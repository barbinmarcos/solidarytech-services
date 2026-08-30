# Arquitetura SolidaryTech

Esta documentação apresenta a arquitetura da plataforma SolidaryTech implantada na AWS, incluindo o fluxo de CI/CD, GitOps, execução dos microsserviços, observabilidade, mensageria, persistência de dados e estratégias de backup e disaster recovery.

## Arquitetura Geral

A arquitetura geral apresenta o fluxo completo da solução, desde o GitHub Actions até o deploy no Amazon EKS, além das integrações com Amazon RDS, Amazon DynamoDB, Amazon SQS, Prometheus, Grafana, Alertmanager, OpenTelemetry, New Relic e Velero.

![Arquitetura Geral SolidaryTech](./solidarytech-architecture-overview.png)

## Arquitetura dos Microsserviços

A visão detalhada apresenta os três microsserviços da plataforma:

- `donation-service`
  - Amazon EKS
  - Amazon RDS PostgreSQL
  - Amazon SQS
  - Amazon SQS DLQ
  - Prometheus
  - Grafana
  - Alertmanager
  - OpenTelemetry
  - New Relic

- `ngo-service`
  - Amazon EKS
  - Amazon RDS PostgreSQL
  - Prometheus
  - Grafana
  - OpenTelemetry
  - New Relic

- `volunteer-service`
  - Amazon EKS
  - Amazon DynamoDB
  - Prometheus
  - Grafana
  - OpenTelemetry
  - New Relic

![Arquitetura dos Microsserviços](./solidarytech-microservices-architecture.png)

## CI/CD e GitOps

O fluxo de entrega utiliza GitHub Actions para testes, validações de segurança, build da imagem e publicação no Amazon ECR.

A autenticação com a AWS utiliza OIDC e IAM Role temporária.

Após a publicação da imagem, o repositório GitOps é atualizado e o ArgoCD realiza a reconciliação do estado desejado no Amazon EKS.

## Observabilidade e SRE

A solução utiliza:

- Prometheus para coleta de métricas.
- Grafana para dashboards.
- Alertmanager para alertas.
- OpenTelemetry para instrumentação e tracing.
- New Relic para APM e análise de traces.

## Backup e Disaster Recovery

A estratégia de continuidade utiliza:

- Velero para backup dos workloads Kubernetes.
- Amazon S3 para armazenamento dos backups do Velero.
- Amazon RDS Backup e PITR para recuperação do PostgreSQL.
- Terraform para reconstrução da infraestrutura.
