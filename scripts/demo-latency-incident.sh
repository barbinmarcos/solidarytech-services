#!/usr/bin/env bash

# =====================================================================
# SolidaryTech - Demonstração SRE / Observabilidade / GitOps
# =====================================================================
#
# Objetivo da demonstração:
#
#   1. Mostrar o sistema saudável.
#   2. Introduzir latência controlada no donation-service.
#   3. Fazer a alteração através do GitOps.
#   4. Gerar tráfego continuamente.
#   5. Observar aumento do p95.
#   6. Demonstrar violação do SLO de latência.
#   7. Esperar o Prometheus disparar o alerta.
#   8. Mostrar Alertmanager / Slack / Grafana / New Relic.
#   9. Remover o incidente via GitOps.
#  10. Acompanhar recuperação.
#  11. Demonstrar RESOLVED.
#  12. Exibir MTTR aproximado.
#
# O script NÃO cria dashboards Grafana.
# O script NÃO altera PVC.
# O script NÃO altera infraestrutura AWS.
#
# =====================================================================

set -u

# =====================================================================
# CONFIGURAÇÃO
# =====================================================================

ROOT_DIR="$HOME/hackathon-DCLT/solidarytech-services"

VALUES_FILE="$ROOT_DIR/helm/donation-service/values.yaml"

NAMESPACE="solidarytech"
MONITORING_NAMESPACE="monitoring"

DEPLOYMENT="donation-service"
SERVICE="donation-service"
ARGO_APP="donation-service"

DONATION_LOCAL_PORT="18082"
DONATION_SERVICE_PORT="8082"

PROM_PORT="19090"
PROM_SERVICE="monitoring-kube-prometheus-prometheus"
PROM_SERVICE_PORT="9090"

ALERTMANAGER_PORT="19093"
ALERTMANAGER_SERVICE="monitoring-kube-prometheus-alertmanager"
ALERTMANAGER_SERVICE_PORT="9093"

GRAFANA_PORT="13000"
GRAFANA_SERVICE="monitoring-grafana"
GRAFANA_SERVICE_PORT="80"

ARGO_LOCAL_PORT="18080"

LATENCY_NORMAL="0"
LATENCY_INCIDENT="2500"

LOAD_PARALLELISM="10"

SLO_LATENCY_SECONDS="2"

P95_TIMEOUT="180"
FIRING_TIMEOUT="240"
RESOLVED_TIMEOUT="300"

PID_DIR="/tmp/solidarytech-demo"
LOG_DIR="${PID_DIR}/logs"

LOAD_PID_FILE="${PID_DIR}/load.pid"

INCIDENT_FILE="${PID_DIR}/incident-start"

mkdir -p "$PID_DIR" "$LOG_DIR"

# =====================================================================
# CORES
# =====================================================================

if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    GREEN=''
    YELLOW=''
    RED=''
    BLUE=''
    CYAN=''
    MAGENTA=''
    BOLD=''
    NC=''
fi

# =====================================================================
# APRESENTAÇÃO
# =====================================================================

clear_screen() {
    clear 2>/dev/null || true
}

title() {

    echo
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo
}

step() {
    echo
    echo -e "${MAGENTA}>>> $1${NC}"
    echo
}

ok() {
    echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERRO]${NC} $*"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

demo() {
    echo -e "${CYAN}[BANCA]${NC} $*"
}

pause_demo() {

    echo
    echo -e "${YELLOW}--------------------------------------------------------------------${NC}"
    read -r -p "Pressione ENTER para continuar a demonstração..."
    echo
}

# =====================================================================
# AUXILIARES
# =====================================================================

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

port_is_open() {

    local port="$1"

    timeout 2 bash -c \
        "echo >/dev/tcp/127.0.0.1/${port}" \
        >/dev/null 2>&1
}

start_pf() {

    local name="$1"
    local namespace="$2"
    local service="$3"
    local local_port="$4"
    local remote_port="$5"

    local logfile="${LOG_DIR}/${name}.log"

    if port_is_open "$local_port"; then
        return 0
    fi

    info "Abrindo port-forward ${name}: localhost:${local_port}"

    nohup kubectl port-forward \
        -n "$namespace" \
        "svc/${service}" \
        "${local_port}:${remote_port}" \
        >"$logfile" 2>&1 &

    for _ in $(seq 1 15); do

        if port_is_open "$local_port"; then
            ok "${name} disponível em localhost:${local_port}"
            return 0
        fi

        sleep 1
    done

    error "Não foi possível criar port-forward para ${name}"

    if [[ -f "$logfile" ]]; then
        tail -10 "$logfile"
    fi

    return 1
}

# =====================================================================
# PORT-FORWARDS
# =====================================================================

check_donation_pf() {

    start_pf \
        "donation" \
        "$NAMESPACE" \
        "$SERVICE" \
        "$DONATION_LOCAL_PORT" \
        "$DONATION_SERVICE_PORT"
}

