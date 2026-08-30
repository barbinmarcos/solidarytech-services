# SolidaryTech — Plano de Continuidade de Negócios e Disaster Recovery

## 1. Objetivo

Este documento define a estratégia de continuidade de negócios e
recuperação de desastre da plataforma SolidaryTech.

O objetivo é reduzir o impacto de falhas severas e estabelecer
procedimentos claros para recuperação dos serviços críticos.

---

## 2. Escopo

O plano cobre principalmente:

- donation-service;
- ngo-service;
- volunteer-service;
- cluster Amazon EKS;
- PostgreSQL RDS;
- DynamoDB;
- objetos Kubernetes;
- configurações GitOps;
- infraestrutura provisionada por Terraform.

O fluxo de doações é considerado o componente de maior criticidade
operacional.

---

## 3. Serviço crítico

### donation-service

Responsável pelo fluxo de registro de doações.

Dependências principais:

- Amazon EKS;
- PostgreSQL RDS;
- SQS;
- ArgoCD;
- imagens armazenadas no Amazon ECR;
- configurações Helm/GitOps.

Por estar diretamente relacionado ao fluxo principal de negócio, o
donation-service possui prioridade máxima de recuperação.

---

## 4. RTO

### Recovery Time Objective

O RTO representa o tempo máximo desejado para restaurar um serviço
após uma interrupção severa.

Para o fluxo crítico de doações, o objetivo definido é:

    RTO <= 60 minutos

Esse valor considera:

- identificação do desastre;
- diagnóstico;
- recuperação do cluster ou workloads;
- restauração de configurações;
- restauração dos dados quando necessária;
- validação funcional.

O valor deverá ser refinado com base em exercícios periódicos de DR.

---

## 5. RPO

### Recovery Point Objective

O RPO representa a quantidade máxima aceitável de perda de dados
medida em tempo.

Para os dados críticos de doação:

    RPO <= 24 horas

O objetivo está alinhado à política de backup disponível no ambiente
atual.

A plataforma deve evoluir esse valor conforme requisitos de negócio
mais restritivos forem definidos.

---

## 6. Estratégia de recuperação

A estratégia combina múltiplos mecanismos.

### Infraestrutura como Código

A infraestrutura é declarada utilizando Terraform.

Isso permite reconstruir componentes da plataforma a partir de código
versionado.

Fluxo:

    Terraform
       |
       v
    AWS
       |
       v
    Infraestrutura reconstruída

---

### GitOps

Os workloads Kubernetes são definidos declarativamente e reconciliados
pelo ArgoCD.

Em caso de reconstrução do cluster:

    Git
      |
      v
    ArgoCD
      |
      v
    Helm / Kubernetes
      |
      v
    Workloads restaurados

---

### Velero

O Velero é utilizado para backup e recuperação de objetos Kubernetes.

Ele permite restaurar recursos como:

- deployments;
- services;
- configmaps;
- secrets;
- objetos Kubernetes incluídos no backup.

O processo de backup e restore foi validado em exercício prático.

---

### PostgreSQL RDS

O banco PostgreSQL utiliza o mecanismo de backup gerenciado do Amazon
RDS.

No ambiente atual, a retenção configurada está limitada a 1 dia.

A recuperação deve utilizar backup ou point-in-time recovery quando
aplicável dentro da janela disponível.

---

### DynamoDB

O volunteer-service utiliza DynamoDB.

A estratégia de continuidade deve considerar os mecanismos nativos de
backup e recuperação da AWS conforme a criticidade dos dados.

---

## 7. Cenários de desastre

### Cenário 1 — Falha de Pod

Mitigação:

- Kubernetes ReplicaSet;
- probes;
- restart automático;
- self-healing.

Impacto esperado:

baixo.

---

### Cenário 2 — Falha de Node

Mitigação:

- múltiplos nodes;
- rescheduling automático;
- EKS managed node group.

Impacto esperado:

limitado, desde que exista capacidade disponível.

---

### Cenário 3 — Falha de Deployment

Mitigação:

- GitOps;
- ArgoCD;
- rollback;
- reconciliação do estado desejado.

---

### Cenário 4 — Perda de Objetos Kubernetes

Mitigação:

- repositório GitOps;
- Terraform;
- Velero.

---

### Cenário 5 — Corrupção ou perda de dados PostgreSQL

Mitigação:

