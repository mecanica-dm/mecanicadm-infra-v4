# Mecânica DM - Infraestrutura Kubernetes (Terraform + Kubernetes)

![Kubernetes](https://img.shields.io/badge/K8s-1.32-blue?logo=kubernetes)
![Terraform](https://img.shields.io/badge/Terraform-1.8.0-purple?logo=terraform)
![AWS](https://img.shields.io/badge/AWS-EKS-orange?logo=amazon-aws)

Repositório de infraestrutura que provisiona e gerencia o cluster **Amazon EKS** e todos os add-ons necessários para rodar a API **Mecânica DM** em produção — incluindo API Gateway (Kong), autoscaling (HPA), secrets management (Kubernetes Secrets), DNS (Route 53 + ExternalDNS) e observabilidade (New Relic APM).

Na **Fase 04** do 15SOAT, este repositório abriga toda a camada principal de infraestrutura como código (IaC).