check_prometheus() {

    start_pf \
        "prometheus" \
        "$MONITORING_NAMESPACE" \
        "$PROM_SERVICE" \
        "$PROM_PORT" \
        "$PROM_SERVICE_PORT"
}

check_alertmanager() {

    start_pf \
        "alertmanager" \
        "$MONITORING_NAMESPACE" \
        "$ALERTMANAGER_SERVICE" \
        "$ALERTMANAGER_PORT" \
        "$ALERTMANAGER_SERVICE_PORT"
}

check_grafana() {

    start_pf \
        "grafana" \
        "$MONITORING_NAMESPACE" \
        "$GRAFANA_SERVICE" \
        "$GRAFANA_PORT" \
        "$GRAFANA_SERVICE_PORT"

    local health

    health=$(curl -s \
        --max-time 5 \
        "http://127.0.0.1:${GRAFANA_PORT}/api/health" \
        2>/dev/null || true)

    if echo "$health" |
        grep -Eq '"database"[[:space:]]*:[[:space:]]*"ok"'; then

        ok "Grafana saudável"

    else

        warn "Grafana respondeu, mas health não pôde ser confirmado"

    fi
}

# =====================================================================
# PROMETHEUS API
# =====================================================================

prom_query() {

    local query="$1"

    curl -sG \
        --max-time 10 \
        "http://127.0.0.1:${PROM_PORT}/api/v1/query" \
        --data-urlencode "query=${query}" \
        2>/dev/null
}

prom_value() {

    local query="$1"

    prom_query "$query" |
        python3 -c '
import json,sys

try:
    data=json.load(sys.stdin)
    result=data["data"]["result"]

    if not result:
        print("0")
    else:
        print(result[0]["value"][1])

except Exception:
    print("0")
'
}

# =====================================================================
# MÉTRICAS
# =====================================================================

get_p95() {

    local query='histogram_quantile(
        0.95,
        sum by (le) (
            rate(
                donation_http_request_duration_seconds_bucket{
                    path="/donations"
                }[2m]
            )
        )
    )'

    prom_value "$query"
}

get_request_rate() {

    local query='sum(
        rate(
            donation_http_requests_total{
                path="/donations"
            }[2m]
        )
    )'

    prom_value "$query"
}

get_alert_state() {

    local query='max(
        ALERTS{
            alertname="DonationServiceHighLatency",
            alertstate="firing"
        }
    ) or vector(0)'

    prom_value "$query"
}

# =====================================================================
# FORMATAÇÃO DE NÚMEROS
# =====================================================================

number_gt() {

    python3 - "$1" "$2" <<'PY'
import sys

try:
    print(
        "true"
        if float(sys.argv[1]) > float(sys.argv[2])
        else "false"
    )
except:
    print("false")
PY
}

format_number() {

    python3 - "$1" <<'PY'
import sys

try:
    print(f"{float(sys.argv[1]):.3f}")
except:
    print(sys.argv[1])
PY
}

# =====================================================================
# GITOPS
# =====================================================================

current_latency() {

    grep -E '^[[:space:]]*simulateLatencyMs:' \
        "$VALUES_FILE" |
        head -1 |
        awk '{print $2}'
}

set_latency_value() {

    local value="$1"

    if [[ ! -f "$VALUES_FILE" ]]; then
        error "Arquivo não encontrado:"
        echo "$VALUES_FILE"
        return 1
    fi

    if ! grep -qE '^[[:space:]]*simulateLatencyMs:' "$VALUES_FILE"; then
        error "simulateLatencyMs não encontrado em values.yaml"
        return 1
    fi

    sed -i -E \
        "s/^([[:space:]]*simulateLatencyMs:).*/\1 ${value}/" \
        "$VALUES_FILE"

    ok "simulateLatencyMs=${value}"
}

gitops_commit_push() {

    local message="$1"

    cd "$ROOT_DIR" || return 1

    git add "$VALUES_FILE"

    if git diff --cached --quiet; then
        warn "Nenhuma alteração Git necessária"
        return 0
    fi

    git commit -m "$message" || return 1

    git push || return 1

    ok "Alteração enviada para o repositório GitOps"
}

argocd_sync() {

    if ! command_exists argocd; then
        warn "argocd CLI não instalado."
        warn "Aguardando auto-sync do ArgoCD."
        return 0
    fi

    if ! port_is_open "$ARGO_LOCAL_PORT"; then
        warn "ArgoCD localhost:${ARGO_LOCAL_PORT} não está acessível."
        warn "O auto-sync poderá realizar a atualização."
        return 0
    fi

    info "Solicitando sync do ArgoCD..."

    argocd app sync "$ARGO_APP" \
        --server "localhost:${ARGO_LOCAL_PORT}" \
        --grpc-web \
        --insecure \
        >/dev/null 2>&1 || {
            warn "Sync manual falhou. Aguardando auto-sync."
            return 0
        }

    ok "ArgoCD sync solicitado"

    info "Aguardando aplicação ficar Healthy/Synced..."

    argocd app wait "$ARGO_APP" \
        --server "localhost:${ARGO_LOCAL_PORT}" \
        --grpc-web \
        --insecure \
        --health \
        --sync \
        --timeout 180 \
        >/dev/null 2>&1 || \
        warn "Timeout no app wait; validaremos pelo Kubernetes."
}

