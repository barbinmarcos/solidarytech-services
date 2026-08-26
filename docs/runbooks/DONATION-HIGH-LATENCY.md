# Runbook — DonationServiceHighLatency

## 1. Identificação

| Campo | Valor |
|---|---|
| Alerta | DonationServiceHighLatency |
| Serviço | donation-service |
| Ambiente | Production |
| Cluster | solidarytech-prod |
| Namespace | solidarytech |
| Severidade | Critical |
| SLI | Latência HTTP p95 |
| Endpoint principal | /donations |
| Threshold | p95 > 2 segundos |
| Duração | 1 minuto |

---

## 2. Objetivo

Este runbook descreve os procedimentos para diagnóstico, mitigação,
recuperação e validação de incidentes de alta latência no
`donation-service`.

O alerta `DonationServiceHighLatency` é disparado quando a latência
p95 do endpoint `/donations` permanece acima de 2 segundos por mais
de 1 minuto.

O objetivo operacional é:

1. Confirmar o incidente.
2. Determinar o impacto.
3. Identificar a causa raiz.
4. Aplicar mitigação através do fluxo GitOps.
5. Validar a recuperação.
6. Encerrar o incidente somente após normalização dos SLIs.

---

## 3. Arquitetura relacionada

    Cliente
       |
       v
 donation-service
       |
       +------> PostgreSQL / Amazon RDS
       |
       +------> AWS SQS
       |
       +------> OpenTelemetry
       |             |
       |             v
       |         New Relic
       |
       +------> /metrics
                     |
                     v
                 Prometheus
                     |
                     v
              PrometheusRule
                     |
                     v
                Alertmanager
                     |
                     v
                  Alerta

O `donation-service` fornece métricas Prometheus através do endpoint
`/metrics` e traces distribuídos através do OpenTelemetry.

---

## 4. Critério do alerta

A métrica utilizada para cálculo da latência é:

    donation_http_request_duration_seconds_bucket

O p95 é calculado utilizando:

    histogram_quantile(
      0.95,
      sum by (le) (
        rate(
          donation_http_request_duration_seconds_bucket{
            path="/donations"
          }[2m]
        )
      )
    )

O alerta é disparado quando:

    p95 > 2 segundos

por:

    1 minuto

PrometheusRule:

    DonationServiceHighLatency

Severidade:

    critical

---

## 5. Primeira resposta

Quando o alerta:

    DonationServiceHighLatency

entrar em estado `Firing`, registrar o horário de início da
investigação.

Fluxo inicial:

    Detected
       |
       v
    Acknowledged
       |
       v
    Investigating

Registrar no incidente:

- horário da detecção;
- serviço afetado;
- endpoint afetado;
- valor atual da latência;
- status do Deployment;
- status dos Pods;
- status do ArgoCD.

---

## 6. Verificar Pods

Executar:

    kubectl get pods \
      -n solidarytech \
      -l app=donation-service \
      -o wide

Resultado esperado:

    READY   STATUS    RESTARTS
    1/1     Running   0
    1/1     Running   0

Investigar imediatamente se houver:

- CrashLoopBackOff;
- Error;
- Pending;
- ImagePullBackOff;
- reinicializações frequentes;
- Pods não Ready.

Para acompanhar mudanças:

    kubectl get pods \
      -n solidarytech \
      -l app=donation-service \
      -w

---

## 7. Verificar Deployment

Executar:

    kubectl get deployment donation-service \
      -n solidarytech

Verificar rollout:

    kubectl rollout status deployment/donation-service \
      -n solidarytech

Verificar imagem atualmente implantada:

    kubectl get deployment donation-service \
      -n solidarytech \
      -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

Confirmar que o número de réplicas disponíveis corresponde ao
esperado.

---

## 8. Verificar eventos Kubernetes

Executar:

    kubectl get events \
      -n solidarytech \
      --sort-by='.lastTimestamp' | tail -30

Investigar principalmente:

- Pod restarts;
- OOMKilled;
- falha de probes;
- problemas de scheduling;
- erros de volume;
- problemas de rede;
- falha no pull da imagem;
- eviction;
- problemas relacionados aos Nodes.

