# INC-001 — Alta Latência no Donation Service

## 1. Identificação

| Campo | Valor |
|---|---|
| ID | INC-001 |
| Serviço | donation-service |
| Ambiente | Production |
| Plataforma | Amazon EKS |
| Namespace | solidarytech |
| Categoria | Performance / Latency |
| Severidade | SEV-2 |
| Status final | RESOLVED |
| MTTR | A registrar a partir da execução medida |

---

## 2. Resumo executivo

Foi identificada uma degradação de performance no `donation-service`,
com aumento do p95 de latência das requisições de doação acima do SLO
estabelecido de 2 segundos.

Durante o incidente, o serviço permaneceu disponível, demonstrando que
disponibilidade e latência representam dimensões distintas da
confiabilidade.

O incidente foi detectado pela camada de observabilidade e também
identificado pela solução de APM/AIOps.

A recuperação foi realizada através do fluxo GitOps, restabelecendo a
configuração normal da aplicação e validando posteriormente a
recuperação através das métricas.

---

## 3. SLI e SLO afetados

### SLI — Latência

Indicador:

p95 da duração das requisições `POST /donations`.

PromQL:

    histogram_quantile(
      0.95,
      sum by (le) (
        rate(
          donation_http_request_duration_seconds_bucket{
            method="POST",
            path="/donations"
          }[2m]
        )
      )
    )

### SLO

    p95 <= 2 segundos

Durante o incidente, o p95 ultrapassou o limite estabelecido.

---

## 4. Disponibilidade durante o incidente

Embora o SLO de latência tenha sido violado, a aplicação permaneceu
respondendo às requisições.

Isso demonstra que:

    Availability SLO != Latency SLO

O serviço pode estar tecnicamente disponível e, simultaneamente,
apresentar degradação significativa de performance.

---

## 5. Detecção

O incidente foi observado através de múltiplas camadas.

### Prometheus

As métricas de duração das requisições indicaram aumento significativo
do p95.

### Grafana

O dashboard SRE apresentou:

- aumento do p95 acima de 2 segundos;
- violação do SLO de latência;
- disponibilidade preservada;
- alerta de alta latência em estado FIRING.

### Alertmanager

A regra `DonationServiceHighLatency` entrou em estado FIRING após a
condição permanecer acima do limite configurado.

### New Relic APM / AIOps

A telemetria OpenTelemetry enviada ao New Relic permitiu visualizar
distributed traces da aplicação.

A condição de anomalia de latência do `donation-service` também
identificou comportamento anômalo durante o incidente.

---

## 6. Classificação

O incidente foi classificado como:

    SEV-2 — Alto

Justificativa:

- serviço crítico de doações afetado;
- SLO de latência violado;
- degradação perceptível de performance;
- serviço permaneceu disponível;
- não houve evidência de perda de dados.

---

## 7. Diagnóstico

Durante a investigação foram correlacionados:

- p95 de latência;
- taxa de requisições;
- disponibilidade;
- CPU;
- memória;
- número de réplicas;
- comportamento do HPA;
- estado do ArgoCD;
- traces do New Relic.

Foi observado que a degradação de latência não correspondia a uma
saturação significativa de CPU.

Consequentemente, o HPA não deveria ser considerado mecanismo direto
de correção desse incidente, pois seu sinal de escala utilizado estava
associado à utilização de CPU.

---

## 8. Causa da demonstração

Para fins de validação controlada do processo SRE/ITSM, a degradação
foi induzida através da configuração:

    SIMULATE_LATENCY_MS=2500

A alteração foi aplicada através do fluxo declarativo GitOps.

Essa configuração adicionou latência às requisições e permitiu validar
todo o ciclo de observabilidade e resposta a incidentes.

---

## 9. Mitigação

A mitigação consistiu em restaurar:

    SIMULATE_LATENCY_MS=0

A alteração seguiu o fluxo:

    Git
      |
      v
    Helm values
      |
      v
    ArgoCD
      |
      v
    Kubernetes / EKS

Após a sincronização, o deployment retornou à configuração normal.

---

## 10. Validação da recuperação

A recuperação foi validada através de:

- retorno do p95 para abaixo de 2 segundos;
- serviço permanecendo disponível;
- alerta deixando o estado FIRING;
- métricas retornando ao baseline;
- workloads Kubernetes saudáveis;
- ArgoCD Healthy/Synced.

