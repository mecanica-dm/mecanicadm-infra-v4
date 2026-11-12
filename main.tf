# Cria VPC — rede isolada do cluster (módulo comunitário reutilizável)
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "mecanicadm-${var.environment}"
  cidr = var.vpc_cidr

  # Três AZs garantem alta disponibilidade do plano de dados.
  azs             = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnets = [for i, az in ["${var.region}a", "${var.region}b", "${var.region}c"] : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, az in ["${var.region}a", "${var.region}b", "${var.region}c"] : cidrsubnet(var.vpc_cidr, 4, i + 3)]

  # NAT Gateway garante que o cluster acesse a internet (ex.: pull de imagens).
  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Environment = var.environment }
}

# Cria Cluster EKS — Kubernetes gerenciado pela AWS (control plane HA)
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Endpoint PRIVADO + PÚBLICO habilitados. O público é necessário para a
  # esteira de deploy (GitHub Actions, fora da VPC) executar o
  # `aws eks update-kubeconfig` e aplicar os manifests com `kubectl`. Em setups
  # avançados isso seria feito via bastion/VPC peering — aqui o público é o
  # caminho padrão.
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Mapeia o criador do cluster (a role/usuário que executou o terraform apply)
  # como admin do cluster — permite o console e o CLI acessarem os recursos K8s.
  enable_cluster_creator_admin_permissions = true

  access_entries = {
    # Conta root: mesmo não sendo "criadora", precisa de access entry para o
    # console mostrar Pods/Workloads. (Uso pontual de diagnóstico.)
    root = {
      kubernetes_groups = []
      principal_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  eks_managed_node_groups = {
    workers = {
      name         = "workers"
      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      instance_types = var.node_instance_types

      capacity_type = "ON_DEMAND"

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 30
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }
    }
  }

  tags = { Environment = var.environment }
}

# ---------------------------------------------------------------------------
# Namespaces — criados pelo Terraform e usados pelos add-ons em k8s/addons/.
# ---------------------------------------------------------------------------

# Namespace de negócio — onde a API principal é aplicada pelo pipeline do
# repositório da aplicação (os manifests não vivem mais neste repo).
resource "kubernetes_namespace_v1" "mecanicadm" {
  metadata {
    name = "mecanicadm"
    labels = {
      environment = var.environment
    }
  }

  depends_on = [module.eks]
}

# Namespace do Kong Ingress Controller / API Gateway.
resource "kubernetes_namespace_v1" "kong" {
  metadata {
    name = "kong"
    labels = {
      environment = var.environment
    }
  }

  depends_on = [module.eks]
}

# Namespace do ExternalDNS.
resource "kubernetes_namespace_v1" "external_dns" {
  metadata {
    name = "external-dns"
    labels = {
      environment = var.environment
    }
  }

  depends_on = [module.eks]
}

# Namespace da stack de observabilidade (OTel Collector, kube-state-metrics e
# Prometheus Agent). Os manifests ficam em k8s/addons/observability/.
resource "kubernetes_namespace_v1" "observability" {
  count = var.observability_enabled ? 1 : 0

  metadata {
    name = "observability"
    labels = {
      environment = var.environment
    }
  }

  depends_on = [module.eks]
}

# ---------------------------------------------------------------------------
# Add-ons de terceiros.
#
# A instalação é feita com manifests Kubernetes puros, versionados em
# k8s/addons/, aplicados pela pipeline com `kubectl apply`:
#   - k8s/addons/kong/kong.yaml                          (Kong Gateway + Ingress Controller)
#   - k8s/addons/metrics-server/components.yaml          (metrics-server, usado pelo HPA)
#   - k8s/addons/external-dns/...                        (ExternalDNS + Route 53)
#   - k8s/addons/observability/kube-state-metrics.yaml   (estado dos objetos do cluster)
#   - k8s/addons/observability/prometheus-agent.yaml     (remote_write para o New Relic)
#   - k8s/addons/observability/otel-collector.yaml       (métricas de node/pod + eventos)
#
# O Terraform permanece responsável pela infraestrutura AWS, pelos namespaces e
# pelos ServiceAccounts com IRSA (anotações eks.amazonaws.com/role-arn), que são
# pré-requisitos dos manifests acima.
#
# External Secrets Operator não é utilizado neste projeto: os secrets da
# aplicação são gerenciados pelo pipeline do repositório da app.
# ---------------------------------------------------------------------------

