variable "region" {
  description = "Região AWS onde o cluster será criado."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente (apenas produção por orientação do projeto)."
  type        = string
  default     = "prod"
  validation {
    condition     = var.environment == "prod"
    error_message = "Apenas o ambiente de produção (prod) é suportado."
  }
}

variable "cluster_name" {
  description = "Nome do cluster EKS (ex.: mecanicadm-prod)."
  type        = string
  default     = "mecanicadm-prod"
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC do cluster (ex.: 10.0.0.0/16)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "cluster_version" {
  description = "Versão do Kubernetes gerenciada pelo EKS."
  type        = string
  default     = "1.32"
}

variable "node_instance_types" {
  description = "Tipos de instância dos worker nodes (adequados à carga de produção)."
  type        = list(string)
  default     = ["t3.small"]
}

variable "node_desired_size" {
  description = "Número desejado de worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Mínimo de worker nodes (escala automática)."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Máximo de worker nodes (escala automática)."
  type        = number
  default     = 2
}

variable "route53_zone_name" {
  description = "Domínio da hosted zone Route 53 criada pela pasta dns/ (usado pelo ExternalDNS)."
  type        = string
  default     = "mecanicadm.com.br"
}

variable "external_dns_enabled" {
  description = "Habilita o ExternalDNS (requer a zona já criada pelo workflow DNS - Hosted Zone)."
  type        = bool
  default     = true
}

variable "observability_enabled" {
  description = "Habilita a stack de observabilidade no namespace observability (OTel Collector + kube-state-metrics + Prometheus Agent). Requer o secret NEW_RELIC_LICENSE_KEY na pipeline."
  type        = bool
  default     = true
}
