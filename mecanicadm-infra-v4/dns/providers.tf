# Estado separado do módulo raiz: a zona NÃO pode morrer junto com o
# ambiente (os ciclos de destroy/recreate dependem dela para o DNS se
# reconstituir sozinho via ExternalDNS).
terraform {
  required_version = ">= 1.5.0"

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