wait_rollout() {

    info "Aguardando rollout do donation-service..."

    if kubectl rollout status \
        deployment/"$DEPLOYMENT" \
        -n "$NAMESPACE" \
        --timeout=180s; then

        ok "Rollout concluído"
    else
        error "Rollout não concluiu"
        return 1
    fi
}

# =====================================================================
# CARGA
# =====================================================================

load_running() {

    if [[ ! -f "$LOAD_PID_FILE" ]]; then
        return 1
    fi

    local pid

    pid=$(cat "$LOAD_PID_FILE" 2>/dev/null || true)

    [[ -n "$pid" ]] &&
        kill -0 "$pid" >/dev/null 2>&1
}

start_load() {

    check_donation_pf || return 1

    if load_running; then
        warn "Carga já está em execução"
        return 0
    fi

    step "INICIANDO CARGA CONTÍNUA"

    demo "Agora começamos a enviar requisições continuamente."
    demo "Isso alimentará o histograma de latência utilizado pelo Prometheus."

    (
        while true; do

            for _ in $(seq 1 "$LOAD_PARALLELISM"); do

                curl -s \
                    --connect-timeout 3 \
                    --max-time 15 \
                    -o /dev/null \
                    -X POST \
                    -H 'Content-Type: application/json' \
                    -d '{
                          "ngo_id": 1,
                          "amount": 100.50,
                          "donor_name": "Banca SRE"
                        }' \
                    "http://127.0.0.1:${DONATION_LOCAL_PORT}/donations" &

            done

            wait || true

            sleep 0.2

        done
    ) >"${LOG_DIR}/load.log" 2>&1 &

    echo $! > "$LOAD_PID_FILE"

    ok "Carga iniciada"
    info "PID: $(cat "$LOAD_PID_FILE")"
}

stop_load() {

    if ! load_running; then
        info "Nenhuma carga ativa"
        rm -f "$LOAD_PID_FILE"
        return 0
    fi

    local pid

    pid=$(cat "$LOAD_PID_FILE")

    info "Encerrando carga..."

    kill "$pid" >/dev/null 2>&1 || true

    pkill -P "$pid" >/dev/null 2>&1 || true

    wait "$pid" 2>/dev/null || true

    rm -f "$LOAD_PID_FILE"

    ok "Carga encerrada"
}

# =====================================================================
# ESPERA P95
# =====================================================================

wait_p95_violation() {

    local elapsed=0

    step "AGUARDANDO VIOLAÇÃO DO SLO"

    demo "SLO de latência definido: p95 <= ${SLO_LATENCY_SECONDS}s."
    demo "O Prometheus está calculando o percentil 95 sobre uma janela de 2 minutos."

    while [[ "$elapsed" -lt "$P95_TIMEOUT" ]]; do

        local p95
        local rate
        local formatted

        p95=$(get_p95)
        rate=$(get_request_rate)

        formatted=$(format_number "$p95")

        printf "\rP95: %-8ss | SLO: %ss | Requests/s: %-8s | aguardando..." \
            "$formatted" \
            "$SLO_LATENCY_SECONDS" \
            "$(format_number "$rate")"

        if [[ "$(number_gt "$p95" "$SLO_LATENCY_SECONDS")" == "true" ]]; then

            echo
            echo

            ok "SLO DE LATÊNCIA VIOLADO"
            echo
            echo "p95 atual : ${formatted}s"
            echo "SLO       : <= ${SLO_LATENCY_SECONDS}s"
            echo

            demo "O serviço continua disponível, porém ficou lento."
            demo "Isso demonstra que disponibilidade e latência são SLIs diferentes."

            return 0
        fi

        sleep 5
        elapsed=$((elapsed + 5))
    done

    echo
    warn "Timeout esperando p95 ultrapassar ${SLO_LATENCY_SECONDS}s"

    return 1
}

# =====================================================================
# ESPERA ALERTA FIRING
# =====================================================================

wait_alert_firing() {

    local elapsed=0

    step "AGUARDANDO ALERTA FIRING"

    demo "A condição de latência já foi detectada."
    demo "Agora o Prometheus precisa respeitar a janela da regra e o 'for' do alerta."
    demo "A carga continuará rodando durante essa espera."

    while [[ "$elapsed" -lt "$FIRING_TIMEOUT" ]]; do

        local state
        local p95

        state=$(get_alert_state)
        p95=$(get_p95)

        printf "\rP95: %-8ss | Alert: %-5s | Tempo: %3ss/%ss" \
            "$(format_number "$p95")" \
            "$state" \
            "$elapsed" \
            "$FIRING_TIMEOUT"

        if [[ "$(number_gt "$state" "0")" == "true" ]]; then

            echo
            echo

            ok "ALERTA DonationServiceHighLatency = FIRING"

            date +%s > "${PID_DIR}/firing-time"

            echo
            demo "Neste momento podemos mostrar para a banca:"
            echo
            echo "  1. Grafana      -> aumento do p95"
            echo "  2. Prometheus   -> alerta FIRING"
            echo "  3. Alertmanager -> alerta ativo"
            echo "  4. Slack        -> notificação do incidente"
            echo "  5. New Relic    -> traces/telemetria"
            echo

            return 0
        fi

        sleep 5
        elapsed=$((elapsed + 5))
    done

    echo
    warn "O alerta não entrou em FIRING dentro do timeout."

    return 1
}

