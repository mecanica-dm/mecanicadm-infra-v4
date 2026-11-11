output "zone_id" {
  description = "ID da hosted zone (referência para comandos CLI e para a policy do ExternalDNS)."
  value       = aws_route53_zone.public.zone_id
}

output "name_servers" {
  description = "Servidores DNS da AWS — estes 4 endereços devem ser cadastrados no painel do Registro.br (delegação, uma vez só)."
  value       = aws_route53_zone.public.name_servers
}
