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

output "url_jenkins" {
  description = "URL de Jenkins en la VM de CI (solo accesible desde cidrs_admin)."
  value       = "http://${azurerm_public_ip.pip_ci.fqdn}:8080"
}

output "url_sonarqube" {
  description = "URL de SonarQube en la VM de CI (solo accesible desde cidrs_admin)."
  value       = "http://${azurerm_public_ip.pip_ci.fqdn}:9000"
}

output "ssh_ci" {
  description = "Comando para conectarse por SSH a la VM de CI."
  value       = "ssh -i ${var.llave_privada_ssh} ${var.usuario_admin}@${azurerm_public_ip.pip_ci.ip_address}"
}
