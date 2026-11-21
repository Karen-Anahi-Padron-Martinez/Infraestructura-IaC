# Aprovisionamiento en Azure: red, firewall, IP pública y VM Linux para el Gestor de Proyectos.
# La configuración del servidor (Docker, despliegue, monitoreo) la hace Ansible.

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.proyecto}"
  location = var.ubicacion
  tags     = var.etiquetas
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.proyecto}"
  address_space       = ["10.20.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.etiquetas
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.20.1.0/24"]
}

# Firewall: solo HTTP es público; SSH y Grafana solo desde las redes del administrador.
# MariaDB, la API y Prometheus no tienen regla, por lo que no son accesibles desde internet.
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-${var.proyecto}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.etiquetas

  security_rule {
    name                       = "permitir-ssh-admin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.cidrs_admin
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "permitir-http-publico"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "permitir-grafana-admin"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefixes    = var.cidrs_admin
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_public_ip" "pip" {
  name                = "pip-${var.proyecto}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "${var.proyecto}-${substr(md5(azurerm_resource_group.rg.id), 0, 6)}"
  tags                = var.etiquetas
}

resource "azurerm_network_interface" "nic" {
  name                = "nic-${var.proyecto}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.etiquetas

  ip_configuration {
    name                          = "interna"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                  = "vm-${var.proyecto}"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = var.tamano_vm
  admin_username        = var.usuario_admin
  network_interface_ids = [azurerm_network_interface.nic.id]
  tags                  = var.etiquetas

  # Solo acceso por llave: sin contraseña
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.usuario_admin
    public_key = file(pathexpand(var.llave_publica_ssh))
  }

  os_disk {
    name                 = "osdisk-${var.proyecto}"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

# Apagado automático diario para no consumir crédito si la VM se queda encendida
resource "azurerm_dev_test_global_vm_shutdown_schedule" "apagado" {
  virtual_machine_id    = azurerm_linux_virtual_machine.vm.id
  location              = azurerm_resource_group.rg.location
  enabled               = true
  daily_recurrence_time = var.hora_apagado
  timezone              = "Central Standard Time (Mexico)"
  tags                  = var.etiquetas

  notification_settings {
    enabled = false
  }
}

# Inventario para Ansible generado a partir de los recursos creados (puente Terraform -> Ansible)
resource "local_file" "inventario_ansible" {
  filename        = "${path.module}/../ansible/inventario.ini"
  file_permission = "0644"
  content = templatefile("${path.module}/plantillas/inventario.ini.tftpl", {
    ip            = azurerm_public_ip.pip.ip_address
    usuario       = var.usuario_admin
    llave_privada = pathexpand(var.llave_privada_ssh)
    fqdn          = azurerm_public_ip.pip.fqdn
  })
}
