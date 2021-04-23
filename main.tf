terraform {
  required_providers {
    vault = {
      source = "hashicorp/vault"
      version = ">=2.19.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=2.46.0"
    }
  }
}

provider "vault" {}

data "vault_generic_secret" "service_principle" {
  path = "azure/service_test"
}

provider "azurerm" {
  features {}
  subscription_id = data.vault_generic_secret.service_principle.data["subscription"]
  client_id       = data.vault_generic_secret.service_principle.data["appId"]
  client_secret   = data.vault_generic_secret.service_principle.data["password"]
  tenant_id       = data.vault_generic_secret.service_principle.data["tenant"]
}

resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}_rg" # resource group name
  location = var.rg_region # Azure region
}

# Create VNET
resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}_vnet" 
  location            = var.rg_region  # Azure region
  resource_group_name = azurerm_resource_group.main.name # resource group name
  address_space       = [ "10.0.0.0/16" ]
}

# Create a subnet
resource "azurerm_subnet" "netapp" {
  name                 = "${var.prefix}_subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
  delegation {
    name = "${var.prefix}_delegation"
    service_delegation {
      name = "Microsoft.Netapp/volumes"
    }
  }
}

# # Create a netapp account
# resource "azurerm_netapp_account" "main" {
#   name                = "${var.prefix}_account"
#   location            = azurerm_resource_group.main.location
#   resource_group_name = azurerm_resource_group.main.name
# }

# # Create a netapp pool
# resource "azurerm_netapp_pool" "main" {
#   name                = "${var.prefix}_pool"
#   location            = azurerm_resource_group.main.location
#   resource_group_name = azurerm_resource_group.main.name
#   account_name        = azurerm_netapp_account.main.name
#   service_level       = "Premium"
#   size_in_tb          = 4
# }

# # # Create a netapp volumes
# resource "azurerm_netapp_volume" "main" {
#   name                = "${var.prefix}_volume"
#   location            = azurerm_resource_group.main.location
#   resource_group_name = azurerm_resource_group.main.name
#   account_name        = azurerm_netapp_account.main.name
#   pool_name           = azurerm_netapp_pool.main.name
#   volume_path         = "my-unique-file-path"
#   service_level       = "Premium"
#   subnet_id           = azurerm_subnet.netapp.id
#   protocols           = ["NFSv4.1"]
#   storage_quota_in_gb = 100
#   tags = {
#     "service" = "NetApp"
#   }
# }

# Create a vault for recovery services
resource "azurerm_recovery_services_vault" "main" {
  name                = "recovery-vault"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"
  tags = {
    "service" = "NetApp"
  }
}

# Create backup policy
resource "azurerm_backup_policy_file_share" "policy" {
  name                = "tfex-recovery-vault-policy"
  resource_group_name = azurerm_resource_group.main.name
  recovery_vault_name = azurerm_recovery_services_vault.main.name

  timezone = "SE Asia Standard Time"

  backup {
    frequency = "Daily"
    time      = "15:00"
  }

  retention_daily {
    count = 10
  }
}