# SolidaryTech — Processo de Gestão de Incidentes

## 1. Objetivo

Este documento define o processo de gerenciamento de incidentes do
SolidaryTech, integrando práticas de ITSM, SRE, GitOps, Observabilidade
e AIOps.

O objetivo é detectar rapidamente degradações, reduzir o MTTR,
restabelecer o serviço e registrar evidências para melhoria contínua.

---

## 2. Fluxo do incidente

O ciclo de tratamento de incidentes segue:

Observabilidade / AIOps
        |
        v
Detecção
        |
        v
Alerta
        |
        v
Registro do incidente
        |
        v
Triagem e classificação
        |
        v
Diagnóstico
        |
        v
Mitigação
        |
        v
Validação da recuperação
        |
        v
Encerramento
        |
        v
Postmortem / melhoria contínua

### Ferramentas utilizadas

| Etapa | Ferramenta |
|---|---|
| Métricas | Prometheus |
| Visualização | Grafana |
| Alertas | PrometheusRule / Alertmanager |
| Notificação | Slack |
| APM / Distributed Tracing | New Relic |
| Detecção de anomalias | New Relic AIOps |
| Orquestração | Kubernetes / EKS |
| Autoscaling | HPA |
| GitOps | ArgoCD |
| Infraestrutura | Terraform |
| Recuperação Kubernetes | Velero |

---

## 3. Classificação de severidade

### SEV-1 — Crítico

Indisponibilidade completa ou impacto direto no fluxo crítico de
doações.

Exemplos:

- donation-service indisponível;
- perda ou corrupção de dados;
- impossibilidade de registrar doações;
- falha generalizada da plataforma.

Resposta: imediata.

---

### SEV-2 — Alto

Serviço disponível, porém com degradação significativa ou violação
de SLO.

Exemplos:

- p95 do donation-service acima de 2 segundos;
- aumento significativo da taxa de erros;
- degradação persistente detectada pelo AIOps.

Resposta: prioritária.

---

### SEV-3 — Médio

Falha parcial sem impacto significativo no fluxo crítico.

Exemplos:

- degradação isolada em serviço não crítico;
- falha de uma réplica sem indisponibilidade;
- problema operacional com mecanismo automático de recuperação.

---

### SEV-4 — Baixo

Evento sem impacto imediato ao usuário.

Exemplos:

- alerta preventivo;
- oportunidade de otimização;
- problema de capacidade ainda sem impacto.

---

## 4. Detecção

O ambiente utiliza múltiplas fontes de observabilidade.

### Prometheus

Coleta métricas técnicas e métricas da aplicação.

Exemplos:

- taxa de requisições;
- duração das requisições;
- CPU;
- memória;
- disponibilidade;
- número de réplicas.

### Grafana

Centraliza os dashboards operacionais e SRE.

O dashboard SRE acompanha, entre outros indicadores:

- p95 de latência;
- disponibilidade;
- cumprimento do SLO;
- estado dos alertas;
- comportamento do HPA.

### New Relic AIOps

O New Relic complementa o monitoramento baseado em thresholds através
da identificação de comportamento anômalo.

Para o donation-service é monitorado o p95 da duração das operações de
doação, permitindo detectar desvios em relação ao comportamento
esperado.

---

## 5. Registro e triagem

Quando um alerta é identificado, devem ser registrados:

- data e hora da detecção;
- serviço afetado;
- severidade;
- alerta responsável pela detecção;
- SLI/SLO afetado;
- impacto observado;
- responsável pelo tratamento;
- status atual.

O incidente passa inicialmente para:

OPEN -> INVESTIGATING

Durante a triagem são verificadas as métricas, traces, logs e o estado
dos workloads Kubernetes.

---

## 6. Diagnóstico

O diagnóstico utiliza correlação entre:

- métricas Prometheus;
- dashboards Grafana;
- distributed tracing / APM;
- eventos Kubernetes;
- estado do HPA;
- estado do ArgoCD;
- logs das aplicações.

Exemplos de comandos:

    kubectl get pods -n solidarytech
    kubectl get hpa -n solidarytech
    kubectl top pods -n solidarytech
    kubectl describe deployment donation-service -n solidarytech