Para um Pod específico:

    kubectl describe pod <POD_NAME> \
      -n solidarytech

---

## 9. Verificar logs

Consultar os últimos 10 minutos:

    kubectl logs \
      -n solidarytech \
      -l app=donation-service \
      --since=10m \
      --prefix

Filtrar possíveis erros:

    kubectl logs \
      -n solidarytech \
      -l app=donation-service \
      --since=10m \
      --prefix | \
      grep -Ei 'error|timeout|failed|fatal|database|postgres|sqs|otel|trace'

Investigar:

- timeout;
- erros de banco;
- erros de SQS;
- falhas de comunicação;
- erros HTTP;
- falhas do OpenTelemetry;
- erros de aplicação.

---

## 10. Medir latência diretamente

Criar um port-forward para o serviço:

    kubectl port-forward \
      -n solidarytech \
      svc/donation-service \
      18082:8082

Manter o terminal do port-forward aberto.

Em outro terminal, validar health check:

    curl -i http://127.0.0.1:18082/health

Resultado esperado:

    HTTP/1.1 200 OK

Medir a latência:

    curl -s -o /dev/null \
      -w 'status=%{http_code} latency=%{time_total}s\n' \
      http://127.0.0.1:18082/donations

Executar múltiplas medições:

    for i in $(seq 1 10); do
      curl -s -o /dev/null \
        -w "request=$i status=%{http_code} latency=%{time_total}s\n" \
        http://127.0.0.1:18082/donations
    done

Durante operação normal, espera-se latência significativamente abaixo
do SLO de 2 segundos.

---

## 11. Verificar configuração de simulação

O `donation-service` possui uma variável utilizada exclusivamente para
simulações controladas de degradação:

    SIMULATE_LATENCY_MS

Consultar o valor atualmente implantado:

    kubectl get deployment donation-service \
      -n solidarytech \
      -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="SIMULATE_LATENCY_MS")].value}{"\n"}'

Estado normal:

    0

Durante testes controlados pode ser utilizado, por exemplo:

    2500

Valores diferentes de `0` devem ser investigados quando não houver
um exercício de resiliência ou observabilidade em andamento.

A configuração é definida no Helm:

    helm/donation-service/values.yaml

Exemplo normal:

    simulateLatencyMs: "0"

Não modificar permanentemente essa variável diretamente no Deployment.

---

## 12. Prometheus

A aplicação disponibiliza métricas no endpoint:

    /metrics

A principal métrica utilizada pelo alerta é:

    donation_http_request_duration_seconds_bucket

Consulta PromQL para p95:

    histogram_quantile(
      0.95,
      sum by (le) (
        rate(
          donation_http_request_duration_seconds_bucket{
            path="/donations"
          }[2m]
        )
      )
    )

SLO:

    p95 < 2 segundos

Verificar a PrometheusRule:

    kubectl get prometheusrule donation-service-alerts \
      -n monitoring

Consultar detalhes:

    kubectl get prometheusrule donation-service-alerts \
      -n monitoring \
      -o yaml

O recurso é gerenciado pelo ArgoCD.

Para acesso local ao Prometheus:

    kubectl port-forward \
      -n monitoring \
      svc/monitoring-kube-prometheus-prometheus \
      19090:9090

A API de alertas pode ser consultada em outro terminal:

    curl -s http://127.0.0.1:19090/api/v1/alerts | \
      python3 -m json.tool

Estados relevantes:

    inactive
    pending
    firing

Fluxo esperado:

    p95 normal
        |
        v
    Inactive
        |
        | p95 > 2s
        v
    Pending
        |
        | 1 minuto
        v
    Firing

---

## 13. Grafana

Utilizar o Grafana para correlacionar o incidente com os Golden Signals.

Verificar principalmente:

- Latency;
- Traffic;
- Errors;
- Saturation.

No dashboard do `donation-service`, analisar o gráfico de latência p95
durante o período do incidente.

