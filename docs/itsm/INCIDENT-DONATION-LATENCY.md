# INC-001 — Alta Latência no Donation Service

## 1. Resumo do Incidente

| Campo | Valor |
|---|---|
| ID | INC-001 |
| Serviço | donation-service |
| Ambiente | Produção / EKS |
| Namespace | solidarytech |
| Severidade | Critical |
| Categoria | Performance / Latency |
| SLI afetado | Latência HTTP p95 |
| Endpoint | GET /donations |
| Limite | p95 > 2 segundos |
| Status final | Resolvido |

O incidente foi provocado de forma controlada para validar a estratégia
de observabilidade, AIOps, GitOps e resposta a incidentes da plataforma
SolidaryTech.

A aplicação recebeu uma configuração de latência artificial de 2500 ms,
provocando degradação no endpoint `/donations`.

---

## 2. Impacto

O endpoint `/donations`, responsável pelas operações relacionadas às
doações da plataforma, apresentou aumento significativo de latência.

Baseline:

    ~10–20 ms

Durante o incidente:

    ~2500 ms

Embora não tenham sido observados erros HTTP significativos, o tempo de
resposta ultrapassou o SLO definido para o serviço.

---

## 3. SLI e SLO

### SLI

Latência p95 das requisições do endpoint `/donations`.

Métrica Prometheus:

    donation_http_request_duration_seconds_bucket

### SLO

    p95 < 2 segundos

O alerta é disparado quando:

    p95 > 2 segundos durante pelo menos 1 minuto

---

## 4. Detecção

A degradação foi detectada automaticamente pelo Prometheus através da
regra:

    DonationServiceHighLatency

Expressão:

    histogram_quantile(
      0.95,
      sum by (le) (
        rate(
          donation_http_request_duration_seconds_bucket{
            path="/donations"
          }[2m]
        )
      )
    ) > 2

A regra permanece em estado `Pending` durante 1 minuto antes de entrar
em `Firing`.

---

## 5. Observabilidade

A investigação utilizou três fontes principais de telemetria.

### Prometheus

Responsável pela coleta das métricas da aplicação através do endpoint:

    /metrics

### Grafana

Utilizado para visualização dos SLIs e comportamento da latência p95.

### New Relic + OpenTelemetry

Utilizado para Distributed Tracing.

Os traces permitiram identificar especificamente:

    donation-service
        └── GET /donations
              └── duração aproximada: 2.5 s

Isso permitiu correlacionar a violação do SLO observada no Prometheus
com a operação específica responsável pela degradação.

---

## 6. Timeline do Incidente

### T0 — Operação normal

O endpoint `/donations` apresentava latência na ordem de poucos
milissegundos.

### T1 — Introdução da degradação

Foi configurado:

    SIMULATE_LATENCY_MS=2500

A alteração foi realizada através do repositório Git.

### T2 — GitOps

O ArgoCD detectou a nova configuração e realizou a reconciliação do
Deployment.

Estado:

    Synced
    Healthy

### T3 — Detecção

O Prometheus identificou:

    p95 > 2 segundos

O alerta entrou em:

    Pending

### T4 — Incidente

Após permanecer acima do limite durante 1 minuto:

    DonationServiceHighLatency = Firing

### T5 — Investigação

O New Relic Distributed Tracing mostrou aumento significativo da duração
dos traces:

    GET /donations ≈ 2.5 segundos

O Grafana confirmou simultaneamente o aumento da latência p95.

### T6 — Mitigação

A configuração foi revertida:

    SIMULATE_LATENCY_MS=0

A alteração foi novamente versionada no Git.

### T7 — Recuperação GitOps

O ArgoCD reconciliou automaticamente o Deployment.

### T8 — Recuperação

A latência retornou ao baseline.

Após a janela de avaliação do Prometheus:

    DonationServiceHighLatency = Resolved / Inactive

---

## 7. Causa Raiz

A causa raiz do incidente de laboratório foi uma configuração de
latência artificial:

    SIMULATE_LATENCY_MS=2500

Em um cenário real, comportamento semelhante poderia ser causado por:

- degradação de banco de dados;
- dependência externa lenta;
- saturação de recursos;
- problemas de rede;
- contenção de conexões;
- aumento inesperado de carga.

---

## 8. Mitigação

A mitigação foi realizada através do fluxo GitOps.

Alteração:

    SIMULATE_LATENCY_MS=2500

para:

    SIMULATE_LATENCY_MS=0

Fluxo:

    Git
      ↓
    GitHub
      ↓
    ArgoCD
      ↓
    Kubernetes Deployment
      ↓
    Novos Pods
      ↓
    Serviço recuperado

Nenhuma alteração manual permanente foi realizada diretamente no
Deployment.

---

## 9. Self-Healing GitOps

Durante os testes também foi realizada uma tentativa de alteração
manual:

    kubectl set env deployment/donation-service \
      SIMULATE_LATENCY_MS=2500

O ArgoCD restaurou automaticamente:

    SIMULATE_LATENCY_MS=0

porque o Git ainda declarava `0`.

Esse comportamento demonstra que o Git é a fonte de verdade da
plataforma e que alterações manuais são corrigidas automaticamente pelo
mecanismo de self-healing.

---

## 10. Fluxo ITSM

O incidente percorreu o seguinte fluxo:

    Detected
       ↓
    Acknowledged
       ↓
    Investigating
       ↓
    Mitigating
       ↓
    Monitoring
       ↓
    Resolved
       ↓
    Post-Mortem

---

## 11. MTTR

O MTTR pode ser calculado como:

    MTTR = horário da recuperação - horário da detecção

O objetivo da integração entre Prometheus, Grafana, OpenTelemetry,
New Relic e ArgoCD é reduzir o tempo necessário para detectar,
diagnosticar e mitigar incidentes.

---

## 12. Evidências

As evidências coletadas durante o exercício incluem:

1. PrometheusRule `DonationServiceHighLatency`.
2. Alerta em estado Pending.
3. Alerta em estado Firing.
4. Grafana mostrando aumento da latência p95.
5. New Relic mostrando traces do `GET /donations`.
6. Latência próxima de 2.5 segundos durante a degradação.
7. Commit Git utilizado para introduzir a degradação.
8. ArgoCD realizando a reconciliação.
9. Commit Git utilizado para mitigação.
10. Retorno da latência ao baseline.
11. Alerta retornando para Resolved/Inactive.
12. ArgoCD em estado Synced/Healthy.

---

## 13. Ações Preventivas

Como evolução da solução:

- manter SLIs e SLOs definidos por serviço;
- criar alertas baseados em sintomas e não apenas infraestrutura;
- integrar Alertmanager com ferramenta de comunicação/incidentes;
- utilizar tracing distribuído para investigação;
- criar runbooks associados aos alertas;
- realizar testes periódicos de incidentes;
- acompanhar MTTA e MTTR;
- revisar SLOs periodicamente;
- evitar alterações manuais fora do fluxo GitOps.

---

## 14. Arquitetura de Resposta a Incidentes

    Usuário
       │
       ▼
    donation-service
       │
       ├──────────────► OpenTelemetry
       │                     │
       │                     ▼
       │                 New Relic
       │
       └── /metrics
              │
              ▼
          Prometheus
              │
              ├── SLI
              ├── SLO
              └── PrometheusRule
                       │
                       ▼
                  Alertmanager
                       │
                       ▼
                    Incidente
                       │
                       ▼
                 Investigação
                       │
                       ▼
                     Git
                       │
                       ▼
                    ArgoCD
                       │
                       ▼
                  Kubernetes
                       │
                       ▼
                   Recovery