---

## 11. HPA

Durante o incidente de latência, o HPA permaneceu próximo ao número
mínimo de réplicas porque não ocorreu saturação correspondente de CPU.

Esse comportamento é esperado.

O HPA responde ao sinal de capacidade configurado e não diretamente ao
p95 de latência.

Um teste separado de carga de CPU é utilizado para demonstrar o
scale-out e scale-down do HPA.

---

## 12. Timeline

| Evento | Horário |
|---|---|
| Baseline saudável confirmado | A registrar |
| Degradação iniciada | A registrar |
| SLO de latência violado | A registrar |
| Alerta FIRING | A registrar |
| Anomalia identificada no APM/AIOps | A registrar |
| Mitigação iniciada | A registrar |
| Configuração normal restaurada | A registrar |
| SLO novamente atendido | A registrar |
| Incidente resolvido | A registrar |

---

## 13. MTTR

O MTTR será calculado utilizando:

    MTTR = horário da recuperação - horário da detecção

O valor deverá ser preenchido a partir da execução cronometrada da
demonstração.

---

## 14. Impacto

Durante a simulação:

- houve degradação significativa de latência;
- o fluxo permaneceu disponível;
- não foi observada perda de dados;
- não foi observada indisponibilidade completa;
- o SLO de latência foi violado.

---

## 15. Ações preventivas e melhorias

### Observabilidade

Manter dashboards SRE e alertas baseados em SLO.

### AIOps

Utilizar detecção de comportamento anômalo como complemento aos
thresholds estáticos.

### GitOps

Manter mudanças de configuração versionadas e reconciliadas pelo
ArgoCD.

### Autoscaling

Avaliar, em evolução futura, métricas adicionais para autoscaling além
de CPU quando houver justificativa operacional.

### Performance

Acompanhar continuamente o p95 do fluxo crítico de doações.

---

## 16. Evidências

As evidências utilizadas na validação incluem:

- dashboard Platform Overview;
- dashboard Donation Service;
- dashboard SRE / SLO;
- Prometheus;
- PrometheusRule `DonationServiceHighLatency`;
- Alertmanager;
- notificação operacional via Slack;
- New Relic Distributed Tracing;
- New Relic AIOps;
- ArgoCD;
- Kubernetes HPA.

---

## 17. Conclusão

O incidente demonstrou que a plataforma consegue identificar uma
degradação mesmo quando o serviço permanece disponível.

A combinação de SLI/SLO, Prometheus, Grafana, Alertmanager,
OpenTelemetry, New Relic e GitOps fornece evidências para detectar,
diagnosticar, mitigar e validar a recuperação do serviço.

O processo ITSM formaliza esse ciclo e permite utilizar o MTTR e o
postmortem como mecanismos de melhoria contínua.

---

## Evidências da simulação controlada

A simulação controlada do incidente foi executada em 30/08/2026.

### Linha do tempo observada

| Evento | Horário |
|---|---|
| Início da simulação | 16:15:46 -03 |
| `DonationServiceHighLatency` em FIRING | 16:18:20 -03 |
| Alerta RESOLVED | 16:32:51 -03 |

O tempo entre o início da simulação e a entrada efetiva do alerta em FIRING foi de:

**2 minutos e 34 segundos**

O MTTR observado, considerando o intervalo entre a detecção efetiva pelo monitoramento e a confirmação da recuperação, foi de:

**14 minutos e 31 segundos (871 segundos)**

### Evidências SLI/SLO

Durante o incidente:

- Donation p95: aproximadamente **4,88 s**
- SLO de latência: **<= 2 s**
- Availability SLI: **100%**
- Latency SLO: **0%**
- `DonationServiceHighLatency`: **FIRING**

O serviço permaneceu disponível, mas com degradação de desempenho suficiente para violar o SLO de latência.

Após a recuperação:

- Donation p95: aproximadamente **4,75 ms**
- Availability SLI: **100%**
- Latency SLO: **100%**
- Alert FIRING: **0**
- `simulateLatencyMs`: **0**
- Donation Service: **2/2 réplicas disponíveis**

A recuperação restabeleceu o SLO de latência sem perda de disponibilidade.