# =====================================================================
# ESPERA ALERTA RESOLVIDO
# =====================================================================

wait_alert_resolved() {

    local elapsed=0

    step "ACOMPANHANDO RECUPERAÇÃO"

    demo "A causa do incidente foi removida."
    demo "Agora aguardamos o Prometheus observar novamente o comportamento saudável."

    while [[ "$elapsed" -lt "$RESOLVED_TIMEOUT" ]]; do

        local state
        local p95

        state=$(get_alert_state)
        p95=$(get_p95)

        printf "\rP95: %-8ss | Alert: %-5s | Tempo: %3ss/%ss" \
            "$(format_number "$p95")" \
            "$state" \
            "$elapsed" \
            "$RESOLVED_TIMEOUT"

        if [[ "$(number_gt "$state" "0")" != "true" ]]; then

            echo
            echo

            ok "ALERTA NÃO ESTÁ MAIS FIRING"

            date +%s > "${PID_DIR}/resolved-time"

            return 0
        fi

        sleep 5
        elapsed=$((elapsed + 5))
    done

    echo
    warn "Timeout aguardando resolução do alerta"

    return 1
}

# =====================================================================
# MTTR
# =====================================================================

show_mttr() {

    if [[ ! -f "${PID_DIR}/firing-time" ]] ||
       [[ ! -f "${PID_DIR}/resolved-time" ]]; then

        return
    fi

    local start
    local end
    local seconds
    local minutes
    local remainder

    start=$(cat "${PID_DIR}/firing-time")
    end=$(cat "${PID_DIR}/resolved-time")

    seconds=$((end - start))

    if [[ "$seconds" -lt 0 ]]; then
        return
    fi

    minutes=$((seconds / 60))
    remainder=$((seconds % 60))

    echo
    echo -e "${CYAN}MTTR aproximado da demonstração:${NC}"
    echo
    echo "  ${minutes} min ${remainder} s"
    echo

    demo "O MTTR representa o intervalo entre a detecção efetiva do incidente"
    demo "e a recuperação observada pelo monitoramento."
}

# =====================================================================
# STATUS
# =====================================================================

show_status() {

    clear_screen
    title "SOLIDARYTECH - STATUS DA DEMONSTRAÇÃO"

    echo "--------------------------------------------------------------------"
    echo "DONATION SERVICE"
    echo "--------------------------------------------------------------------"

    kubectl get deployment "$DEPLOYMENT" \
        -n "$NAMESPACE" \
        2>/dev/null || true

    echo

    kubectl get pods \
        -n "$NAMESPACE" \
        -o wide \
        2>/dev/null |
        grep donation || true

    echo
    echo "--------------------------------------------------------------------"
    echo "HPA"
    echo "--------------------------------------------------------------------"

    kubectl get hpa "$DEPLOYMENT" \
        -n "$NAMESPACE" \
        2>/dev/null || true

    echo
    echo "--------------------------------------------------------------------"
    echo "LATÊNCIA CONFIGURADA"
    echo "--------------------------------------------------------------------"

    echo "simulateLatencyMs = $(current_latency)"

    echo
    echo "--------------------------------------------------------------------"
    echo "PROMETHEUS"
    echo "--------------------------------------------------------------------"

    check_prometheus >/dev/null 2>&1 || true

    P95=$(get_p95)
    RATE=$(get_request_rate)
    ALERT=$(get_alert_state)

    echo "p95 atual:      $(format_number "$P95") s"
    echo "SLO:            <= ${SLO_LATENCY_SECONDS} s"
    echo "Requests/s:     $(format_number "$RATE")"
    echo "Alert FIRING:   $ALERT"

    echo
    echo "--------------------------------------------------------------------"
    echo "CARGA"
    echo "--------------------------------------------------------------------"

    if load_running; then
        echo -e "${RED}ATIVA${NC}"
    else
        echo -e "${GREEN}PARADA${NC}"
    fi

    echo
    echo "--------------------------------------------------------------------"
    echo "OBSERVABILIDADE"
    echo "--------------------------------------------------------------------"

    echo "Grafana:       http://localhost:${GRAFANA_PORT}"
    echo "Prometheus:    http://localhost:${PROM_PORT}"
    echo "Alertmanager:  http://localhost:${ALERTMANAGER_PORT}"
    echo "ArgoCD:        https://localhost:${ARGO_LOCAL_PORT}"

    echo
}

# =====================================================================
# PRÉ-CHECK
# =====================================================================

