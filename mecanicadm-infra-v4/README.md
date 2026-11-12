# Mecânica DM - Infraestrutura Kubernetes (Terraform + Kubernetes)

![Kubernetes](https://img.shields.io/badge/K8s-1.32-blue?logo=kubernetes)
![Terraform](https://img.shields.io/badge/Terraform-1.15.4-purple?logo=terraform)
![AWS](https://img.shields.io/badge/AWS-EKS-orange?logo=amazon-aws)

Repositório de infraestrutura que provisiona o cluster **Amazon EKS** e os add-ons de
plataforma (API Gateway Kong, ExternalDNS + Route 53, metrics-server e a stack de
observabilidade no New Relic) para a API **Mecânica DM** em produção.

> **Fronteira importante:** este repositório cuida do **cluster e dos add-ons**.
> Os manifests da aplicação (Deployment, Service, Ingress, HPA, seed/migrações),
> a imagem e os secrets da aplicação vivem no **repositório da app**.

## Estrutura

```
.
├── main.tf                 # VPC, EKS, namespaces, IRSA do ExternalDNS, SSM compartilhado
├── variables.tf            # variáveis do módulo raiz
├── providers.tf            # providers aws/kubernetes + backend S3
├── outputs.tf              # cluster_name, vpc_id, external_dns_*
├── dns/                    # hosted zone Route 53 (state separado)
├── k8s/
│   └── addons/
│       ├── kong/kong.yaml
│       ├── external-dns/external-dns.yaml
│       ├── metrics-server/components.yaml
│       └── observability/
│           ├── kube-state-metrics.yaml
│           ├── prometheus-agent.yaml
│           └── otel-collector.yaml
└── .github/workflows/
    ├── ci-cd.yml           # Terraform + add-ons
    ├── dns.yml             # hosted zone Route 53
    └── destroy.yml         # botão vermelho
```

## O que é gerenciado aqui

| Camada | Responsável |
|---|---|
| VPC, subnets, NAT, EKS, node group | Terraform (`main.tf`) |
| Namespaces `mecanicadm`, `kong`, `external-dns`, `observability` | Terraform |
| ServiceAccounts com IRSA (ExternalDNS) | Terraform |
| Parâmetros SSM `/mecanicadm/prod/vpc_id` e `/eks_node_sg_id` | Terraform |
| Add-ons Kong, ExternalDNS, metrics-server | `kubectl apply` no `ci-cd.yml` |
| Stack de observabilidade (kube-state-metrics, Prometheus Agent, OTel Collector) | `kubectl apply` no `ci-cd.yml` |
| Secret `newrelic-license-key` (namespace `observability`) | `ci-cd.yml`, a partir do GitHub secret `NEW_RELIC_LICENSE_KEY` |
| Hosted zone `mecanicadm.com.br` | `dns/` (state separado) |
| Deployment/Service/Ingress/HPA/seed da app | **repositório da app** |
| Secrets da app (mail, New Relic, banco) | **repositório da app** |

Não usamos mais **Helm** nem **External Secrets Operator** neste repositório.

## Pré-requisitos no GitHub

**Secrets** (environment `prod`):

| Secret | Uso |
|---|---|
| `AWS_ACCESS_KEY_ID` | credencial AWS da pipeline |
| `AWS_SECRET_ACCESS_KEY` | credencial AWS da pipeline |
| `NEW_RELIC_LICENSE_KEY` | license key (tipo `Ingest - License`) usada pela stack de observabilidade; se ausente, a stack é ignorada com warning |

**Variables** (opcionais — os workflows têm defaults):

| Variable | Default | Uso |
|---|---|---|
| `AWS_REGION` | `us-east-1` | região AWS |
| `TF_STATE_BUCKET` | `mecanicadm-v4-01` | bucket do state |
| `TF_STATE_KEY` | `terraform/mecanicadm-v4/terraform.tfstate` | key do state da raiz |
| `EKS_CLUSTER_NAME` | `mecanicadm-prod` | nome do cluster (também vira `TF_VAR_cluster_name`) |

> As credenciais estáticas são uma pendência conhecida: o ideal é migrar para
> **OIDC** (`role-to-assume`), eliminando os access keys.

## State

- Bucket S3 `mecanicadm-v4-01`, key `terraform/mecanicadm-v4/terraform.tfstate`.
- **Sem workspaces**: um único ambiente (`prod`).
- **Lock nativo do S3** (`use_lockfile=true`), suportado a partir do Terraform 1.10.
  Requer versionamento no bucket — o `ci-cd.yml` garante isso.
- O DNS usa state separado (`terraform/mecanicadm-dns/terraform.tfstate`) para que a
  hosted zone não morra junto com o cluster.

## Primeira subida (do zero)

1. **DNS** (uma vez): rode o workflow `DNS - Hosted Zone Route 53` e cadastre os
   nameservers exibidos no Registro.br.
2. **Infra**: rode o `CI/CD - Terraform EKS + Kubernetes` na `main`. Em um ambiente
   vazio o workflow cria VPC + EKS primeiro (`-target=module.eks`), porque o provider
   `kubernetes` depende do cluster existir; depois faz o plan/apply do restante e
   aplica os add-ons.
3. **App**: o pipeline do repositório da app faz o deploy no namespace `mecanicadm`.

Para o passo a passo manual, veja [INSTRUCOES_TERRAFORM_MANUAL.md](INSTRUCOES_TERRAFORM_MANUAL.md).

## Pipelines

### `ci-cd.yml`
Dispara em `push`/`pull_request` na `main` quando muda `*.tf`, `.terraform.lock.hcl`,
`k8s/**` ou o próprio workflow, além de `workflow_dispatch`.

- PR: init → fmt → validate → plan (sem apply).
- `main`/manual: bootstrap do cluster (se necessário) → plan → apply → kubeconfig →
  add-ons → stack de observabilidade → rollout → verificação do IRSA do ExternalDNS.

### `dns.yml`
Manual. Executa o Terraform de `dns/` (state separado) e imprime os nameservers.

### `destroy.yml`
Manual, exige digitar `DESTRUIR`. Remove os add-ons antes do destroy (para liberar o
NLB do Kong), executa `terraform destroy` e lista recursos órfãos.

## Add-ons

- **Kong** (`k8s/addons/kong/kong.yaml`): Gateway + Ingress Controller, exposto por um
  Service `LoadBalancer` (NLB) descoberto pelo ExternalDNS.
- **ExternalDNS** (`k8s/addons/external-dns/external-dns.yaml`): sincroniza Services
  `LoadBalancer` e Ingresses com o Route 53. A autenticação é via IRSA — o
  ServiceAccount é criado pelo Terraform com a anotação `eks.amazonaws.com/role-arn`.
- **metrics-server** (`k8s/addons/metrics-server/components.yaml`): fornece métricas
  para o HPA da app. Usa `--kubelet-insecure-tls` porque os certificados de serving do
  kubelet no EKS são autoassinados.
- **kube-state-metrics** (`k8s/addons/observability/kube-state-metrics.yaml`): expõe o
  estado dos objetos do cluster (Deployments, Pods, Nodes, HPA, Jobs).
- **Prometheus Agent** (`k8s/addons/observability/prometheus-agent.yaml`): faz scrape do
  kube-state-metrics e envia via `remote_write` para o New Relic.
- **OpenTelemetry Collector** (`k8s/addons/observability/otel-collector.yaml`): DaemonSet
  com `kubeletstats` (CPU/memória de node, pod e container), `k8s_cluster` (estado do
  cluster) e `k8s_events` (OOMKilled, FailedScheduling etc.), exportando via OTLP/HTTP.
  `k8s_cluster`/`k8s_events` usam o `k8s_leader_elector` (lease no namespace
  `observability`), então só o pod líder coleta — sem séries duplicadas por node.

## Observabilidade

O APM da aplicação é feito pelo **New Relic Java agent** no repositório da app. A parte
de **cluster** que antes vinha do `nri-bundle` (Helm) foi reconstruída sem Helm:

| Dado | Origem | Como chega ao New Relic |
|---|---|---|
| CPU/memória/rede por node, pod e container | `otel-collector` (`kubeletstats`) | OTLP/HTTP (`otlp.nr-data.net:4318`) |
| Estado do cluster (nodes Ready, pods por fase) | `otel-collector` (`k8s_cluster`) | OTLP/HTTP |
| Eventos do cluster | `otel-collector` (`k8s_events`) | OTLP/HTTP (logs) |
| Deployments, réplicas, HPA, Jobs, PVCs | `kube-state-metrics` | Prometheus `remote_write` |
| Latência, erros, traces, JVM, slow queries | Java agent (repo da app) | APM |

Pontos de atenção:

- A license key **não** fica em nenhum manifest. A pipeline cria o secret
  `newrelic-license-key` no namespace `observability` a partir do GitHub secret
  `NEW_RELIC_LICENSE_KEY`; o collector e o Prometheus leem de lá
  (`secretKeyRef` e `credentials_file`).
- Endpoints usados são os da conta **US**. Para EU/JP, ajuste o endpoint do
  `otel-collector` e a URL do `remote_write` (comentários no topo de cada manifest).
- Para desligar a stack: `-var="observability_enabled=false"` (ou repo variable
  equivalente). Sem a license key a pipeline também pula a stack, com `::warning::`.
- Os nomes de cluster/ambiente enviados como labels são `mecanicadm-prod` e `prod`
  (`resource/cluster` no collector e `external_labels` no Prometheus).

Consultas úteis no New Relic (NRQL):

```sql
-- CPU por pod no namespace da app
FROM Metric SELECT average(k8s.pod.cpu.usage) FACET k8s.pod.name
WHERE k8s.namespace.name = 'mecanicadm' TIMESERIES

-- Réplicas desejadas vs disponíveis por deployment
FROM Metric SELECT latest(kube_deployment_spec_replicas), latest(kube_deployment_status_replicas_available)
FACET deployment WHERE cluster = 'mecanicadm-prod'

-- Eventos recentes do cluster
FROM Log SELECT * WHERE k8s.event.reason IS NOT NULL SINCE 1 hour ago
```

## Troubleshooting

**Observabilidade sem dados no New Relic**
```bash
kubectl -n observability get pods
kubectl -n observability logs ds/otel-collector --tail=100
kubectl -n observability logs deploy/prometheus-agent --tail=100
kubectl -n observability get lease otel-collector-cluster
```
- `401`/`403` nos logs → license key inválida/ausente; confira o secret
  `newrelic-license-key` (a pipeline só o cria se `NEW_RELIC_LICENSE_KEY` existir).
- `kubeletstats` com erro de conexão → o pod não alcança `https://<nodeIP>:10250`.
- Lease sem líder → verifique se o pod do collector tem permissão em `leases`
  (Role `otel-collector-lease`).

**IRSA não injetado no ExternalDNS**
```bash
kubectl -n external-dns get pod -l app.kubernetes.io/name=external-dns \
  -o jsonpath='{.items[0].spec.containers[0].env[?(@.name=="AWS_ROLE_ARN")].value}'
```
Se vier vazio, verifique o webhook de identidade (`eks-pod-identity-webhook`) do cluster.

**Plan falha com "cluster not found"**
O cluster não existe e o provider `kubernetes` não consegue ser configurado. Rode o
workflow na `main` (bootstrap automático) ou manualmente:
```bash
terraform apply -target=module.eks -auto-approve
```

**NLB órfão após destroy**
Rode o `destroy.yml` (ele remove o Kong antes) ou delete o manifest manualmente:
```bash
kubectl delete -f k8s/addons/kong/kong.yaml --ignore-not-found
```