Comparar:

    baseline
       |
       v
    início da degradação
       |
       v
    violação do SLO
       |
       v
    mitigação
       |
       v
    recuperação

A análise temporal ajuda a determinar exatamente quando o incidente
começou e quando o serviço retornou ao comportamento normal.

---

## 14. New Relic / OpenTelemetry

O `donation-service` exporta traces através de OpenTelemetry.

Endpoint OTLP configurado:

    otlp.nr-data.net:4318

No New Relic:

1. Abrir Distributed Tracing / APM.
2. Selecionar `donation-service`.
3. Localizar `GET /donations`.
4. Verificar duração dos traces.
5. Comparar com o baseline.
6. Verificar operações lentas.
7. Correlacionar o horário com o alerta Prometheus.

Durante o teste controlado de latência foi possível observar:

    GET /donations
        |
        v
    ~2.5 segundos

A correlação entre Prometheus e New Relic permite determinar se a
degradação observada pelo SLI corresponde efetivamente ao comportamento
da aplicação.

Verificar também os logs relacionados ao OpenTelemetry:

    kubectl logs \
      -n solidarytech \
      -l app=donation-service \
      --since=10m | \
      grep -Ei 'otel|otlp|trace|export|403|401|error'

---

## 15. Banco de dados

O `donation-service` utiliza PostgreSQL no Amazon RDS.

### 15.1 Verificar estado da instância

Executar:

    aws rds describe-db-instances \
      --db-instance-identifier solidarytech-prod-postgres \
      --query 'DBInstances[0].[DBInstanceStatus,DBInstanceClass,MultiAZ,Endpoint.Address]' \
      --output table

Estado atual validado:

    Status:        available
    Instance:      db.t3.micro
    Multi-AZ:      False
    Endpoint:      solidarytech-prod-postgres.ccbsau2m4pss.us-east-1.rds.amazonaws.com

O estado:

    available

indica que a instância está operacional.

Entretanto, o estado `available` sozinho não garante ausência de
problemas de performance. Por isso também devem ser analisadas métricas
do CloudWatch.

### 15.2 Verificar CPU do RDS

`CPUUtilization` é uma métrica do Amazon CloudWatch e não um atributo
retornado por `describe-db-instances`.

Executar:

    aws cloudwatch get-metric-statistics \
      --namespace AWS/RDS \
      --metric-name CPUUtilization \
      --dimensions Name=DBInstanceIdentifier,Value=solidarytech-prod-postgres \
      --statistics Average Maximum \
      --period 300 \
      --start-time "$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
      --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --query 'Datapoints[*].[Timestamp,Average,Maximum]' \
      --output table

Investigar:

- CPU elevada;
- picos coincidentes com o incidente;
- utilização sustentada próxima do limite da instância.

### 15.3 Verificar conexões

Consultar:

    aws cloudwatch get-metric-statistics \
      --namespace AWS/RDS \
      --metric-name DatabaseConnections \
      --dimensions Name=DBInstanceIdentifier,Value=solidarytech-prod-postgres \
      --statistics Average Maximum \
      --period 300 \
      --start-time "$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
      --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --query 'Datapoints[*].[Timestamp,Average,Maximum]' \
      --output table

Investigar crescimento inesperado das conexões ou possível esgotamento
do pool utilizado pela aplicação.

### 15.4 Verificar latência de leitura

Executar:

    aws cloudwatch get-metric-statistics \
      --namespace AWS/RDS \
      --metric-name ReadLatency \
      --dimensions Name=DBInstanceIdentifier,Value=solidarytech-prod-postgres \
      --statistics Average Maximum \
      --period 300 \
      --start-time "$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
      --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --query 'Datapoints[*].[Timestamp,Average,Maximum]' \
      --output table

### 15.5 Verificar latência de escrita

Executar:

    aws cloudwatch get-metric-statistics \
      --namespace AWS/RDS \
      --metric-name WriteLatency \
      --dimensions Name=DBInstanceIdentifier,Value=solidarytech-prod-postgres \
      --statistics Average Maximum \
      --period 300 \
      --start-time "$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
      --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --query 'Datapoints[*].[Timestamp,Average,Maximum]' \
      --output table