precheck() {

    clear_screen

    title "SOLIDARYTECH - PRÉ-CHECK DA DEMONSTRAÇÃO"

    demo "Antes de iniciar o incidente, validamos que o ambiente está saudável."
    echo

    local failed=0

    # ---------------------------------------------------------
    # Dependências
    # ---------------------------------------------------------

    step "1. Dependências"

    for cmd in kubectl git curl python3 timeout; do

        if command_exists "$cmd"; then
            ok "$cmd"
        else
            error "$cmd não encontrado"
            failed=1
        fi

    done

    # ---------------------------------------------------------
    # Kubernetes
    # ---------------------------------------------------------

    step "2. Kubernetes"

    if kubectl get --raw='/readyz' \
        --request-timeout=10s \
        >/dev/null 2>&1; then

        ok "Kubernetes API saudável"

    else

        error "Kubernetes API indisponível"
        failed=1

    fi

    # ---------------------------------------------------------
    # Donation
    # ---------------------------------------------------------

    step "3. Donation Service"

    if kubectl get deployment "$DEPLOYMENT" \
        -n "$NAMESPACE" \
        >/dev/null 2>&1; then

        ok "Deployment encontrado"

        kubectl get deployment "$DEPLOYMENT" \
            -n "$NAMESPACE"

    else

        error "Deployment não encontrado"
        failed=1

    fi

    # ---------------------------------------------------------
    # Donation health
    # ---------------------------------------------------------

    step "4. Health Check"

    if check_donation_pf; then

        HTTP=$(curl -s \
            -o /dev/null \
            -w '%{http_code}' \
            --max-time 5 \
            "http://127.0.0.1:${DONATION_LOCAL_PORT}/health" \
            2>/dev/null || echo 000)

        if [[ "$HTTP" == "200" ]]; then
            ok "Donation Service HTTP 200"
        else
            error "Donation Service HTTP ${HTTP}"
            failed=1
        fi

    else

        failed=1

    fi

    # ---------------------------------------------------------
    # Prometheus
    # ---------------------------------------------------------

    step "5. Prometheus"

    if check_prometheus; then

        HTTP=$(curl -s \
            -o /dev/null \
            -w '%{http_code}' \
            --max-time 5 \
            "http://127.0.0.1:${PROM_PORT}/-/ready" \
            2>/dev/null || echo 000)

        if [[ "$HTTP" == "200" ]]; then
            ok "Prometheus Ready"
        else
            error "Prometheus HTTP ${HTTP}"
            failed=1
        fi

    else

        failed=1

    fi

    # ---------------------------------------------------------
    # Alertmanager
    # ---------------------------------------------------------

    step "6. Alertmanager"

    if check_alertmanager; then

        HTTP=$(curl -s \
            -o /dev/null \
            -w '%{http_code}' \
            --max-time 5 \
            "http://127.0.0.1:${ALERTMANAGER_PORT}/-/ready" \
            2>/dev/null || echo 000)

        if [[ "$HTTP" == "200" ]]; then
            ok "Alertmanager Ready"
        else
            warn "Alertmanager HTTP ${HTTP}"
        fi

    else

        warn "Alertmanager não pôde ser validado"
    fi

    # ---------------------------------------------------------
    # Grafana
    # ---------------------------------------------------------

    step "7. Grafana"

    if check_grafana; then
        ok "Grafana acessível"
    else
        warn "Grafana não pôde ser validado"
    fi

    # ---------------------------------------------------------
    # HPA
    # ---------------------------------------------------------

    step "8. HPA"

    if kubectl get hpa "$DEPLOYMENT" \
        -n "$NAMESPACE" \
        >/dev/null 2>&1; then

        ok "HPA configurado"

        kubectl get hpa "$DEPLOYMENT" \
            -n "$NAMESPACE"

    else

        warn "HPA não encontrado"
    fi

    # ---------------------------------------------------------
    # Alert Rule
    # ---------------------------------------------------------

    step "9. Alert Rule"

    if kubectl get prometheusrule -A \
        -o yaml \
        2>/dev/null |
        grep -q 'DonationServiceHighLatency'; then

        ok "DonationServiceHighLatency configurado"

    else

        error "DonationServiceHighLatency não encontrado"
        failed=1

    fi

    # ---------------------------------------------------------
    # Latência inicial
    # ---------------------------------------------------------

    step "10. Estado inicial"

    LATENCY=$(current_latency)

    echo "simulateLatencyMs = ${LATENCY:-desconhecido}"

    if [[ "$LATENCY" == "$LATENCY_NORMAL" ]]; then
        ok "Sistema configurado em estado NORMAL"
    else
        warn "Latência simulada não está em zero"
    fi

    echo

    if [[ "$failed" -eq 0 ]]; then

        echo -e "${GREEN}======================================================================${NC}"
        echo -e "${GREEN}       AMBIENTE PRONTO PARA A DEMONSTRAÇÃO DA BANCA${NC}"
        echo -e "${GREEN}======================================================================${NC}"

    else

        echo -e "${RED}======================================================================${NC}"
        echo -e "${RED}       EXISTEM PROBLEMAS QUE DEVEM SER CORRIGIDOS${NC}"
        echo -e "${RED}======================================================================${NC}"

    fi

    echo
}

