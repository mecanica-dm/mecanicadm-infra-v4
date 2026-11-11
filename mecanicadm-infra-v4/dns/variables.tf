variable "region" {
  description = "Região AWS onde a zona Route 53 será criada."
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Domínio público registrado no Registro.br que será servido pelo Route 53."
  type        = string
  default     = "mecanicadm.com.br"
}