- backups do RDS;
- point-in-time recovery dentro da janela disponível.

---

### Cenário 6 — Perda completa do cluster

Fluxo de recuperação:

1. provisionar ou recuperar infraestrutura via Terraform;
2. validar acesso ao cluster;
3. reinstalar componentes de plataforma;
4. reinstalar ArgoCD;
5. restaurar objetos necessários com Velero;
6. sincronizar aplicações via GitOps;
7. validar acesso às dependências;
8. executar testes funcionais;
9. validar observabilidade;
10. liberar o ambiente.

---

## 8. Procedimento de recuperação com Velero

Exemplo de inspeção dos backups:

    velero backup get

Detalhes:

    velero backup describe <backup-name> --details

Restore:

    velero restore create \
      --from-backup <backup-name>

Acompanhar:

    velero restore get

Detalhes:

    velero restore describe <restore-name> --details

Após a recuperação devem ser executados:

    kubectl get pods -A
    kubectl get deployments -n solidarytech
    kubectl get services -n solidarytech

---

## 9. Validação pós-recuperação

A recuperação somente é considerada concluída quando:

- workloads estão Ready;
- aplicações respondem aos health checks;
- donation-service consegue processar requisições;
- dependências de banco estão acessíveis;
- ArgoCD está Healthy/Synced;
- Prometheus coleta métricas;
- Grafana apresenta telemetria;
- alertas críticos estão normalizados.

---

## 10. Priorização de recuperação

Ordem recomendada:

    1. Infraestrutura base
    2. EKS
    3. Dependências de dados
    4. ArgoCD
    5. donation-service
    6. ngo-service
    7. volunteer-service
    8. Observabilidade
    9. Serviços complementares

O donation-service recebe prioridade por estar associado ao fluxo
principal de doações.

---

## 11. Responsabilidades

### Incident Commander

Coordena a recuperação e comunicação.

### Plataforma / DevOps

Responsável por:

- Terraform;
- Kubernetes;
- ArgoCD;
- Velero;
- infraestrutura AWS.

### Aplicação

Responsável por:

- validação funcional;
- análise de erros;
- consistência da aplicação.

### Negócio

Responsável por:

- avaliação do impacto;
- priorização;
- comunicação com stakeholders.

---

## 12. Comunicação

Durante um desastre, a comunicação deve incluir:

### Início

- horário;
- serviços afetados;
- impacto;
- severidade;
- investigação iniciada.

### Durante a recuperação

- progresso;
- serviços recuperados;
- riscos;
- previsão de próxima atualização.

### Encerramento

- horário da recuperação;
- impacto final;
- RTO observado;
- RPO observado;
- ações posteriores.

---

## 13. Testes de DR

O plano deve ser validado periodicamente.

Exemplos:

- exclusão controlada de recursos Kubernetes;
- restore com Velero;
- reconstrução de infraestrutura não produtiva;
- validação de backups;
- teste de recuperação de banco;
- validação de GitOps após reconstrução.

Os resultados devem ser registrados como evidência operacional.

---

## 14. Evidências atuais

A plataforma já possui evidências de:

- infraestrutura definida em Terraform;
- aplicações declaradas via Helm/GitOps;
- ArgoCD realizando reconciliação;
- self-healing Kubernetes;
- backup com Velero;
- restore com Velero;
- RDS com backup gerenciado;
- monitoramento pós-recuperação.

---

## 15. Melhorias futuras

- aumentar a janela de retenção de backup quando permitido;
- validar PITR periodicamente;
- automatizar testes de restore;
- avaliar backup nativo do DynamoDB;
- avaliar replicação entre regiões conforme criticidade;
- revisar RTO/RPO com stakeholders;
- criar runbook automatizado para reconstrução completa;
- realizar exercícios periódicos de disaster recovery.

---

## 16. Conclusão

A estratégia de continuidade do SolidaryTech combina:

    Terraform
       +
    GitOps
       +
    Kubernetes
       +
    Velero
       +
    Serviços gerenciados AWS

Essa abordagem reduz dependência de procedimentos manuais e aumenta a
capacidade de reconstrução e recuperação da plataforma.

Os objetivos definidos são:

    RTO <= 60 minutos
    RPO <= 24 horas

Esses valores devem ser revisados periodicamente com base nos testes
reais de recuperação e nos requisitos do negócio.