### 15.6 Verificar conectividade pelo donation-service

Consultar:

    kubectl logs \
      -n solidarytech \
      -l app=donation-service \
      --since=15m \
      --prefix | \
      grep -Ei 'database|postgres|connection|timeout|failed|error'

Investigar principalmente:

- timeout de conexão;
- falha de conexão com PostgreSQL;
- queries lentas;
- excesso de conexões;
- saturação de CPU;
- aumento de ReadLatency;
- aumento de WriteLatency;
- problemas de rede entre EKS e RDS.

### 15.7 Backup e proteção

Estado atual validado para o RDS:

    BackupRetention:     1 dia
    DeletionProtection:  True
    MultiAZ:             False
    Status:              available

O ambiente utiliza retenção de backup de 1 dia devido às limitações
atuais do plano da conta AWS.

Uma tentativa de configurar retenção superior foi rejeitada pela AWS
devido à restrição do plano.

Portanto, retenção maior deve ser tratada como evolução futura e não
como funcionalidade atualmente implantada.

### 15.8 Considerações de resiliência

A instância atual utiliza:

    db.t3.micro
    Multi-AZ: False

Essa configuração reduz custos para o ambiente do projeto, porém não
fornece redundância Multi-AZ.

Para um ambiente de produção com requisitos mais rigorosos de
disponibilidade, considerar:

- habilitação de Multi-AZ;
- dimensionamento adequado da instância;
- maior retenção de backups;
- testes periódicos de Point-in-Time Recovery;
- monitoramento de conexões;
- monitoramento de CPU;
- monitoramento de ReadLatency e WriteLatency.

Essas alterações devem considerar requisitos de RTO, RPO e FinOps.

---

## 16. AWS SQS

O `donation-service` possui integração com Amazon SQS.

Verificar atributos da fila:

    aws sqs get-queue-attributes \
      --queue-url "$(terraform -chdir=terraform/environments/prod output -raw sqs_queue_url)" \
      --attribute-names \
        ApproximateNumberOfMessages \
        ApproximateNumberOfMessagesNotVisible

Investigar:

- crescimento anormal do backlog;
- mensagens não processadas;
- aumento de mensagens em processamento;
- falhas de publicação;
- problemas de IAM.

Também verificar a DLQ:

    aws sqs get-queue-attributes \
      --queue-url "$(terraform -chdir=terraform/environments/prod output -raw sqs_dlq_url)" \
      --attribute-names \
        ApproximateNumberOfMessages

Mensagens acumuladas na DLQ devem ser investigadas.

---

## 17. Recursos Kubernetes

Verificar utilização dos Pods:

    kubectl top pods \
      -n solidarytech \
      -l app=donation-service

Verificar Nodes:

    kubectl top nodes

Investigar:

- CPU elevada;
- memória elevada;
- throttling;
- saturação do Node;
- distribuição inadequada dos Pods.

---

## 18. HPA

O `donation-service` utiliza Horizontal Pod Autoscaler.

Verificar:

    kubectl get hpa \
      -n solidarytech

Detalhes:

    kubectl describe hpa donation-service \
      -n solidarytech

Configuração definida para o serviço:

    minReplicas: 2
    maxReplicas: 4
    targetCPUUtilizationPercentage: 60

Investigar se o serviço atingiu:

    maxReplicas = 4

e mesmo assim permanece saturado.

---

## 19. GitOps / ArgoCD

O ArgoCD é responsável pela reconciliação do estado desejado da
aplicação.

Verificar:

    argocd app get donation-service

Estado esperado:

    Sync Status:   Synced
    Health Status: Healthy

Listar aplicações:

    argocd app list

Verificar diferenças:

    argocd app diff donation-service

Sincronizar quando necessário:

    argocd app sync donation-service

Aguardar sincronização:

    argocd app wait donation-service \
      --sync \
      --health \
      --timeout 120

### Regra operacional

