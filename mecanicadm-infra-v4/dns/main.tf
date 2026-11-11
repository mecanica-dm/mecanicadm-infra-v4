# ---------------------------------------------------------------------------
# Hosted Zone pública — uma vez só, nunca destruída pelos botões vermelhos.
#
# A delegação dos nameservers no Registro.br aponta para ESTA zona. Se ela
# fosse recriada a cada ciclo, os nameservers mudariam e a delegação teria
# que ser refeita manualmente. Por isso vive em state próprio (esta pasta),
# fora do alcance do pipeline de destroy.
#
# Os registros dentro da zona (api.mecanicadm.com.br etc.) NÃO são geridos
# aqui: quem cria/atualiza automaticamente é o ExternalDNS rodando dentro
# do cluster, apontando para o LoadBalancer atual do Kong.
# ---------------------------------------------------------------------------
resource "aws_route53_zone" "public" {
  name = var.domain_name

  # Permite `terraform destroy` mesmo com registros dentro da zona
  # (o ExternalDNS cria registros dinamicamente ao longo do tempo;
  # sem isso, a deleção falharia até apagar todos um a um).
  force_destroy = true

  tags = {
    Name      = var.domain_name
    ManagedBy = "terraform"
  }
}
