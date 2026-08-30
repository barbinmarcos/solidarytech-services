#!/usr/bin/env bash

# ============================================================
# SolidaryTech - Pré-check da Banca
#
# Valida:
#   - AWS / EKS
#   - Kubernetes / Nodes
#   - Microsserviços
#   - Grafana + persistência PVC
#   - Prometheus
#   - Alertmanager
#   - ArgoCD
#   - HPA
#   - PrometheusRule
#   - AlertmanagerConfig / Slack
#   - ServiceMonitors
#   - EBS CSI Driver
#
# IMPORTANTE:
#   - NÃO cria dashboards.
#   - NÃO valida dashboards.
#   - NÃO altera workloads.
#   - Pode somente criar/recriar port-forwards locais.
# ============================================================

set -u

# ============================================================
# CONFIGURAÇÃO
# ============================================================

CLUSTER_NAME="solidarytech-prod"
AWS_REGION="us-east-1"

APP_NAMESPACE="solidarytech"
MONITORING_NAMESPACE="monitoring"
ARGO_NAMESPACE="argocd"

# Grafana
GRAFANA_SERVICE="monitoring-grafana"
GRAFANA_PVC="monitoring-grafana"
GRAFANA_PORT="13000"
GRAFANA_SERVICE_PORT="80"

# Prometheus
PROMETHEUS_SERVICE="monitoring-kube-prometheus-prometheus"
PROMETHEUS_PORT="19090"
PROMETHEUS_SERVICE_PORT="9090"

# Alertmanager
ALERTMANAGER_SERVICE="monitoring-kube-prometheus-alertmanager"
ALERTMANAGER_PORT="19093"
ALERTMANAGER_SERVICE_PORT="9093"

# ArgoCD
ARGO_SERVICE="argocd-server"
ARGO_PORT="18080"
ARGO_SERVICE_PORT="443"

# Microsserviços
DONATION_SERVICE="donation-service"
DONATION_PORT="18082"
DONATION_SERVICE_PORT="8082"

NGO_SERVICE="ngo-service"
NGO_PORT="18081"
NGO_SERVICE_PORT="8081"

VOLUNTEER_SERVICE="volunteer-service"
VOLUNTEER_PORT="18083"
VOLUNTEER_SERVICE_PORT="8083"

# Diretórios temporários
PID_DIR="/tmp/solidarytech-precheck"
LOG_DIR="${PID_DIR}/logs"

mkdir -p "$PID_DIR" "$LOG_DIR"

# ============================================================
# CONTADORES
# ============================================================

OK_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

# ============================================================
# CORES
# ============================================================

if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    GREEN=''
    YELLOW=''
    RED=''
    BLUE=''
    CYAN=''
    NC=''
fi

# ============================================================
# FUNÇÕES DE SAÍDA
# ============================================================