Não realizar alterações permanentes diretamente através de:

    kubectl edit
    kubectl patch
    kubectl set env

O Git é a fonte de verdade.

Uma alteração manual pode ser automaticamente revertida pelo
self-healing do ArgoCD.

Fluxo correto:

    alteração
       |
       v
      Git
       |
       v
    GitHub
       |
       v
    ArgoCD
       |
       v
    Kubernetes

---

## 20. Estratégia de mitigação

A mitigação deve depender da causa identificada.

### 20.1 Configuração incorreta

Corrigir:

    helm/donation-service/values.yaml

Validar:

    helm lint ./helm/donation-service

Depois:

    git add helm/donation-service/
    git commit -m "fix: mitigate donation service incident"
    git push origin main

Sincronizar:

    argocd app sync donation-service

### 20.2 Versão problemática

Identificar a última versão conhecida como estável.

Verificar histórico:

    git log --oneline

Realizar rollback através do Git, preservando o fluxo GitOps.

Não substituir permanentemente a imagem diretamente no Deployment.

### 20.3 Saturação da aplicação

Verificar:

    kubectl top pods \
      -n solidarytech \
      -l app=donation-service

Verificar HPA:

    kubectl get hpa \
      -n solidarytech

Se necessário, revisar:

- requests;
- limits;
- minReplicas;
- maxReplicas;
- targetCPUUtilizationPercentage.

Qualquer alteração permanente deve ser realizada no Helm/Terraform
apropriado e versionada no Git.

### 20.4 Problema de banco

Investigar:

- CPUUtilization;
- DatabaseConnections;
- ReadLatency;
- WriteLatency;
- logs da aplicação;
- conectividade;
- queries lentas.

Evitar aumentar capacidade sem antes confirmar a causa, preservando
os princípios de FinOps.

### 20.5 Problema de dependência

Investigar AWS SQS e outras dependências utilizadas pela aplicação.

Correlacionar:

    métricas
       +
    logs
       +
    traces

antes de determinar a mitigação.

---

## 21. Validação pós-mitigação

Após aplicar a correção, verificar o Deployment:

    kubectl rollout status deployment/donation-service \
      -n solidarytech

Verificar Pods:

    kubectl get pods \
      -n solidarytech \
      -l app=donation-service

Executar:

    for i in $(seq 1 10); do
      curl -s -o /dev/null \
        -w "request=$i status=%{http_code} latency=%{time_total}s\n" \
        http://127.0.0.1:18082/donations
    done

Esperado:

    HTTP 200
    latência abaixo do SLO

Confirmar ArgoCD:

    argocd app get donation-service

Esperado:

    Sync Status:   Synced
    Health Status: Healthy

---

## 22. Validar resolução do alerta

O alerta utiliza uma janela de:

    rate(...[2m])

Portanto, ele pode permanecer ativo por algum tempo após a mitigação,
até que as requisições lentas saiam da janela de cálculo.

Consultar:

    curl -s http://127.0.0.1:19090/api/v1/alerts | \
      python3 -m json.tool

O estado final esperado é:

    DonationServiceHighLatency
        |
        v
    Resolved / Inactive

A ausência do alerta na API `/api/v1/alerts` indica que ele não está
mais ativo.

---

## 23. Critérios para encerramento

O incidente somente deve ser considerado resolvido quando:

- Pods estiverem Running e Ready;
- Deployment estiver disponível;
- endpoint `/health` retornar HTTP 200;
- endpoint `/donations` estiver respondendo normalmente;
- latência p95 estiver novamente abaixo do SLO;
- alerta estiver Resolved/Inactive;
- ArgoCD estiver Synced;
- ArgoCD estiver Healthy;
- não houver crescimento anormal de erros;
- Grafana confirmar recuperação;
- New Relic confirmar normalização dos traces;
- dependências críticas estiverem operacionais.

---

## 24. MTTA e MTTR

Registrar:

    Detection Time
    Acknowledgement Time
    Mitigation Start Time
    Recovery Time

Calcular:

    MTTA = Acknowledgement Time - Detection Time

