# Estado separado do módulo raiz: a zona NÃO pode morrer junto com o
# ambiente (os ciclos de destroy/recreate dependem dela para o DNS se
# reconstituir sozinho via ExternalDNS).
terraform {
  # >= 1.10 para suportar state locking nativo do backend S3 (use_lockfile).
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.region
}