section() {
    echo
    echo "================================================================"
    echo "$1"
    echo "================================================================"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $*"
    OK_COUNT=$((OK_COUNT + 1))
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
    WARN_COUNT=$((WARN_COUNT + 1))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

# ============================================================
# FUNÇÕES AUXILIARES
# ============================================================

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

#
# Teste TCP puro.
#
# Não usa HTTP porque:
# - Grafana usa HTTP
# - Prometheus usa HTTP
# - Alertmanager usa HTTP
# - ArgoCD usa HTTPS
#
# /dev/tcp testa somente se existe algo escutando.
#
port_is_open() {
    local port="$1"

    timeout 2 bash -c \
        "echo >/dev/tcp/127.0.0.1/${port}" \
        >/dev/null 2>&1
}

stop_matching_port_forward() {
    local local_port="$1"
    local remote_port="$2"

    pkill -f \
        "kubectl port-forward.*${local_port}:${remote_port}" \
        >/dev/null 2>&1 || true

    sleep 1
}

start_port_forward() {
    local name="$1"
    local namespace="$2"
    local service="$3"
    local local_port="$4"
    local remote_port="$5"

    local logfile="${LOG_DIR}/${name}.log"
    local pidfile="${PID_DIR}/${name}.pid"

    if port_is_open "$local_port"; then
        info "Porta ${local_port} já está aberta para ${name}"
        return 0
    fi

    info "Criando port-forward para ${name}..."

    stop_matching_port_forward "$local_port" "$remote_port"

    nohup kubectl port-forward \
        -n "$namespace" \
        "svc/${service}" \
        "${local_port}:${remote_port}" \
        >"$logfile" 2>&1 &

    local pid=$!
    echo "$pid" > "$pidfile"

    for _ in $(seq 1 15); do

        if port_is_open "$local_port"; then
            return 0
        fi

        if ! kill -0 "$pid" >/dev/null 2>&1; then
            break
        fi

        sleep 1
    done

    return 1
}

show_pf_log() {
    local name="$1"
    local logfile="${LOG_DIR}/${name}.log"

    if [[ -f "$logfile" ]]; then
        info "Últimas linhas do log:"
        tail -10 "$logfile" 2>/dev/null || true
    fi
}

# ============================================================
# 1. DEPENDÊNCIAS
# ============================================================

section "1. DEPENDÊNCIAS"

for cmd in kubectl aws curl grep awk sed timeout; do
    if command_exists "$cmd"; then
        ok "$cmd encontrado"
    else
        fail "$cmd NÃO encontrado"
    fi
done

if command_exists helm; then
    ok "helm encontrado"
else
    warn "helm não encontrado"
fi

if command_exists argocd; then
    ok "argocd CLI encontrado"
else
    warn "argocd CLI não encontrado"
fi

# ============================================================
# 2. AWS
# ============================================================

section "2. AWS"

AWS_IDENTITY=$(aws sts get-caller-identity \
    --query 'Arn' \
    --output text \
    2>/dev/null || true)

if [[ -n "$AWS_IDENTITY" && "$AWS_IDENTITY" != "None" ]]; then
    ok "Autenticação AWS funcionando"
    info "$AWS_IDENTITY"
else
    fail "Não foi possível autenticar na AWS"
fi

# ============================================================
# 3. EKS
# ============================================================

section "3. EKS"

EKS_STATUS=$(aws eks describe-cluster \
    --name "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query 'cluster.status' \
    --output text \
    2>/dev/null || true)

if [[ "$EKS_STATUS" == "ACTIVE" ]]; then
    ok "Cluster $CLUSTER_NAME está ACTIVE"
else
    fail "Cluster $CLUSTER_NAME não está ACTIVE: ${EKS_STATUS:-desconhecido}"
fi

CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || true)

if [[ -n "$CURRENT_CONTEXT" ]]; then
    ok "Contexto Kubernetes configurado"
    info "$CURRENT_CONTEXT"
else
    fail "Nenhum contexto Kubernetes ativo"
fi

if READYZ=$(kubectl get --raw='/readyz' \
    --request-timeout=15s \
    2>/dev/null); then

    if [[ "$READYZ" == "ok" ]]; then
        ok "Kubernetes API Server está Ready"
    else
        warn "API respondeu, mas /readyz retornou: $READYZ"
    fi
else
    fail "Não foi possível acessar Kubernetes API Server"
fi

# ============================================================
# 4. NODES
# ============================================================

section "4. NODES / CAPACIDADE"

NODE_COUNT=$(kubectl get nodes \
    --no-headers \
    2>/dev/null | wc -l)

READY_NODES=$(kubectl get nodes \
    --no-headers \
    2>/dev/null | awk '$2=="Ready"{count++} END{print count+0}')

if [[ "$NODE_COUNT" -gt 0 && "$READY_NODES" -eq "$NODE_COUNT" ]]; then
    ok "Todos os nodes estão Ready: ${READY_NODES}/${NODE_COUNT}"
else
    fail "Nodes Ready: ${READY_NODES}/${NODE_COUNT}"
fi

kubectl get nodes \
    -L topology.kubernetes.io/zone \
    2>/dev/null || true

echo
info "Uso de Pods por node:"

CLUSTER_FREE_PODS=0

while read -r node; do

    [[ -z "$node" ]] && continue

    MAX=$(kubectl get node "$node" \
        -o jsonpath='{.status.capacity.pods}' \
        2>/dev/null || echo 0)

    USED=$(kubectl get pods -A \
        --field-selector "spec.nodeName=${node}" \
        --no-headers \
        2>/dev/null | wc -l)

    ZONE=$(kubectl get node "$node" \
        -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' \
        2>/dev/null || echo "?")

    FREE=$((MAX - USED))
    CLUSTER_FREE_PODS=$((CLUSTER_FREE_PODS + FREE))

    if [[ "$FREE" -le 0 ]]; then
        warn "$node | $ZONE | Pods=${USED}/${MAX} | Livres=0"
    else
        info "$node | $ZONE | Pods=${USED}/${MAX} | Livres=${FREE}"
    fi

done < <(
    kubectl get nodes \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
        2>/dev/null
)

if [[ "$CLUSTER_FREE_PODS" -gt 0 ]]; then
    ok "Cluster possui ${CLUSTER_FREE_PODS} slots de Pod livres"
else
    fail "Cluster não possui slots de Pod livres"
fi

# ============================================================
# 5. MICROSSERVIÇOS / DEPLOYMENTS
# ============================================================

section "5. MICROSSERVIÇOS"

check_deployment() {

    local deployment="$1"

    if ! kubectl get deployment "$deployment" \
        -n "$APP_NAMESPACE" \
        >/dev/null 2>&1; then

        fail "Deployment $deployment não encontrado"
        return
    fi

    local desired
    local available

    desired=$(kubectl get deployment "$deployment" \
        -n "$APP_NAMESPACE" \
        -o jsonpath='{.spec.replicas}' \
        2>/dev/null || echo 0)

    available=$(kubectl get deployment "$deployment" \
        -n "$APP_NAMESPACE" \
        -o jsonpath='{.status.availableReplicas}' \
        2>/dev/null || echo 0)

    [[ -z "$desired" ]] && desired=0
    [[ -z "$available" ]] && available=0

    if [[ "$available" -ge "$desired" && "$desired" -gt 0 ]]; then
        ok "$deployment disponível ${available}/${desired}"
    else
        fail "$deployment disponível ${available}/${desired}"
    fi
}

check_deployment "$DONATION_SERVICE"
check_deployment "$NGO_SERVICE"
check_deployment "$VOLUNTEER_SERVICE"

echo
kubectl get pods -n "$APP_NAMESPACE" -o wide 2>/dev/null || true

# ============================================================
# 6. GRAFANA - PERSISTÊNCIA
# ============================================================

section "6. GRAFANA - PERSISTÊNCIA"

if kubectl get pvc "$GRAFANA_PVC" \
    -n "$MONITORING_NAMESPACE" \
    >/dev/null 2>&1; then

    PVC_STATUS=$(kubectl get pvc "$GRAFANA_PVC" \
        -n "$MONITORING_NAMESPACE" \
        -o jsonpath='{.status.phase}' \
        2>/dev/null || true)

    PVC_VOLUME=$(kubectl get pvc "$GRAFANA_PVC" \
        -n "$MONITORING_NAMESPACE" \
        -o jsonpath='{.spec.volumeName}' \
        2>/dev/null || true)

    PVC_SIZE=$(kubectl get pvc "$GRAFANA_PVC" \
        -n "$MONITORING_NAMESPACE" \
        -o jsonpath='{.status.capacity.storage}' \
        2>/dev/null || true)

    PVC_SC=$(kubectl get pvc "$GRAFANA_PVC" \
        -n "$MONITORING_NAMESPACE" \
        -o jsonpath='{.spec.storageClassName}' \
        2>/dev/null || true)

    if [[ "$PVC_STATUS" == "Bound" ]]; then
        ok "PVC $GRAFANA_PVC está Bound"
    else
        fail "PVC $GRAFANA_PVC está $PVC_STATUS"
    fi

    info "Volume:       ${PVC_VOLUME:-desconhecido}"
    info "Capacidade:   ${PVC_SIZE:-desconhecida}"
    info "StorageClass: ${PVC_SC:-desconhecida}"

else
    fail "PVC $GRAFANA_PVC não encontrado"
fi

GRAFANA_POD=$(kubectl get pods \
    -n "$MONITORING_NAMESPACE" \
    -l app.kubernetes.io/name=grafana \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' \
    2>/dev/null || true)

if [[ -z "$GRAFANA_POD" ]]; then

    fail "Nenhum Pod Running do Grafana encontrado"

else

    info "Grafana Pod: $GRAFANA_POD"

    GRAFANA_READY=$(kubectl get pod "$GRAFANA_POD" \
        -n "$MONITORING_NAMESPACE" \
        -o jsonpath='{range .status.containerStatuses[*]}{.ready}{" "}{end}' \
        2>/dev/null || true)

    if [[ "$GRAFANA_READY" != *"false"* && -n "$GRAFANA_READY" ]]; then
        ok "Containers do Grafana estão Ready"
    else
        fail "Nem todos os containers do Grafana estão Ready"
    fi

    STORAGE_CLAIM=$(kubectl get pod "$GRAFANA_POD" \
        -n "$MONITORING_NAMESPACE" \
        -o jsonpath='{.spec.volumes[?(@.name=="storage")].persistentVolumeClaim.claimName}' \
        2>/dev/null || true)

    if [[ "$STORAGE_CLAIM" == "$GRAFANA_PVC" ]]; then
        ok "Volume storage usa PVC $GRAFANA_PVC"
    else
        fail "Volume storage NÃO usa o PVC esperado"
        info "Claim encontrado: ${STORAGE_CLAIM:-nenhum}"
    fi

    STORAGE_MOUNT=$(kubectl get pod "$GRAFANA_POD" \
        -n "$MONITORING_NAMESPACE" \
        -o jsonpath='{.spec.containers[?(@.name=="grafana")].volumeMounts[?(@.name=="storage")].mountPath}' \
        2>/dev/null || true)

    if [[ "$STORAGE_MOUNT" == "/var/lib/grafana" ]]; then
        ok "PVC montado em /var/lib/grafana"
    else
        fail "Mount storage inesperado: ${STORAGE_MOUNT:-não encontrado}"
    fi

fi

# ============================================================
# 7. GRAFANA - API
# ============================================================

section "7. GRAFANA - API"

if start_port_forward \
    "grafana" \
    "$MONITORING_NAMESPACE" \
    "$GRAFANA_SERVICE" \
    "$GRAFANA_PORT" \
    "$GRAFANA_SERVICE_PORT"; then

    GRAFANA_HEALTH=$(curl -s \
        --connect-timeout 3 \
        --max-time 5 \
        "http://127.0.0.1:${GRAFANA_PORT}/api/health" \
        2>/dev/null || true)

    if echo "$GRAFANA_HEALTH" |
        grep -Eq '"database"[[:space:]]*:[[:space:]]*"ok"'; then

        ok "Grafana API saudável"
        info "$GRAFANA_HEALTH"

    else

        fail "Grafana API não respondeu corretamente"

        if [[ -n "$GRAFANA_HEALTH" ]]; then
            info "$GRAFANA_HEALTH"
        fi

        show_pf_log "grafana"
    fi

else

    fail "Não foi possível criar port-forward do Grafana"
    show_pf_log "grafana"

fi

info "Grafana: http://localhost:${GRAFANA_PORT}"

# ============================================================
# 8. PROMETHEUS
# ============================================================

section "8. PROMETHEUS"

if start_port_forward \
    "prometheus" \
    "$MONITORING_NAMESPACE" \
    "$PROMETHEUS_SERVICE" \
    "$PROMETHEUS_PORT" \
    "$PROMETHEUS_SERVICE_PORT"; then

    PROM_READY=$(curl -s \
        --connect-timeout 3 \
        --max-time 5 \
        "http://127.0.0.1:${PROMETHEUS_PORT}/-/ready" \
        2>/dev/null || true)

    if echo "$PROM_READY" |
        grep -qiE 'ready|Prometheus Server is Ready'; then

        ok "Prometheus está Ready"

    else

        fail "Prometheus não respondeu /-/ready"
        info "Resposta: ${PROM_READY:-vazia}"
        show_pf_log "prometheus"
    fi

else

    fail "Não foi possível criar port-forward do Prometheus"
    show_pf_log "prometheus"

fi

info "Prometheus: http://localhost:${PROMETHEUS_PORT}"

# ============================================================
# 9. ALERTMANAGER
# ============================================================

section "9. ALERTMANAGER"

if start_port_forward \
    "alertmanager" \
    "$MONITORING_NAMESPACE" \
    "$ALERTMANAGER_SERVICE" \
    "$ALERTMANAGER_PORT" \
    "$ALERTMANAGER_SERVICE_PORT"; then

    AM_READY=$(curl -s \
        --connect-timeout 3 \
        --max-time 5 \
        "http://127.0.0.1:${ALERTMANAGER_PORT}/-/ready" \
        2>/dev/null || true)

    if echo "$AM_READY" | grep -qi 'OK'; then

        ok "Alertmanager está Ready"

    else

        # Algumas versões podem responder sem exatamente "OK".
        HTTP_CODE=$(curl -s \
            -o /dev/null \
            -w '%{http_code}' \
            --connect-timeout 3 \
            --max-time 5 \
            "http://127.0.0.1:${ALERTMANAGER_PORT}/-/ready" \
            2>/dev/null || echo 000)

        if [[ "$HTTP_CODE" == "200" ]]; then
            ok "Alertmanager está Ready - HTTP 200"
        else
            fail "Alertmanager não respondeu /-/ready"
            info "HTTP: $HTTP_CODE"
            info "Resposta: ${AM_READY:-vazia}"
            show_pf_log "alertmanager"
        fi
    fi

else

    fail "Não foi possível criar port-forward do Alertmanager"
    show_pf_log "alertmanager"

fi

info "Alertmanager: http://localhost:${ALERTMANAGER_PORT}"

# ============================================================
# 10. ARGOCD
# ============================================================

section "10. ARGOCD"

ARGO_BAD_PODS=$(kubectl get pods \
    -n "$ARGO_NAMESPACE" \
    --no-headers \
    2>/dev/null |
    awk '$3!="Running" && $3!="Completed"{print}' || true)

if [[ -z "$ARGO_BAD_PODS" ]]; then
    ok "Pods do ArgoCD estão saudáveis"
else
    fail "Existem Pods não saudáveis no ArgoCD"
    echo "$ARGO_BAD_PODS"
fi

if start_port_forward \
    "argocd" \
    "$ARGO_NAMESPACE" \
    "$ARGO_SERVICE" \
    "$ARGO_PORT" \
    "$ARGO_SERVICE_PORT"; then

    if curl -sk \
        --connect-timeout 3 \
        --max-time 5 \
        "https://127.0.0.1:${ARGO_PORT}/healthz" \
        >/dev/null 2>&1; then

        ok "ArgoCD acessível"

    else

        # O TCP estar aberto já confirma o port-forward.
        if port_is_open "$ARGO_PORT"; then
            ok "Port-forward do ArgoCD está ativo"
        else
            fail "ArgoCD não está acessível"
        fi
    fi

else

    fail "Não foi possível criar port-forward do ArgoCD"
    show_pf_log "argocd"

fi

info "ArgoCD: https://localhost:${ARGO_PORT}"

if command_exists argocd && port_is_open "$ARGO_PORT"; then

    echo

    argocd app list \
        --server "localhost:${ARGO_PORT}" \
        --grpc-web \
        --insecure \
        2>/dev/null || \
        warn "CLI ArgoCD não conseguiu listar aplicações"

fi

# ============================================================
# 11. HEALTH DOS MICROSSERVIÇOS
# ============================================================

section "11. HEALTH DOS MICROSSERVIÇOS"

check_service_health() {

    local name="$1"
    local service="$2"
    local local_port="$3"
    local service_port="$4"

    if ! start_port_forward \
        "$name" \
        "$APP_NAMESPACE" \
        "$service" \
        "$local_port" \
        "$service_port"; then

        fail "Não foi possível acessar $name"
        show_pf_log "$name"
        return
    fi

    local body
    local http_code

    body=$(curl -s \
        --connect-timeout 3 \
        --max-time 5 \
        "http://127.0.0.1:${local_port}/health" \
        2>/dev/null || true)

    http_code=$(curl -s \
        -o /dev/null \
        -w '%{http_code}' \
        --connect-timeout 3 \
        --max-time 5 \
        "http://127.0.0.1:${local_port}/health" \
        2>/dev/null || echo 000)

    if [[ "$http_code" == "200" ]]; then
        ok "$name saudável - HTTP 200"
        info "$body"
    else
        fail "$name health check falhou - HTTP $http_code"
        info "${body:-sem resposta}"
    fi
}

check_service_health \
    "donation-service" \
    "$DONATION_SERVICE" \
    "$DONATION_PORT" \
    "$DONATION_SERVICE_PORT"

check_service_health \
    "ngo-service" \
    "$NGO_SERVICE" \
    "$NGO_PORT" \
    "$NGO_SERVICE_PORT"

check_service_health \
    "volunteer-service" \
    "$VOLUNTEER_SERVICE" \
    "$VOLUNTEER_PORT" \
    "$VOLUNTEER_SERVICE_PORT"

# ============================================================
# 12. HPA
# ============================================================

section "12. HPA"

if kubectl get hpa "$DONATION_SERVICE" \
    -n "$APP_NAMESPACE" \
    >/dev/null 2>&1; then

    ok "HPA donation-service encontrado"

    kubectl get hpa "$DONATION_SERVICE" \
        -n "$APP_NAMESPACE"

else

    fail "HPA donation-service não encontrado"

fi

# ============================================================
# 13. PROMETHEUS RULE
# ============================================================

section "13. PROMETHEUS RULE"

RULE_OUTPUT=$(kubectl get prometheusrule -A \
    --no-headers \
    2>/dev/null |
    grep -i 'donation-service-alerts' || true)

if [[ -n "$RULE_OUTPUT" ]]; then

    ok "PrometheusRule do Donation encontrado"
    echo "$RULE_OUTPUT"

else

    fail "PrometheusRule donation-service-alerts não encontrado"

fi

ALERT_FOUND=$(kubectl get prometheusrule -A \
    -o yaml \
    2>/dev/null |
    grep -c 'DonationServiceHighLatency' || true)

if [[ "$ALERT_FOUND" -gt 0 ]]; then
    ok "Alert DonationServiceHighLatency configurado"
else
    fail "Alert DonationServiceHighLatency não encontrado"
fi

# ============================================================
# 14. ALERTMANAGER CONFIG / SLACK
# ============================================================

section "14. ALERTMANAGER CONFIG / SLACK"

AMCONFIGS=$(kubectl get alertmanagerconfig -A \
    --no-headers \
    2>/dev/null || true)

if [[ -n "$AMCONFIGS" ]]; then

    SOLIDARYTECH_AMCONFIG=$(echo "$AMCONFIGS" |
        grep -Ei 'solidarytech|slack' || true)

    if [[ -n "$SOLIDARYTECH_AMCONFIG" ]]; then
        ok "AlertmanagerConfig SolidaryTech/Slack encontrado"
        echo "$SOLIDARYTECH_AMCONFIG"
    else
        warn "AlertmanagerConfig existe, mas nenhum nome contém SolidaryTech/Slack"
        echo "$AMCONFIGS"
    fi

else

    warn "Nenhum AlertmanagerConfig encontrado"

fi

SLACK_SECRETS=$(kubectl get secrets \
    -n "$MONITORING_NAMESPACE" \
    --no-headers \
    2>/dev/null |
    grep -Ei 'slack|webhook' || true)

if [[ -n "$SLACK_SECRETS" ]]; then

    ok "Secret relacionado ao Slack/Webhook encontrado"

    # Mostra apenas nome/tipo, nunca conteúdo.
    echo "$SLACK_SECRETS"

else

    warn "Nenhum Secret com nome Slack/Webhook encontrado em monitoring"

fi

# ============================================================
# 15. SERVICE MONITORS
# ============================================================

section "15. SERVICE MONITORS"

check_service_monitor() {

    local name="$1"

    local result

    result=$(kubectl get servicemonitor -A \
        --no-headers \
        2>/dev/null |
        grep -Ei "(^|[[:space:]])${name}([[:space:]]|$)|${name}-service" \
        || true)

    if [[ -n "$result" ]]; then
        ok "ServiceMonitor $name encontrado"
        echo "$result"
    else
        warn "ServiceMonitor $name não encontrado"
    fi
}

check_service_monitor "donation"
check_service_monitor "ngo"
check_service_monitor "volunteer"

# ============================================================
# 16. EBS CSI DRIVER
# ============================================================

section "16. EBS CSI DRIVER"

if kubectl get csidriver ebs.csi.aws.com \
    >/dev/null 2>&1; then

    ok "CSI Driver ebs.csi.aws.com registrado"

else

    fail "CSI Driver ebs.csi.aws.com não encontrado"

fi

EBS_CONTROLLERS=$(kubectl get pods \
    -n kube-system \
    --no-headers \
    2>/dev/null |
    grep '^ebs-csi-controller-' || true)

if [[ -n "$EBS_CONTROLLERS" ]]; then

    echo "$EBS_CONTROLLERS"

    BAD_EBS=$(echo "$EBS_CONTROLLERS" |
        awk '$3!="Running"{print}')

    if [[ -z "$BAD_EBS" ]]; then
        ok "EBS CSI Controller está Running"
    else
        fail "Existem EBS CSI Controllers não Running"
        echo "$BAD_EBS"
    fi

else

    fail "Nenhum EBS CSI Controller encontrado"

fi

# ============================================================
# 17. RESUMO
# ============================================================

section "RESULTADO DO PRÉ-CHECK"

echo
printf "Checks OK:       %s\n" "$OK_COUNT"
printf "Warnings:        %s\n" "$WARN_COUNT"
printf "Falhas:          %s\n" "$FAIL_COUNT"
echo

echo "----------------------------------------------------------------"
echo "URLs PARA A BANCA"
echo "----------------------------------------------------------------"
echo
echo "Grafana:       http://localhost:${GRAFANA_PORT}"
echo "Prometheus:    http://localhost:${PROMETHEUS_PORT}"
echo "Alertmanager:  http://localhost:${ALERTMANAGER_PORT}"
echo "ArgoCD:        https://localhost:${ARGO_PORT}"
echo "Donation:      http://localhost:${DONATION_PORT}"
echo "NGO:           http://localhost:${NGO_PORT}"
echo "Volunteer:     http://localhost:${VOLUNTEER_PORT}"
echo

if [[ "$FAIL_COUNT" -eq 0 ]]; then

    echo "==============================================================="
    echo "          AMBIENTE APROVADO PARA A BANCA"
    echo "==============================================================="

    if [[ "$WARN_COUNT" -gt 0 ]]; then
        echo
        echo "Existem ${WARN_COUNT} warning(s), mas nenhuma falha crítica."
    fi

    exit 0

else

    echo "==============================================================="
    echo "          PRÉ-CHECK ENCONTROU PROBLEMAS"
    echo "==============================================================="
    echo
    echo "Corrija as falhas antes de iniciar a demonstração."

    exit 1

fi
