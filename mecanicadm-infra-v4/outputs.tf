output "cluster_name" {
  description = "Nome do cluster EKS (usado pelo aws eks update-kubeconfig)."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint do API Server do cluster (uso didático/auditoria)."
  value       = module.eks.cluster_endpoint
}

output "vpc_id" {
  description = "ID da VPC criada para o cluster."
  value       = module.vpc.vpc_id
}

output "external_dns_enabled" {
  description = "Indica se o ExternalDNS está habilitado (a pipeline usa para decidir se aplica o manifest)."
  value       = var.external_dns_enabled
}

output "external_dns_irsa_role_arn" {
  description = "ARN da IAM Role usada pelo ServiceAccount do ExternalDNS."
  value       = var.external_dns_enabled ? aws_iam_role.external_dns[0].arn : ""
}

output "observability_enabled" {
  description = "Indica se a stack de observabilidade está habilitada (a pipeline usa para decidir se aplica os manifests)."
  value       = var.observability_enabled
}