# =====================================================================
# INCIDENTE
# =====================================================================

start_incident() {

    clear_screen

    title "SOLIDARYTECH - SIMULAÇÃO DE INCIDENTE"

    echo -e "${BOLD}Cenário:${NC}"
    echo
    echo "O donation-service começa a apresentar degradação de desempenho."
    echo
    echo "O serviço continuará respondendo, porém cada requisição terá"
    echo "aproximadamente ${LATENCY_INCIDENT}ms de latência artificial."
    echo

    demo "Objetivo: demonstrar detecção, observabilidade, alertas e recuperação."

    pause_demo

    # ---------------------------------------------------------
    # Estado antes
    # ---------------------------------------------------------

    step "ETAPA 1 - ESTADO SAUDÁVEL"

    echo "Deployment:"
    kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE"

    echo
    echo "HPA:"
    kubectl get hpa "$DEPLOYMENT" -n "$NAMESPACE" || true

    echo
    echo "Latência configurada:"
    echo "$(current_latency) ms"

    check_prometheus || return 1

    P95_BEFORE=$(get_p95)

    echo
    echo "p95 antes do incidente: $(format_number "$P95_BEFORE") s"

    demo "Este é nosso baseline antes da falha."

    pause_demo

    # ---------------------------------------------------------
    # Registrar incidente
    # ---------------------------------------------------------

    date +%s > "$INCIDENT_FILE"

    rm -f \
        "${PID_DIR}/firing-time" \
        "${PID_DIR}/resolved-time"

    # ---------------------------------------------------------
    # GitOps
    # ---------------------------------------------------------

    step "ETAPA 2 - INTRODUZINDO O INCIDENTE VIA GITOPS"

    demo "Em vez de alterar diretamente o Deployment com kubectl,"
    demo "mudaremos o estado desejado versionado no Git."

    echo
    echo "Alteração:"
    echo
    echo "simulateLatencyMs: ${LATENCY_NORMAL}"
    echo "            ↓"
    echo "simulateLatencyMs: ${LATENCY_INCIDENT}"
    echo

    set_latency_value "$LATENCY_INCIDENT" || return 1

    gitops_commit_push \
        "demo: simulate donation-service latency ${LATENCY_INCIDENT}ms" \
        || return 1

    argocd_sync

    wait_rollout || return 1

    echo
    kubectl get pods -n "$NAMESPACE" -o wide | grep donation || true

    echo
    demo "O Kubernetes convergiu para o novo estado definido no Git."

    # ---------------------------------------------------------
    # Confirmar env
    # ---------------------------------------------------------

    step "ETAPA 3 - CONFIRMANDO A CONFIGURAÇÃO"

    ENV_VALUE=$(kubectl get deployment "$DEPLOYMENT" \
        -n "$NAMESPACE" \
        -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="SIMULATE_LATENCY_MS")].value}' \
        2>/dev/null || true)

    echo "SIMULATE_LATENCY_MS=${ENV_VALUE:-não encontrado}"

    if [[ "$ENV_VALUE" == "$LATENCY_INCIDENT" ]]; then
        ok "Latência artificial aplicada"
    else
        warn "Valor esperado ${LATENCY_INCIDENT}; encontrado ${ENV_VALUE:-vazio}"
    fi

    # ---------------------------------------------------------
    # Teste simples
    # ---------------------------------------------------------

    step "ETAPA 4 - EXPERIÊNCIA DO USUÁRIO"

    check_donation_pf || return 1

    demo "Agora medimos uma requisição real."

    echo

    curl -s \
        -o /dev/null \
        -w 'HTTP=%{http_code} | Tempo total=%{time_total}s\n' \
        --max-time 15 \
        -X POST \
        -H 'Content-Type: application/json' \
        -d '{
              "ngo_id": 1,
              "amount": 50,
              "donor_name": "Banca"
            }' \
        "http://127.0.0.1:${DONATION_LOCAL_PORT}/donations"

    echo
    demo "Observe: o endpoint continua disponível, mas sua latência aumentou."

    # ---------------------------------------------------------
    # Carga
    # ---------------------------------------------------------

    start_load || return 1

    # ---------------------------------------------------------
    # SLO
    # ---------------------------------------------------------

    wait_p95_violation || true

    # ---------------------------------------------------------
    # Alert
    # ---------------------------------------------------------

    wait_alert_firing || true

    # ---------------------------------------------------------
    # Evidências
    # ---------------------------------------------------------

    step "ETAPA 5 - EVIDÊNCIAS DO INCIDENTE"

    P95=$(get_p95)
    RATE=$(get_request_rate)
    ALERT=$(get_alert_state)

    echo "p95:            $(format_number "$P95") s"
    echo "SLO:            <= ${SLO_LATENCY_SECONDS} s"
    echo "Requests/s:     $(format_number "$RATE")"
    echo "Alert FIRING:   $ALERT"

    echo
    kubectl get hpa "$DEPLOYMENT" -n "$NAMESPACE" || true

    echo
    kubectl get pods -n "$NAMESPACE" -o wide | grep donation || true

    echo
    echo -e "${YELLOW}======================================================================${NC}"
    echo -e "${YELLOW}             PAUSA PARA APRESENTAÇÃO À BANCA${NC}"
    echo -e "${YELLOW}======================================================================${NC}"
    echo
    echo "A carga CONTINUA ativa."
    echo
    echo "Mostre agora:"
    echo
    echo "  Grafana"
    echo "    http://localhost:${GRAFANA_PORT}"
    echo
    echo "    • p95 do donation-service"
    echo "    • linha do SLO = 2 segundos"
    echo "    • Availability SLI"
    echo "    • Alert Status = FIRING"
    echo "    • HPA / réplicas"
    echo
    echo "  Prometheus"
    echo "    http://localhost:${PROM_PORT}"
    echo
    echo "  Alertmanager"
    echo "    http://localhost:${ALERTMANAGER_PORT}"
    echo
    echo "  Slack"
    echo "    • mensagem do DonationServiceHighLatency"
    echo
    echo "  New Relic"
    echo "    • traces do donation-service"
    echo "    • duração elevada"
    echo
    echo "IMPORTANTE:"
    echo
    echo "  NÃO escolha a opção de recuperação enquanto estiver mostrando"
    echo "  o incidente. A carga continuará sustentando a condição."
    echo

    pause_demo
}

