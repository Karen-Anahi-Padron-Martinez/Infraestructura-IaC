output "ip_publica" {
  description = "IP pública de la VM."
  value       = azurerm_public_ip.pip.ip_address
}

output "fqdn" {
  description = "Nombre DNS público asignado por Azure."
  value       = azurerm_public_ip.pip.fqdn
}

output "url_aplicacion" {
  description = "URL del cliente web (frontend)."
  value       = "http://${azurerm_public_ip.pip.fqdn}"
}

output "url_grafana" {
  description = "URL de Grafana (solo accesible desde cidrs_admin)."
  value       = "http://${azurerm_public_ip.pip.fqdn}:3000"
}

output "ssh" {
  description = "Comando para conectarse por SSH."
  value       = "ssh -i ${var.llave_privada_ssh} ${var.usuario_admin}@${azurerm_public_ip.pip.ip_address}"
}