O objetivo é determinar se o incidente está relacionado a:

- aplicação;
- dependência externa;
- infraestrutura;
- capacidade;
- configuração;
- deployment;
- banco de dados;
- rede.

---

## 7. Mitigação

As alterações permanentes devem seguir o modelo GitOps:

Git
 |
 v
Alteração declarativa
 |
 v
ArgoCD
 |
 v
Kubernetes/EKS

Evita-se alterar diretamente o estado desejado da aplicação através de
mudanças manuais no cluster.

Dependendo do incidente, podem ser utilizados mecanismos como:

- rollback;
- alteração de configuração;
- correção da aplicação;
- autoscaling;
- restart controlado;
- recuperação via Velero.

---

## 8. Validação da recuperação

Após a mitigação, a recuperação deve ser comprovada por evidências.

Para um incidente de latência do donation-service, por exemplo:

- aplicação permanece disponível;
- p95 retorna para <= 2 segundos;
- alerta deixa o estado FIRING;
- New Relic deixa de indicar a condição anômala;
- métricas retornam ao baseline;
- ArgoCD permanece Healthy/Synced.

O incidente somente deve ser encerrado após validação técnica.

---

## 9. MTTR

O SolidaryTech utiliza MTTR como indicador de eficiência operacional.

    MTTR = horário da recuperação - horário da detecção

A observabilidade reduz o tempo de identificação e diagnóstico,
enquanto GitOps e automação reduzem o tempo necessário para aplicar
e validar a recuperação.

Cada incidente relevante deve registrar seu MTTR.

---

## 10. Estados do incidente

Fluxo padrão:

    OPEN
      |
      v
    INVESTIGATING
      |
      v
    MITIGATING
      |
      v
    MONITORING
      |
      v
    RESOLVED
      |
      v
    CLOSED

### OPEN

Incidente detectado.

### INVESTIGATING

Equipe realizando triagem e diagnóstico.

### MITIGATING

Ação corretiva ou mitigatória em andamento.

### MONITORING

Correção aplicada e ambiente sendo observado.

### RESOLVED

Serviço tecnicamente recuperado.

### CLOSED

Evidências, comunicação e postmortem concluídos.

---

## 11. Critérios de encerramento

Um incidente somente pode ser marcado como CLOSED quando:

- serviço estiver operacional;
- SLI estiver dentro do SLO;
- alerta estiver resolvido;
- impacto tiver cessado;
- MTTR tiver sido registrado;
- evidências estiverem preservadas;
- stakeholders tiverem recebido comunicação;
- postmortem tiver sido registrado quando aplicável.

---

## 12. Postmortem

Incidentes relevantes devem produzir um postmortem contendo:

1. resumo executivo;
2. impacto;
3. timeline;
4. detecção;
5. causa;
6. mitigação;
7. recuperação;
8. MTTR;
9. fatores contribuintes;
10. ações corretivas;
11. ações preventivas;
12. responsáveis e prazos.

O postmortem deve ter foco em melhoria de processos, arquitetura,
automação e confiabilidade.

---

## 13. Comunicação

A comunicação deve ocorrer em três momentos principais.

### Abertura

Informar:

- serviço afetado;
- impacto;
- severidade;
- início do incidente;
- investigação em andamento.

### Atualização

Informar:

- diagnóstico atual;
- ações realizadas;
- estado do serviço;
- próximos passos.

### Encerramento

Informar:

- horário de recuperação;
- impacto final;
- MTTR;
- situação atual;
- necessidade de postmortem.

---

## 14. Integração SRE + ITSM + AIOps

A estratégia operacional do SolidaryTech combina:

    SRE
     +
    Observabilidade
     +
    AIOps
     +
    ITSM
     +
    GitOps

SRE define os objetivos de confiabilidade.

Prometheus e Grafana fornecem observabilidade operacional.

New Relic adiciona APM, distributed tracing e detecção de anomalias.

Alertmanager e Slack permitem comunicação operacional.

ITSM organiza o ciclo de tratamento do incidente.

GitOps fornece um processo controlado e auditável para recuperação.

Essa integração permite reduzir o tempo entre detecção, diagnóstico,
mitigação e recuperação, contribuindo diretamente para redução do MTTR.
