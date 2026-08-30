# Postmortem — INC-001

## Alta Latência no Donation Service

**Incidente:** INC-001  
**Serviço:** donation-service  
**Ambiente:** Production  
**Severidade:** SEV-2  
**Status:** Resolvido  
**Data:** 30/08/2026  
**MTTR:** A registrar a partir da execução medida

---

## 1. Resumo executivo

Durante uma simulação controlada de incidente, o `donation-service`
apresentou degradação significativa de latência no fluxo de doações.

O p95 das requisições `POST /donations` ultrapassou o SLO estabelecido
de 2 segundos.

Apesar da degradação de performance, o serviço permaneceu disponível.

A observabilidade baseada em Prometheus e Grafana detectou a violação,
o Alertmanager sinalizou a condição de alta latência e a telemetria
OpenTelemetry/New Relic permitiu observar o comportamento através de
APM, distributed tracing e detecção de anomalia.

A recuperação foi executada através do processo GitOps, restaurando a
configuração normal da aplicação.

---

## 2. Impacto

Durante o incidente:

- o p95 do fluxo de doações ultrapassou 2 segundos;
- o SLO de latência foi violado;
- o serviço permaneceu disponível;
- não foi observada perda de dados;
- não houve indisponibilidade completa da plataforma;
- NGO Service e Volunteer Service permaneceram estáveis.

O incidente demonstrou que disponibilidade e performance devem ser
monitoradas como dimensões distintas de confiabilidade.

---

## 3. SLI/SLO afetado

### SLI

p95 da duração das requisições:

    POST /donations

### SLO

    p95 <= 2 segundos

PromQL utilizada:

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

---

## 4. Detecção

O incidente foi detectado através de múltiplas camadas.

### Prometheus

Identificou o aumento da duração das requisições através das métricas
da aplicação.

### Grafana

Os dashboards mostraram simultaneamente:

- aumento do p95;
- violação do SLO de latência;
- disponibilidade preservada;
- comportamento dos recursos Kubernetes;
- estado do HPA.

### Alertmanager

A regra:

    DonationServiceHighLatency

entrou em estado `FIRING` após a condição configurada permanecer
violada.

### New Relic

A telemetria OpenTelemetry permitiu observar traces do
`donation-service`.

A condição de baseline/anomaly detection configurada para a latência
também identificou o comportamento anômalo.

---

## 5. Causa raiz

A causa da degradação foi uma alteração controlada utilizada para
simulação do incidente:

    SIMULATE_LATENCY_MS=2500

A configuração adicionou aproximadamente 2,5 segundos de latência ao
fluxo da aplicação.

Essa alteração foi proposital e teve como objetivo validar o processo
de observabilidade, SRE, AIOps, ITSM e recuperação.

---

## 6. Fatores contribuintes

O HPA não reagiu significativamente ao incidente porque o mecanismo de
autoscaling estava baseado em utilização de CPU.

A degradação introduzida aumentava a duração das requisições sem gerar
uma saturação proporcional de CPU.

Portanto:

    alta latência != necessariamente alta utilização de CPU

Esse comportamento foi considerado correto para a configuração atual
do HPA.

---

## 7. Mitigação

A mitigação consistiu em restaurar:

    SIMULATE_LATENCY_MS=0

A alteração seguiu o processo GitOps:

    Git
      ↓
    Helm
      ↓
    ArgoCD
      ↓
    Kubernetes / EKS

O ArgoCD reconciliou o estado desejado e realizou a atualização do
workload.

---

## 8. Recuperação

Após a mitigação foram verificadas as seguintes condições:

- deployment saudável;
- aplicação disponível;
- p95 novamente abaixo de 2 segundos;
- alerta deixando o estado FIRING;
- métricas retornando ao baseline;
- ArgoCD Healthy/Synced.

Somente após essas verificações o incidente foi considerado resolvido.

---

## 9. Timeline

| Evento | Horário |
|---|---|
| Baseline confirmado | A registrar |
| Simulação iniciada | A registrar |
| SLO violado | A registrar |
| Alerta FIRING | A registrar |
| Anomalia AIOps observada | A registrar |
| Mitigação iniciada | A registrar |
| Configuração normal restaurada | A registrar |
| SLO normalizado | A registrar |
| Incidente resolvido | A registrar |

---

## 10. MTTR

O MTTR é definido como:

    MTTR = horário da recuperação - horário da detecção

O valor final deverá ser preenchido utilizando os timestamps coletados
durante a execução cronometrada do incidente.

---

## 11. O que funcionou bem

