# VM de integración continua: Jenkins + SonarQube (+ PostgreSQL) separados de producción.
# Comparte la VNet con la aplicación: Jenkins despliega a vm-gestor por la red privada.
# Jenkins (8080) y SonarQube (9000) solo se abren a cidrs_admin (reglas en el NSG de main.tf).

resource "azurerm_public_ip" "pip_ci" {
  name                = "pip-${var.proyecto}-ci"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "${var.proyecto}-ci-${substr(md5(azurerm_resource_group.rg.id), 0, 6)}"
  tags                = var.etiquetas
}

resource "azurerm_network_interface" "nic_ci" {
  name                = "nic-${var.proyecto}-ci"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.etiquetas

  ip_configuration {
    name                          = "interna"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.ip_privada_ci
    public_ip_address_id          = azurerm_public_ip.pip_ci.id
  }
}

resource "azurerm_linux_virtual_machine" "ci" {
  name                  = "vm-${var.proyecto}-ci"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = var.tamano_vm_ci
  admin_username        = var.usuario_admin
  network_interface_ids = [azurerm_network_interface.nic_ci.id]
  tags                  = merge(var.etiquetas, { rol = "ci" })

  disable_password_authentication = true

  admin_ssh_key {
    username   = var.usuario_admin
    public_key = file(pathexpand(var.llave_publica_ssh))
  }

  os_disk {
    name                 = "osdisk-${var.proyecto}-ci"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = var.disco_ci_gb # repositorio Maven, imágenes Docker e índices de SonarQube
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "apagado_ci" {
  virtual_machine_id    = azurerm_linux_virtual_machine.ci.id
  location              = azurerm_resource_group.rg.location
  enabled               = true
  daily_recurrence_time = var.hora_apagado
  timezone              = "Central Standard Time (Mexico)"
  tags                  = var.etiquetas

  notification_settings {
    enabled = false
  }
}
