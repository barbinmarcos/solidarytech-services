# SolidaryTech — Service Level Agreement (SLA)

## 1. Objetivo

Este documento estabelece os níveis de serviço definidos para o
fluxo crítico de doações da plataforma SolidaryTech.

O SLA utiliza os indicadores técnicos monitorados pela plataforma
como base para avaliação da qualidade e confiabilidade do serviço.

---

## 2. Serviço crítico

Serviço:

    donation-service

Operação crítica:

    POST /donations

Ambiente:

    Production

O donation-service é considerado crítico por participar diretamente
do fluxo de registro de doações.

---

## 3. Indicadores

### Disponibilidade

A disponibilidade é calculada a partir das requisições ao fluxo de
doações.

Objetivo:

    >= 99,9%

Janela de avaliação:

    30 dias

---

### Latência

Indicador:

    p95 das requisições POST /donations

Objetivo:

    p95 <= 2 segundos

A latência é tratada separadamente da disponibilidade.

Um serviço pode estar disponível e ainda apresentar degradação de
performance.

---

## 4. SLI

Os principais Service Level Indicators são:

### SLI 1 — Latência

    p95 POST /donations

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

### SLI 2 — Sucesso

Percentual de requisições POST /donations concluídas com sucesso.

PromQL:

    100 *
    sum(
      increase(
        donation_http_requests_total{
          method="POST",
          path="/donations",
          status="Created"
        }[30d]
      )
    )
    /
    sum(
      increase(
        donation_http_requests_total{
          method="POST",
          path="/donations"
        }[30d]
      )
    )

---

## 5. SLO

Os objetivos internos de confiabilidade são:

| Indicador | SLO |
|---|---|
| Sucesso das doações | >= 99,9% |
| Latência p95 | <= 2 segundos |

Os SLOs são utilizados para orientar alertas, dashboards,
investigações e decisões operacionais.

---

## 6. SLA

O nível de serviço estabelecido para o fluxo crítico é:

    Disponibilidade/Sucesso >= 99,9%

A avaliação considera uma janela de 30 dias.

A latência possui objetivo operacional adicional:

    p95 <= 2 segundos

Violações devem gerar análise operacional quando persistentes e
atender aos critérios configurados de alerta.

---

## 7. Error Budget

Para um SLO de 99,9%, o Error Budget corresponde a:

    100% - 99,9% = 0,1%

Para o fluxo baseado em requisições, o orçamento é calculado sobre o
volume total de requisições.

Exemplo:

    Total de requisições = 100.000
    Error Budget = 0,1%
    Falhas permitidas = 100

Portanto, o Error Budget utilizado neste contexto é baseado em
eventos/requisições e não em minutos de indisponibilidade.

---

## 8. Monitoramento

O cumprimento dos objetivos é acompanhado através de:

- Prometheus;
- Grafana;
- PrometheusRule;
- Alertmanager;
- Slack;
- OpenTelemetry;
- New Relic APM/AIOps.

O dashboard SRE consolida os principais indicadores de
confiabilidade.

---

## 9. Gestão de violações

Quando um SLO é violado de forma persistente:

    Detecção
       ↓
    Alerta
       ↓
    Incidente
       ↓
    Triagem
       ↓
    Mitigação
       ↓
    Recuperação
       ↓
    MTTR
       ↓
    Postmortem

O processo segue o procedimento ITSM documentado pelo SolidaryTech.

---

## 10. Continuidade

Para cenários de desastre, o Plano de Continuidade de Negócios define:

    RTO <= 60 minutos
    RPO <= 24 horas

Esses objetivos são tratados separadamente dos objetivos normais de
nível de serviço.

---

## 11. Exclusões

Eventos planejados ou situações externas podem exigir avaliação
específica, incluindo:

- manutenção previamente comunicada;
- indisponibilidade de serviços externos fora do controle da
  plataforma;
- eventos de força maior;
- testes controlados de resiliência;
- simulações autorizadas de incidentes.

Esses eventos devem permanecer registrados para fins de auditoria e
análise.

---

## 12. Revisão

Os níveis de serviço devem ser revisados periodicamente com base em:

- comportamento real da plataforma;
- volume de utilização;
- incidentes;
- Error Budget;
- requisitos de negócio;
- resultados dos exercícios de DR.

---

## 13. Conclusão

O modelo de confiabilidade do SolidaryTech relaciona:

    SLI -> mede
    SLO -> define o objetivo interno
    SLA -> estabelece o compromisso de serviço
    Error Budget -> define a margem operacional

Para o fluxo crítico de doações:

    Sucesso >= 99,9%
    p95 <= 2 segundos
    Error Budget = 0,1%

Esses indicadores são acompanhados continuamente através da camada
de observabilidade da plataforma.
