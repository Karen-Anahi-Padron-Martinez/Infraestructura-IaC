variable "subscription_id" {
  description = "ID de la suscripción de Azure (Azure for Students). Va en terraform.tfvars, que no se versiona."
  type        = string
  default     = null
}

variable "proyecto" {
  description = "Prefijo para nombrar los recursos."
  type        = string
  default     = "gestor"
}

variable "ubicacion" {
  description = "Región de Azure permitida por la política de la suscripción."
  type        = string
  default     = "eastus"
}

variable "tamano_vm" {
  description = "Tamaño de la VM. B2s = 2 vCPU y 4 GB, suficiente para la aplicación y el monitoreo."
  type        = string
  default     = "Standard_B2s"
}

variable "usuario_admin" {
  description = "Usuario administrador de la VM (acceso solo por llave SSH)."
  type        = string
  default     = "azureuser"
}

variable "llave_publica_ssh" {
  description = "Ruta de la llave pública SSH que se instala en la VM."
  type        = string
  default     = "~/.ssh/id_ed25519_gestor_azure.pub"
}

variable "llave_privada_ssh" {
  description = "Ruta de la llave privada (solo se escribe en el inventario local de Ansible; nunca se sube)."
  type        = string
  default     = "~/.ssh/id_ed25519_gestor_azure"
}

variable "cidrs_admin" {
  description = "Redes (CIDR) autorizadas para SSH y Grafana. Normalmente la IP pública propia con /32."
  type        = list(string)

  validation {
    condition     = length(var.cidrs_admin) > 0 && alltrue([for c in var.cidrs_admin : can(cidrhost(c, 0))])
    error_message = "Indica al menos un CIDR válido, por ejemplo [\"203.0.113.10/32\"]."
  }
}

variable "hora_apagado" {
  description = "Hora diaria de apagado automático (HHMM, hora del centro de México) para cuidar el crédito."
  type        = string
  default     = "2300"
}

variable "etiquetas" {
  description = "Etiquetas comunes para todos los recursos."
  type        = map(string)
  default = {
    proyecto   = "gestor-proyectos"
    materia    = "GPDS"
    gestionado = "terraform"
  }
}
