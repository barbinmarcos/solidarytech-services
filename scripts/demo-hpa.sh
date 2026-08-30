#!/usr/bin/env bash

set -u

NAMESPACE="solidarytech"
DEPLOYMENT="donation-service"
HPA="donation-service"

# A carga agora é gerada LOCALMENTE.
# Isso evita consumir um Pod/slot do próprio cluster que está sendo testado.
LOCAL_PORT="${LOCAL_PORT:-18082}"
SERVICE_PORT="8082"
SERVICE_URL="http://127.0.0.1:${LOCAL_PORT}/health"

# Quantidade de workers HTTP paralelos na máquina local.
# Exemplo:
# CONCURRENCY=150 ./scripts/demo-hpa.sh
CONCURRENCY="${CONCURRENCY:-80}"

WAIT_SCALE_UP="${WAIT_SCALE_UP:-240}"
WAIT_SCALE_DOWN="${WAIT_SCALE_DOWN:-420}"

RUNTIME_DIR="/tmp/solidarytech-hpa-demo"
LOAD_PID_FILE="${RUNTIME_DIR}/load.pid"
PF_PID_FILE="${RUNTIME_DIR}/port-forward.pid"
LOAD_LOG="${RUNTIME_DIR}/load.log"
PF_LOG="${RUNTIME_DIR}/port-forward.log"

# Nome usado apenas para remover um eventual gerador antigo
# criado pela versão anterior do script.
LEGACY_LOAD_POD="donation-hpa-load"

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m"

mkdir -p "$RUNTIME_DIR"

