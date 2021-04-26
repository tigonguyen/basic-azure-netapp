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
  backend "azurerm" {
    resource_group_name  = "tstate"
    storage_account_name = "tstatedevops"
    container_name       = "anfdeployment"
    key                  = "terraform.tfstate"
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

# Create a netapp account
resource "azurerm_netapp_account" "main" {
  name                = "${var.prefix}_account"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# Create a netapp pool
resource "azurerm_netapp_pool" "main" {
  name                = "${var.prefix}_pool"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_netapp_account.main.name
  service_level       = "Premium"
  size_in_tb          = 4
}

# # Create a netapp volumes
resource "azurerm_netapp_volume" "main" {
  name                = "${var.prefix}_volume"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_netapp_account.main.name
  pool_name           = azurerm_netapp_pool.main.name
  volume_path         = "my-nfs-v4-1-path"
  service_level       = "Premium"
  subnet_id           = azurerm_subnet.netapp.id
  protocols           = ["NFSv3"]
  storage_quota_in_gb = 100
}

resource "null_resource" "create_snapshot_polilcy" {
  provisioner "local-exec" {
	command = <<EOT
	APP_ID=${data.vault_generic_secret.service_principle.data["appId"]}
	PASSWORD=${data.vault_generic_secret.service_principle.data["password"]}
	TENANT_ID=${data.vault_generic_secret.service_principle.data["tenant"]}

  # Install Azure CLI
  sudo apt-get update
  sudo apt-get install ca-certificates curl apt-transport-https lsb-release gnupg
  curl -sL https://packages.microsoft.com/keys/microsoft.asc |
    gpg --dearmor |
    sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
  AZ_REPO=$(lsb_release -cs)
  echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" |
    sudo tee /etc/apt/sources.list.d/azure-cli.list
  sudo apt-get update
  sudo apt-get install azure-cli

  az login --service-principal --username $APP_ID --password $PASSWORD --tenant $TENANT_ID
  az netappfiles snapshot policy create --snapshot-policy-name "${var.prefix}_snap_policy" --account-name "${azurerm_netapp_account.main.name}" --location "${var.rg_region}" --resource-group "${azurerm_resource_group.main.name}" --daily-hour 14 --enabled true
	EOT
	interpreter = ["bash"]
  }
}