### Observabilidade

Prometheus e Grafana permitiram identificar claramente a degradação.

### SLI/SLO

O SLO tornou objetiva a definição de comportamento aceitável e
degradação.

### Alertas

O Alertmanager transformou a violação persistente em um evento
operacional.

### AIOps

A detecção de anomalia complementou o threshold estático utilizado
pela camada Prometheus.

### GitOps

A recuperação através do estado declarativo permitiu uma alteração
controlada, versionada e auditável.

### Kubernetes

A plataforma permaneceu operacional durante a degradação.

---

## 12. O que pode ser melhorado

### Autoscaling

Avaliar futuramente métricas customizadas para cenários nos quais
latência ou tamanho da fila sejam sinais melhores de capacidade que
CPU.

### Runbooks

Manter procedimentos específicos para:

- alta latência;
- indisponibilidade;
- erro de banco de dados;
- falha de deployment;
- recuperação de desastre.

### Correlação

Evoluir a correlação entre métricas, traces, logs e eventos para
reduzir ainda mais o tempo de diagnóstico.

### Automação ITSM

Uma evolução futura pode integrar os alertas a uma plataforma de
gestão de serviços para abertura e atualização automática de
incidentes.

---

## 13. Ações corretivas e preventivas

| Ação | Prioridade | Status |
|---|---|---|
| Manter alerta de p95 > 2s | Alta | Implementado |
| Manter dashboard SRE/SLO | Alta | Implementado |
| Manter APM/Distributed Tracing | Alta | Implementado |
| Manter detecção de anomalia | Alta | Implementado |
| Manter recuperação via GitOps | Alta | Implementado |
| Documentar processo ITSM | Alta | Implementado |
| Registrar MTTR das simulações | Alta | Pendente |
| Avaliar autoscaling por métricas customizadas | Média | Backlog |
| Integrar ferramenta ITSM para ticket automático | Baixa | Backlog |

---

## 14. Lições aprendidas

O incidente demonstrou que um serviço pode permanecer disponível e
ainda assim violar seu objetivo de confiabilidade devido à latência.

Também demonstrou que o autoscaling deve utilizar métricas alinhadas
ao tipo de saturação que se deseja controlar.

A combinação de observabilidade, SLOs, alertas, AIOps e GitOps reduz o
tempo necessário para detectar, diagnosticar e recuperar o serviço.

---

## 15. Conclusão

O INC-001 validou de ponta a ponta o processo operacional do
SolidaryTech:

    Telemetria
        ↓
    Detecção
        ↓
    SLO violado
        ↓
    Alerta
        ↓
    AIOps
        ↓
    Diagnóstico
        ↓
    Mitigação GitOps
        ↓
    Recuperação
        ↓
    MTTR
        ↓
    Postmortem
        ↓
    Melhoria contínua

O resultado demonstra uma abordagem integrada entre SRE, ITSM,
AIOps, observabilidade e GitOps.

---

## Resultado da validação SRE

A reprodução controlada do incidente validou o ciclo completo de detecção, resposta e recuperação.

### Timeline

- **16:15:46:** início do incidente controlado.
- **16:18:20:** `DonationServiceHighLatency` entrou em FIRING.
- **16:32:51:** o alerta deixou o estado FIRING e a recuperação foi confirmada.

### MTTR observado

O MTTR foi calculado entre a detecção efetiva pelo monitoramento e a confirmação da recuperação:

```text
MTTR = resolved-time - firing-time
MTTR = 16:32:51 - 16:18:20
MTTR = 871 segundos
MTTR = 14 minutos e 31 segundos

```

### Comportamento dos SLIs

Durante o incidente:

- p95 de latência: aproximadamente **4,88 s**;
- Availability SLI: **100%**;
- SLO de latência <= 2 s: **violado**;
- alerta de alta latência: **FIRING**.

Após a mitigação:

- p95 de latência: aproximadamente **4,75 ms**;
- Availability SLI: **100%**;
- SLO de latência <= 2 s: **atendido**;
- alerta: **resolvido**.

A simulação demonstrou que disponibilidade e latência são SLIs independentes. O endpoint continuou disponível durante o incidente, mas a degradação de desempenho foi suficiente para violar o objetivo de nível de serviço.

### Validações realizadas

O exercício confirmou:

- detecção pelo Prometheus;
- visualização do impacto no Grafana;
- acionamento do `DonationServiceHighLatency`;
- mitigação via GitOps;
- recuperação do serviço;
- retorno ao SLO;
- mensuração objetiva do MTTR.