header() {
    clear
    echo
    echo "============================================================"
    echo " SolidaryTech - Demonstração HPA"
    echo "============================================================"
    echo
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
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

pause() {
    echo
    read -rp "Pressione ENTER para continuar..."
}

pid_running() {
    local pid="${1:-}"

    [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1
}

load_is_active() {
    if [ ! -f "$LOAD_PID_FILE" ]; then
        return 1
    fi

    local pid
    pid=$(cat "$LOAD_PID_FILE" 2>/dev/null || true)

    if pid_running "$pid"; then
        return 0
    fi

    rm -f "$LOAD_PID_FILE"
    return 1
}

check_dependencies() {
    local missing=0

    for cmd in kubectl curl setsid; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "$cmd não encontrado."
            missing=1
        fi
    done

    if [ "$missing" -ne 0 ]; then
        return 1
    fi

    kubectl cluster-info >/dev/null 2>&1 || {
        error "Sem acesso ao cluster Kubernetes."
        return 1
    }

    return 0
}

ensure_port_forward() {
    # Se o endpoint já responde, aproveitamos o port-forward existente.
    if curl -fsS \
        --connect-timeout 2 \
        --max-time 3 \
        "$SERVICE_URL" >/dev/null 2>&1; then

        ok "Donation acessível em $SERVICE_URL"
        return 0
    fi

    info "Donation não está acessível em localhost:${LOCAL_PORT}."
    info "Iniciando port-forward local..."

    # Remove referência velha, caso exista.
    if [ -f "$PF_PID_FILE" ]; then
        local old_pid
        old_pid=$(cat "$PF_PID_FILE" 2>/dev/null || true)

        if pid_running "$old_pid"; then
            kill "$old_pid" >/dev/null 2>&1 || true
        fi

        rm -f "$PF_PID_FILE"
    fi

    kubectl port-forward \
        -n "$NAMESPACE" \
        svc/"$DEPLOYMENT" \
        "${LOCAL_PORT}:${SERVICE_PORT}" \
        >"$PF_LOG" 2>&1 &

    local pf_pid=$!
    echo "$pf_pid" > "$PF_PID_FILE"

    sleep 3

    if curl -fsS \
        --connect-timeout 2 \
        --max-time 3 \
        "$SERVICE_URL" >/dev/null 2>&1; then

        ok "Port-forward iniciado em localhost:${LOCAL_PORT}"
        return 0
    fi

    error "Não foi possível acessar $SERVICE_URL"

    if pid_running "$pf_pid"; then
        kill "$pf_pid" >/dev/null 2>&1 || true
    fi

    rm -f "$PF_PID_FILE"

    echo
    warn "Últimas linhas do port-forward:"
    tail -n 10 "$PF_LOG" 2>/dev/null || true

    return 1
}

show_hpa() {
    echo
    echo "---------------- HPA ----------------"
    kubectl get hpa "$HPA" -n "$NAMESPACE"
    echo

    echo "------------- DEPLOYMENT ------------"
    kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE"
    echo

    echo "---------------- PODS ---------------"
    kubectl get pods -n "$NAMESPACE" \
        -l app.kubernetes.io/name="$DEPLOYMENT" \
        -o wide 2>/dev/null || \
    kubectl get pods -n "$NAMESPACE" | grep "$DEPLOYMENT" || true

    echo
    echo "-------------- CPU PODS -------------"
    kubectl top pods -n "$NAMESPACE" 2>/dev/null \
        | grep "$DEPLOYMENT" || \
        warn "Metrics Server ainda não retornou métricas."
}

precheck() {
    header

    echo "[1/6] Dependências / Kubernetes"
    if ! check_dependencies; then
        return 1
    fi
    ok "Cluster acessível"

    echo
    echo "[2/6] Deployment"
    if ! kubectl get deployment "$DEPLOYMENT" \
        -n "$NAMESPACE" >/dev/null 2>&1; then

        error "Deployment $DEPLOYMENT não encontrado."
        return 1
    fi
    ok "$DEPLOYMENT encontrado"

    echo
    echo "[3/6] HPA"
    if ! kubectl get hpa "$HPA" \
        -n "$NAMESPACE" >/dev/null 2>&1; then

        error "HPA $HPA não encontrado."
        return 1
    fi

    local min_replicas
    local max_replicas

    min_replicas=$(kubectl get hpa "$HPA" \
        -n "$NAMESPACE" \
        -o jsonpath='{.spec.minReplicas}')

    max_replicas=$(kubectl get hpa "$HPA" \
        -n "$NAMESPACE" \
        -o jsonpath='{.spec.maxReplicas}')

    ok "HPA encontrado"
    info "MinReplicas: $min_replicas"
    info "MaxReplicas: $max_replicas"

    echo
    echo "[4/6] Metrics Server"
    if kubectl top pods -n "$NAMESPACE" >/dev/null 2>&1; then
        ok "Métricas de CPU disponíveis"
    else
        warn "kubectl top ainda não está retornando métricas."
    fi

    echo
    echo "[5/6] Donation / port-forward"
    if ! ensure_port_forward; then
        return 1
    fi

    echo
    echo "[6/6] Estado inicial"
    show_hpa

    echo
    ok "Pré-check concluído."
    echo
    info "A carga será gerada FORA do EKS."
    info "Nenhum Pod de carga consumirá capacidade do cluster."
}

delete_legacy_load_pod() {
    if kubectl get pod "$LEGACY_LOAD_POD" \
        -n "$NAMESPACE" >/dev/null 2>&1; then

        warn "Encontrado Pod de carga da versão antiga."
        info "Removendo $LEGACY_LOAD_POD..."

        kubectl delete pod "$LEGACY_LOAD_POD" \
            -n "$NAMESPACE" \
            --ignore-not-found=true \
            --wait=false >/dev/null 2>&1 || true

        ok "Pod legado removido."
    fi
}

delete_load() {
    if ! load_is_active; then
        rm -f "$LOAD_PID_FILE"
        info "Nenhum gerador de carga local ativo."
        return 0
    fi

    local pid
    pid=$(cat "$LOAD_PID_FILE")

    info "Encerrando gerador de carga local (PID $pid)..."

    # O processo foi iniciado com setsid.
    # Encerra o grupo inteiro, incluindo todos os workers curl.
    kill -- "-$pid" >/dev/null 2>&1 || \
        kill "$pid" >/dev/null 2>&1 || true

    sleep 1

    if pid_running "$pid"; then
        kill -9 -- "-$pid" >/dev/null 2>&1 || \
            kill -9 "$pid" >/dev/null 2>&1 || true
    fi

    rm -f "$LOAD_PID_FILE"

    ok "Carga local interrompida."
}

start_local_load() {
    if load_is_active; then
        warn "Já existe um gerador de carga local ativo."
        return 0
    fi

    : > "$LOAD_LOG"

    info "Criando $CONCURRENCY workers HTTP locais..."

    LOAD_URL="$SERVICE_URL" \
    WORKERS="$CONCURRENCY" \
    setsid bash -c '
        i=1

        while [ "$i" -le "$WORKERS" ]; do
            (
                while true; do
                    curl -s \
                        --connect-timeout 2 \
                        --max-time 3 \
                        -o /dev/null \
                        "$LOAD_URL" || true
                done
            ) &

            i=$((i + 1))
        done

        wait
    ' >>"$LOAD_LOG" 2>&1 &

    local load_pid=$!
    echo "$load_pid" > "$LOAD_PID_FILE"

    sleep 2

    if pid_running "$load_pid"; then
        ok "Gerador de carga local ativo."
        info "PID: $load_pid"
        return 0
    fi

    error "Gerador de carga terminou inesperadamente."
    rm -f "$LOAD_PID_FILE"
    return 1
}

start_load() {
    header

    if ! check_dependencies; then
        return 1
    fi

    delete_legacy_load_pod
    delete_load

    if ! ensure_port_forward; then
        return 1
    fi

    echo
    echo "============================================================"
    echo " INICIANDO TESTE DE SCALE-OUT"
    echo "============================================================"
    echo
    echo "Origem:        máquina local"
    echo "Destino:       $SERVICE_URL"
    echo "Concorrência:  $CONCURRENCY workers"
    echo
    echo "A carga utiliza GET /health."
    echo "Nenhuma doação será criada no PostgreSQL."
    echo "Nenhum Pod de carga será criado no EKS."
    echo

    local before
    before=$(kubectl get deployment "$DEPLOYMENT" \
        -n "$NAMESPACE" \
        -o jsonpath='{.status.replicas}')

    before="${before:-0}"

    local max_replicas
    max_replicas=$(kubectl get hpa "$HPA" \
        -n "$NAMESPACE" \
        -o jsonpath='{.spec.maxReplicas}')

    max_replicas="${max_replicas:-4}"

    info "Réplicas antes do teste: $before"
    info "Máximo configurado no HPA: $max_replicas"

    if ! start_local_load; then
        return 1
    fi

    echo
    info "O HPA precisa de algumas janelas de métricas para reagir."
    echo

    local start
    local deadline
    local scaled=0

    start=$(date +%s)
    deadline=$((start + WAIT_SCALE_UP))

    while true; do
        local now
        local current

        now=$(date +%s)

        current=$(kubectl get deployment "$DEPLOYMENT" \
            -n "$NAMESPACE" \
            -o jsonpath='{.status.replicas}')

        current="${current:-0}"

        echo
        echo "------------------------------------------------------------"
        date '+%H:%M:%S'
        kubectl get hpa "$HPA" -n "$NAMESPACE"

        echo
        kubectl top pods -n "$NAMESPACE" 2>/dev/null \
            | grep "$DEPLOYMENT" || true

        if [ "$current" -gt "$before" ] && [ "$scaled" -eq 0 ]; then
            echo
            ok "HPA ESCALOU!"
            echo
            echo "Réplicas:"
            echo "  Antes : $before"
            echo "  Agora : $current"
            echo
            echo "O scale-out foi provocado por aumento de CPU."
            echo
            info "Continuando a carga para observar se alcança MaxReplicas=$max_replicas..."
            scaled=1
        fi

        if [ "$current" -ge "$max_replicas" ]; then
            echo
            ok "HPA ATINGIU O MÁXIMO CONFIGURADO"
            echo
            echo "Réplicas atuais: $current"
            echo "MaxReplicas:      $max_replicas"
            echo
            echo "A carga continuará ativa para coleta de evidências."
            return 0
        fi

        if [ "$now" -ge "$deadline" ]; then
            echo

            if [ "$scaled" -eq 1 ]; then
                ok "Scale-out confirmado."
                info "Réplicas atuais: $current"
                info "Não foi necessário atingir MaxReplicas para comprovar o HPA."
            else
                warn "Não houve scale-out dentro de ${WAIT_SCALE_UP}s."
            fi

            echo
            echo "A carga continuará ativa."
            echo
            echo "Para aumentar a pressão de CPU, encerre a carga e execute:"
            echo
            echo "  CONCURRENCY=150 ./scripts/demo-hpa.sh"
            echo

            return 0
        fi

        sleep 15
    done
}

status() {
    header

    echo "============================================================"
    echo " STATUS DA DEMONSTRAÇÃO"
    echo "============================================================"

    show_hpa

    echo
    echo "----------- GERADOR DE CARGA ----------"

    if load_is_active; then
        local pid
        pid=$(cat "$LOAD_PID_FILE")

        ok "Carga HPA LOCAL ATIVA"
        info "PID:          $pid"
        info "Workers:      $CONCURRENCY"
        info "Destino:      $SERVICE_URL"
    else
        warn "Carga HPA INATIVA"
    fi

    echo
    echo "--------- CAPACIDADE DE PODS ---------"

    kubectl get nodes \
        -o custom-columns='NAME:.metadata.name,PODS:.status.allocatable.pods' \
        --no-headers 2>/dev/null || true
}

stop_and_watch() {
    header

    echo "============================================================"
    echo " ENCERRANDO CARGA / OBSERVANDO SCALE-DOWN"
    echo "============================================================"
    echo

    delete_load

    echo
    info "Carga removida."
    info "Agora a CPU deve cair."
    echo
    warn "O scale-down do HPA não é instantâneo."
    echo "Kubernetes utiliza uma janela de estabilização"
    echo "para evitar flapping de réplicas."
    echo

    local min_replicas
    min_replicas=$(kubectl get hpa "$HPA" \
        -n "$NAMESPACE" \
        -o jsonpath='{.spec.minReplicas}')

    min_replicas="${min_replicas:-1}"

    local start
    local deadline

    start=$(date +%s)
    deadline=$((start + WAIT_SCALE_DOWN))

    while true; do
        local now
        local current

        now=$(date +%s)

        current=$(kubectl get deployment "$DEPLOYMENT" \
            -n "$NAMESPACE" \
            -o jsonpath='{.status.replicas}')

        current="${current:-0}"

        echo
        echo "------------------------------------------------------------"
        date '+%H:%M:%S'
        kubectl get hpa "$HPA" -n "$NAMESPACE"

        echo
        kubectl top pods -n "$NAMESPACE" 2>/dev/null \
            | grep "$DEPLOYMENT" || true

        if [ "$current" -le "$min_replicas" ]; then
            echo
            ok "SCALE-DOWN CONCLUÍDO"
            echo
            echo "Réplicas atuais: $current"
            echo "MinReplicas:      $min_replicas"
            return 0
        fi

        if [ "$now" -ge "$deadline" ]; then
            echo
            warn "Scale-down ainda não terminou dentro de ${WAIT_SCALE_DOWN}s."
            echo
            echo "Isso não representa necessariamente erro."
            echo "O HPA utiliza estabilização para evitar flapping."
            return 0
        fi

        sleep 15
    done
}

watch_live() {
    header

    echo "Atualização a cada 5 segundos."
    echo "CTRL+C para sair."
    echo
    sleep 2

    watch -n 5 "
      echo '=== HPA ===';
      kubectl get hpa $HPA -n $NAMESPACE;
      echo;
      echo '=== PODS ===';
      kubectl get pods -n $NAMESPACE | grep $DEPLOYMENT;
      echo;
      echo '=== CPU ===';
      kubectl top pods -n $NAMESPACE 2>/dev/null | grep $DEPLOYMENT || true
    "
}

cleanup() {
    header

    delete_load
    delete_legacy_load_pod

    ok "Limpeza do gerador de carga concluída."

    echo
    info "O port-forward foi mantido para não afetar outras demos."
}

menu() {
    while true; do
        header

        echo "[1] PRÉ-CHECK"
        echo "[2] INICIAR CARGA LOCAL E DEMONSTRAR SCALE-OUT"
        echo "[3] STATUS / EVIDÊNCIAS"
        echo "[4] MONITORAR HPA AO VIVO"
        echo "[5] PARAR CARGA E OBSERVAR SCALE-DOWN"
        echo "[6] LIMPAR GERADOR DE CARGA"
        echo "[0] SAIR"
        echo

        read -rp "Escolha uma opção: " OPTION

        case "$OPTION" in
            1)
                precheck
                pause
                ;;
            2)
                start_load
                pause
                ;;
            3)
                status
                pause
                ;;
            4)
                watch_live
                ;;
            5)
                stop_and_watch
                pause
                ;;
            6)
                cleanup
                pause
                ;;
            0)
                exit 0
                ;;
            *)
                warn "Opção inválida."
                sleep 1
                ;;
        esac
    done
}

menu