# =====================================================================
# RECUPERAÇÃO
# =====================================================================

recover_service() {

    clear_screen

    title "SOLIDARYTECH - RECUPERAÇÃO DO INCIDENTE"

    demo "Agora executaremos a mitigação."
    demo "A alteração será novamente realizada pelo GitOps."

    echo
    echo "Estado desejado:"
    echo
    echo "simulateLatencyMs: ${LATENCY_INCIDENT}"
    echo "            ↓"
    echo "simulateLatencyMs: ${LATENCY_NORMAL}"

    pause_demo

    step "ETAPA 1 - INTERROMPENDO A CARGA"

    stop_load

    step "ETAPA 2 - REMOVENDO A LATÊNCIA VIA GITOPS"

    set_latency_value "$LATENCY_NORMAL" || return 1

    gitops_commit_push \
        "demo: recover donation-service latency" \
        || return 1

    argocd_sync

    wait_rollout || return 1

    step "ETAPA 3 - VALIDANDO A RECUPERAÇÃO"

    ENV_VALUE=$(kubectl get deployment "$DEPLOYMENT" \
        -n "$NAMESPACE" \
        -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="SIMULATE_LATENCY_MS")].value}' \
        2>/dev/null || true)

    echo "SIMULATE_LATENCY_MS=${ENV_VALUE:-não encontrado}"

    check_donation_pf || true

    echo

    curl -s \
        -o /dev/null \
        -w 'HTTP=%{http_code} | Tempo total=%{time_total}s\n' \
        --max-time 10 \
        "http://127.0.0.1:${DONATION_LOCAL_PORT}/health" \
        || true

    echo
    demo "A causa da degradação foi removida."

    # ---------------------------------------------------------
    # Pequena carga saudável
    # ---------------------------------------------------------

    step "ETAPA 4 - GERANDO AMOSTRAS SAUDÁVEIS"

    demo "Geraremos algumas requisições normais para acelerar"
    demo "a atualização das métricas do Prometheus."

    for _ in $(seq 1 30); do

        curl -s \
            --max-time 5 \
            -o /dev/null \
            -X POST \
            -H 'Content-Type: application/json' \
            -d '{
                  "ngo_id": 1,
                  "amount": 10,
                  "donor_name": "Recovery"
                }' \
            "http://127.0.0.1:${DONATION_LOCAL_PORT}/donations" &

        sleep 0.1

    done

    wait || true

    # ---------------------------------------------------------
    # Alert resolved
    # ---------------------------------------------------------

    check_prometheus || true

    wait_alert_resolved || true

    # ---------------------------------------------------------
    # Resultado
    # ---------------------------------------------------------

    step "ETAPA 5 - RESULTADO"

    P95=$(get_p95)
    ALERT=$(get_alert_state)

    echo "p95 atual:      $(format_number "$P95") s"
    echo "SLO:            <= ${SLO_LATENCY_SECONDS} s"
    echo "Alert FIRING:   $ALERT"

    echo

    kubectl get deployment "$DEPLOYMENT" \
        -n "$NAMESPACE" || true

    echo

    kubectl get hpa "$DEPLOYMENT" \
        -n "$NAMESPACE" || true

    show_mttr

    echo
    echo -e "${GREEN}======================================================================${NC}"
    echo -e "${GREEN}                 SERVIÇO RECUPERADO${NC}"
    echo -e "${GREEN}======================================================================${NC}"
    echo

    demo "Ciclo demonstrado:"
    echo
    echo "  Detecção"
    echo "      ↓"
    echo "  Observabilidade"
    echo "      ↓"
    echo "  Alerta"
    echo "      ↓"
    echo "  Notificação"
    echo "      ↓"
    echo "  Mitigação via GitOps"
    echo "      ↓"
    echo "  Recuperação"
    echo "      ↓"
    echo "  RESOLVED"
    echo

    pause_demo
}