e:

    MTTR = Recovery Time - Detection Time

O objetivo é reduzir MTTA e MTTR através da combinação de:

- alertas automáticos;
- métricas;
- dashboards;
- tracing distribuído;
- runbooks;
- GitOps;
- automação operacional.

---

## 25. Escalonamento

Se a causa não puder ser determinada rapidamente, escalar de acordo
com o componente afetado.

### Aplicação

Responsável:

    Time de desenvolvimento / SRE

### Kubernetes / EKS

Responsável:

    Plataforma / DevOps / SRE

### PostgreSQL / RDS

Responsável:

    Plataforma / DBA / SRE

### AWS SQS

Responsável:

    Plataforma / Cloud / SRE

### Observabilidade

Responsável:

    SRE / Plataforma

Durante o escalonamento, fornecer:

- horário do incidente;
- alerta;
- gráficos;
- traces;
- logs;
- eventos Kubernetes;
- versão da aplicação;
- alterações recentes;
- estado das dependências.

---

## 26. Pós-incidente

Após a recuperação, criar ou atualizar o Post-Mortem.

Documento relacionado:

    docs/itsm/INCIDENT-DONATION-LATENCY.md

Registrar:

- impacto;
- timeline;
- causa raiz;
- detecção;
- mitigação;
- MTTA;
- MTTR;
- ações corretivas;
- ações preventivas;
- evidências.

---

## 27. Evidências recomendadas

Durante um exercício ou incidente real, capturar:

1. Grafana antes da degradação.
2. Grafana durante a degradação.
3. PrometheusRule criada.
4. Alerta em estado Pending.
5. Alerta em estado Firing.
6. New Relic mostrando traces lentos.
7. Resultado do curl mostrando latência elevada.
8. Estado dos Pods.
9. Estado do HPA.
10. Estado do RDS.
11. Métricas CloudWatch do RDS.
12. Commit responsável pela alteração.
13. ArgoCD realizando a sincronização.
14. Commit de mitigação.
15. Latência normal após recuperação.
16. Alerta Resolved/Inactive.
17. ArgoCD Synced/Healthy após recuperação.

---

## 28. Fluxo operacional completo

    DonationServiceHighLatency
              |
              v
           FIRING
              |
              v
         Acknowledge
              |
              v
      Kubernetes Health
              |
              +-------------------+
              |                   |
              v                   v
          Metrics               Logs
              |                   |
              v                   |
           Grafana                |
              |                   |
              +---------+---------+
                        |
                        v
                  New Relic Traces
                        |
                        v
                   Dependencies
                    /        \
                   v          v
                 RDS         SQS
                   \          /
                    \        /
                     v      v
                    Root Cause
                        |
                        v
                    Mitigation
                        |
                        v
                       Git
                        |
                        v
                     GitHub
                        |
                        v
                     ArgoCD
                        |
                        v
                   Kubernetes
                        |
                        v
                    Validation
                        |
             +----------+----------+
             |          |          |
             v          v          v
          Grafana   New Relic   Prometheus
             |          |          |
             +----------+----------+
                        |
                        v
                     RESOLVED

---

## 29. Princípios operacionais

Durante incidentes no `donation-service`:

1. Diagnosticar antes de alterar capacidade.
2. Correlacionar métricas, logs e traces.
3. Utilizar Git como fonte de verdade.
4. Evitar alterações manuais permanentes no cluster.
5. Preservar evidências do incidente.
6. Validar tecnicamente a recuperação.
7. Confirmar o SLO antes de encerrar o incidente.
8. Registrar MTTA e MTTR.
9. Produzir Post-Mortem quando aplicável.
10. Transformar aprendizados em ações preventivas.

---

## 30. Resumo do fluxo de resposta

    Detectar
       |
       v
    Confirmar
       |
       v
    Investigar
       |
       v
    Correlacionar
       |
       v
    Identificar causa
       |
       v
    Mitigar via GitOps
       |
       v
    Validar recuperação
       |
       v
    Confirmar SLO
       |
       v
    Resolver
       |
       v
    Post-Mortem
