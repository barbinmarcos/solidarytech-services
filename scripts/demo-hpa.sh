#!/usr/bin/env bash

set -u

NAMESPACE="solidarytech"
DEPLOYMENT="donation-service"
HPA="donation-service"

LOAD_POD="donation-hpa-load"
SERVICE_URL="http://donation-service:8082/health"

# Quantidade de loops HTTP paralelos dentro do pod de carga.
# Pode sobrescrever:
# CONCURRENCY=120 ./scripts/demo-hpa.sh
CONCURRENCY="${CONCURRENCY:-80}"

WAIT_SCALE_UP="${WAIT_SCALE_UP:-240}"
WAIT_SCALE_DOWN="${WAIT_SCALE_DOWN:-420}"

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m"

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

check_dependencies() {
    command -v kubectl >/dev/null 2>&1 || {
        error "kubectl não encontrado."
        return 1
    }

    kubectl cluster-info >/dev/null 2>&1 || {
        error "Sem acesso ao cluster Kubernetes."
        return 1
    }

    return 0
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

    echo "[1/5] Kubernetes"
    if ! check_dependencies; then
        return 1
    fi
    ok "Cluster acessível"

    echo
    echo "[2/5] Deployment"
    if ! kubectl get deployment "$DEPLOYMENT" \
        -n "$NAMESPACE" >/dev/null 2>&1; then
        error "Deployment $DEPLOYMENT não encontrado."
        return 1
    fi
    ok "$DEPLOYMENT encontrado"

    echo
    echo "[3/5] HPA"
    if ! kubectl get hpa "$HPA" \
        -n "$NAMESPACE" >/dev/null 2>&1; then
        error "HPA $HPA não encontrado."
        return 1
    fi
    ok "HPA encontrado"

    echo
    echo "[4/5] Metrics Server"
    if kubectl top pods -n "$NAMESPACE" >/dev/null 2>&1; then
        ok "Métricas de CPU disponíveis"
    else
        warn "kubectl top ainda não está retornando métricas."
    fi

    echo
    echo "[5/5] Estado inicial"
    show_hpa

    echo
    ok "Pré-check concluído."
}

delete_load() {
    if kubectl get pod "$LOAD_POD" \
        -n "$NAMESPACE" >/dev/null 2>&1; then

        info "Removendo gerador de carga..."

        kubectl delete pod "$LOAD_POD" \
            -n "$NAMESPACE" \
            --ignore-not-found=true \
            --wait=false

        ok "Carga interrompida."
    else
        info "Nenhum gerador de carga ativo."
    fi
}

start_load() {
    header

    if ! check_dependencies; then
        return 1
    fi

    delete_load

    echo
    echo "============================================================"
    echo " INICIANDO TESTE DE SCALE-OUT"
    echo "============================================================"
    echo
    echo "Destino:       $SERVICE_URL"
    echo "Concorrência:  $CONCURRENCY loops"
    echo
    echo "A carga utiliza GET /health."
    echo "Nenhuma doação será criada no PostgreSQL."
    echo

    BEFORE=$(kubectl get deployment "$DEPLOYMENT" \
        -n "$NAMESPACE" \
        -o jsonpath='{.status.replicas}')

    BEFORE="${BEFORE:-0}"

    info "Réplicas antes do teste: $BEFORE"

    kubectl run "$LOAD_POD" \
        -n "$NAMESPACE" \
        --image=busybox:1.36 \
        --restart=Never \
        --labels="app=solidarytech-hpa-load" \
        --command -- \
        sh -c "
        echo 'Iniciando ${CONCURRENCY} workers...';

        i=1;
        while [ \$i -le ${CONCURRENCY} ]; do
          (
            while true; do
              wget -q -T 2 -O /dev/null '${SERVICE_URL}' || true;
            done
          ) &
          i=\$((i+1));
        done;

        wait
        "

    echo
    info "Aguardando pod de carga..."

    kubectl wait \
        --for=condition=Ready \
        pod/"$LOAD_POD" \
        -n "$NAMESPACE" \
        --timeout=60s || {
            error "Pod de carga não ficou Ready."
            kubectl describe pod "$LOAD_POD" -n "$NAMESPACE"
            return 1
        }

    ok "Gerador de carga ativo."

    echo
    info "O HPA precisa de algumas janelas de métricas para reagir."
    echo

    START=$(date +%s)
    DEADLINE=$((START + WAIT_SCALE_UP))

    while true; do
        NOW=$(date +%s)

        CURRENT=$(kubectl get deployment "$DEPLOYMENT" \
            -n "$NAMESPACE" \
            -o jsonpath='{.status.replicas}')

        CURRENT="${CURRENT:-0}"

        echo
        echo "------------------------------------------------------------"
        date '+%H:%M:%S'
        kubectl get hpa "$HPA" -n "$NAMESPACE"
        echo
        kubectl top pods -n "$NAMESPACE" 2>/dev/null \
            | grep "$DEPLOYMENT" || true

        if [ "$CURRENT" -gt "$BEFORE" ]; then
            echo
            ok "HPA ESCALOU!"
            echo
            echo "Réplicas:"
            echo "  Antes : $BEFORE"
            echo "  Agora : $CURRENT"
            echo
            echo "O scale-out foi provocado por aumento de CPU."
            return 0
        fi

        if [ "$NOW" -ge "$DEADLINE" ]; then
            echo
            warn "Não houve scale-out dentro de ${WAIT_SCALE_UP}s."
            echo
            echo "A carga continuará ativa."
            echo
            echo "Você pode aumentar a concorrência executando:"
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

    if kubectl get pod "$LOAD_POD" \
        -n "$NAMESPACE" >/dev/null 2>&1; then
        kubectl get pod "$LOAD_POD" -n "$NAMESPACE"
        echo
        ok "Carga HPA ATIVA"
    else
        warn "Carga HPA INATIVA"
    fi
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
    echo "Kubernetes normalmente mantém uma janela de estabilização"
    echo "antes de remover réplicas."
    echo

    MIN=$(kubectl get hpa "$HPA" \
        -n "$NAMESPACE" \
        -o jsonpath='{.spec.minReplicas}')

    MIN="${MIN:-1}"

    START=$(date +%s)
    DEADLINE=$((START + WAIT_SCALE_DOWN))

    while true; do
        NOW=$(date +%s)

        CURRENT=$(kubectl get deployment "$DEPLOYMENT" \
            -n "$NAMESPACE" \
            -o jsonpath='{.status.replicas}')

        CURRENT="${CURRENT:-0}"

        echo
        echo "------------------------------------------------------------"
        date '+%H:%M:%S'
        kubectl get hpa "$HPA" -n "$NAMESPACE"

        echo
        kubectl top pods -n "$NAMESPACE" 2>/dev/null \
            | grep "$DEPLOYMENT" || true

        if [ "$CURRENT" -le "$MIN" ]; then
            echo
            ok "SCALE-DOWN CONCLUÍDO"
            echo
            echo "Réplicas atuais: $CURRENT"
            echo "MinReplicas:      $MIN"
            return 0
        fi

        if [ "$NOW" -ge "$DEADLINE" ]; then
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
    ok "Limpeza concluída."
}

menu() {
    while true; do
        header

        echo "[1] PRÉ-CHECK"
        echo "[2] INICIAR CARGA E DEMONSTRAR SCALE-OUT"
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