# =====================================================================
# CLEANUP
# =====================================================================

cleanup_demo() {

    clear_screen

    title "SOLIDARYTECH - LIMPEZA LOCAL"

    stop_load

    rm -f \
        "${PID_DIR}/firing-time" \
        "${PID_DIR}/resolved-time" \
        "$INCIDENT_FILE"

    ok "Processos de carga removidos"

    echo
    info "Os port-forwards foram mantidos para facilitar a banca."
    info "Nenhum dashboard foi alterado."
    info "Nenhum recurso AWS foi removido."

    echo
}

# =====================================================================
# ROTEIRO
# =====================================================================

show_script_explanation() {

    clear_screen

    title "SOLIDARYTECH - ROTEIRO DA BANCA"

    cat <<TEXT
Este roteiro demonstra um incidente completo de SRE.

CENÁRIO

  O donation-service está saudável.

              ↓

  Introduzimos 2500 ms de latência via GitOps.

              ↓

  ArgoCD sincroniza o novo estado.

              ↓

  Kubernetes executa o rollout.

              ↓

  Geramos tráfego continuamente.

              ↓

  Prometheus coleta as métricas.

              ↓

  p95 ultrapassa o SLO de 2 segundos.

              ↓

  DonationServiceHighLatency entra em FIRING.

              ↓

  Alertmanager processa o alerta.

              ↓

  Slack recebe a notificação.

              ↓

  Grafana mostra a degradação.

              ↓

  New Relic mostra traces com duração elevada.

              ↓

  Executamos mitigação via GitOps.

              ↓

  O serviço retorna ao estado normal.

              ↓

  Prometheus observa recuperação.

              ↓

  Alertmanager envia RESOLVED.


PONTOS IMPORTANTES PARA EXPLICAR

  • Git é a fonte da verdade.

  • ArgoCD realiza a convergência do estado.

  • Prometheus coleta os SLIs.

  • Grafana apresenta os indicadores.

  • Alertmanager gerencia o ciclo do alerta.

  • Slack representa o canal operacional.

  • OpenTelemetry/New Relic fornece tracing.

  • HPA demonstra elasticidade.

  • Disponibilidade e latência são SLIs independentes.

  • O MTTR demonstra o tempo de recuperação operacional.

TEXT

    pause_demo
}

# =====================================================================
# MENU
# =====================================================================

menu() {

    while true; do

        clear_screen

        echo -e "${CYAN}"
        echo "======================================================================"
        echo "                  SOLIDARYTECH - DEMO DA BANCA"
        echo "======================================================================"
        echo -e "${NC}"

        echo "  [1] PRÉ-CHECK DA BANCA"
        echo
        echo "  [2] EXPLICAR ARQUITETURA DA DEMONSTRAÇÃO"
        echo
        echo "  [3] INICIAR INCIDENTE DE LATÊNCIA"
        echo
        echo "  [4] STATUS / EVIDÊNCIAS"
        echo
        echo "  [5] RECUPERAR SERVIÇO"
        echo
        echo "  [6] LIMPAR PROCESSOS DA DEMO"
        echo
        echo "  [0] SAIR"
        echo

        echo "--------------------------------------------------------------------"

        if load_running; then
            echo -e "Carga: ${RED}ATIVA${NC}"
        else
            echo -e "Carga: ${GREEN}PARADA${NC}"
        fi

        echo "Latência configurada: $(current_latency 2>/dev/null || echo '?') ms"

        echo "--------------------------------------------------------------------"
        echo

        read -r -p "Escolha uma opção: " option

        case "$option" in

            1)
                precheck
                pause_demo
                ;;

            2)
                show_script_explanation
                ;;

            3)
                start_incident
                ;;

            4)
                show_status
                pause_demo
                ;;

            5)
                recover_service
                ;;

            6)
                cleanup_demo
                pause_demo
                ;;

            0)

                echo

                if load_running; then

                    warn "Existe uma carga ativa."

                    read -r -p \
                        "Deseja encerrá-la antes de sair? [s/N]: " answer

                    if [[ "$answer" =~ ^[Ss]$ ]]; then
                        stop_load
                    fi

                fi

                echo
                echo "Encerrando demonstração."
                echo

                exit 0
                ;;

            *)

                warn "Opção inválida"
                sleep 2
                ;;

        esac

    done
}

# =====================================================================
# INÍCIO
# =====================================================================

trap '
echo
warn "Interrupção recebida."
if load_running; then
    warn "A carga continua ativa."
    warn "Use a opção [6] para encerrá-la ou finalize manualmente."
fi
' INT

menu