# API Gateway (Kong) — expõe a API via LoadBalancer (NLB), cujo hostname é
# registrado automaticamente no Route 53 pelo ExternalDNS.

# ServiceAccount do Kong (criado no manifest upstream como kong-serviceaccount).
resource "kubernetes_service_account_v1" "kong" {
  metadata {
    name      = "kong-serviceaccount"
    namespace = kubernetes_namespace_v1.kong.metadata[0].name
    labels = {
      environment = var.environment
    }
  }

  depends_on = [kubernetes_namespace_v1.kong]
}

# Observabilidade — o APM da aplicação continua sendo feito pelo New Relic via
# Java agent (configurado no repositório da app). A visão de cluster, que antes
# vinha do nri-bundle (Helm), é reconstruída sem Helm por três peças em
# k8s/addons/observability/:
#   - kube-state-metrics  : estado dos objetos (Deployments, Pods, HPA, Nodes)
#   - prometheus-agent    : scrape do kube-state-metrics -> remote_write New Relic
#   - otel-collector      : kubeletstats + k8s_cluster + k8s_events -> OTLP New Relic
# Todos autenticam com a license key do secret "newrelic-license-key", criado
# pela pipeline a partir do GitHub secret NEW_RELIC_LICENSE_KEY.

# metrics-server — necessário para o HorizontalPodAutoscaler (hpa.yaml) escalar
# por CPU/memória. Instalado pelo manifest k8s/addons/metrics-server.

# Identidade da conta AWS — usada nas políticas IAM e nos endpoints da VPC.
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# External DNS — mantém o Route 53 sincronizado com os LoadBalancers do
# cluster. Observa Services tipo LoadBalancer (ex.: proxy do Kong) e cria/atualiza
# sozinho o registro api.<domínio> para o NLB atual.
# Requer a zona já criada pelo workflow "DNS - Hosted Zone Route 53".
# ---------------------------------------------------------------------------
data "aws_route53_zone" "public" {
  count = var.external_dns_enabled ? 1 : 0

  name         = var.route53_zone_name
  private_zone = false
}

resource "aws_iam_role" "external_dns" {
  count = var.external_dns_enabled ? 1 : 0

  name = "mecanicadm-${var.environment}-external-dns"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:external-dns:external-dns"
          "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "external_dns_route53" {
  count = var.external_dns_enabled ? 1 : 0

  name = "route53-records"
  role = aws_iam_role.external_dns[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = "arn:aws:route53:::hostedzone/${data.aws_route53_zone.public[0].zone_id}"
      },
      {
        Effect   = "Allow"
        Action   = ["route53:GetChange"]
        Resource = "arn:aws:route53:::change/*"
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones", "route53:ListHostedZonesByName", "route53:ListResourceRecordSets", "route53:GetHostedZone"]
        Resource = "*"
      }
    ]
  })
}

# ServiceAccount do ExternalDNS — gerenciado pelo Terraform para receber a
# anotação IRSA (o manifest em k8s/addons/external-dns não cria o SA).
resource "kubernetes_service_account_v1" "external_dns" {
  count = var.external_dns_enabled ? 1 : 0

  metadata {
    name      = "external-dns"
    namespace = kubernetes_namespace_v1.external_dns.metadata[0].name
    labels = {
      environment = var.environment
    }
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns[0].arn
    }
  }

  depends_on = [kubernetes_namespace_v1.external_dns]
}

# ---------------------------------------------------------------------------
# Parâmetros SSM compartilhados entre os repos.
# ---------------------------------------------------------------------------
resource "aws_ssm_parameter" "vpc_id" {
  name  = "/mecanicadm/${var.environment}/vpc_id"
  type  = "String"
  value = module.vpc.vpc_id
}

resource "aws_ssm_parameter" "eks_node_sg_id" {
  name  = "/mecanicadm/${var.environment}/eks_node_sg_id"
  type  = "String"
  value = module.eks.node_security_group_id
}
