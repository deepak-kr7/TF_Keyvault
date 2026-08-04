# Variable declarations

variable "location" {
  default = "centralindia"
}

variable "resource_group_name" {
  default = "rg_demo_dev"
}

variable "vm_admin_username" {
  default = "azureuser"
}

variable "key_vault_name" {
  default = "kvrgdemo"
}

variable "admin_password_secret_name" {
  default = "vm-admin-password"
}

# Provider configuration

terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource Group

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# Current Client Information

data "azurerm_client_config" "current" {}

# Key Vault

resource "azurerm_key_vault" "kv" {
  name                       = var.key_vault_name
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = true
  soft_delete_retention_days = 7

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get",
      "Set",
      "List",
      "Delete",
      "Recover",
      "Purge"
    ]
  }
}

# Random Password Generation

resource "random_password" "vm_password" {
  length           = 20
  special          = true
  override_special = "!@#$%^*()-_=+"
}

# Store Password In Key Vault

resource "azurerm_key_vault_secret" "vm_secret" {
  name         = var.admin_password_secret_name
  value        = random_password.vm_password.result
  key_vault_id = azurerm_key_vault.kv.id
}

# Read Secret from Key Vault

data "azurerm_key_vault_secret" "vm_password" {
  name         = azurerm_key_vault_secret.vm_secret.name
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_key_vault_secret.vm_secret]
}

# Virtual Network

resource "azurerm_virtual_network" "vnet" {
  name                = "demo_vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.10.0.0/16"]
}

# Subnet

resource "azurerm_subnet" "subnet" {
  name                 = "vm-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.1.0/24"]
}

# Bastion Subnet

resource "azurerm_subnet" "bastion_subnet" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.2.0/24"]
}

# NIC

resource "azurerm_network_interface" "Nic" {
  name                = "VM-Nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# VM

resource "azurerm_linux_virtual_machine" "vm" {
  name                            = "linux-vm01"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = "Standard_D2s_v3"
  admin_username                  = var.vm_admin_username
  admin_password                  = data.azurerm_key_vault_secret.vm_password.value
  network_interface_ids           = [azurerm_network_interface.Nic.id]
  disable_password_authentication = false

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}
