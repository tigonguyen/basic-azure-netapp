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

# Create NetApp snapshot policy via Powershell
resource "null_resource" "create_snapshot_polilcy" {
  provisioner "local-exec" {
	command = <<EOT
	$spApplicationId = "${data.vault_generic_secret.service_principle.data["appId"]}"
	$spSecret = "${data.vault_generic_secret.service_principle.data["password"]}"
	$secspSecret = ConvertTo-SecureString -String $spSecret -AsPlainText -Force
	$tenantId = "${data.vault_generic_secret.service_principle.data["tenant"]}"
	$pscredential = New-Object -TypeName System.Management.Automation.PSCredential($spApplicationId,$secspSecret)
	Connect-AzAccount -ServicePrincipal -Credential $pscredential -Tenant $tenantId
  $hourlySchedule = @{        
      Minute = 30
      SnapshotsToKeep = 6
    }
    $dailySchedule = @{
      Hour = 1
      Minute = 30
      SnapshotsToKeep = 6
    }
    $weeklySchedule = @{
      Minute = 30    
      Hour = 1		        
      Day = "Sunday,Monday"
      SnapshotsToKeep = 6
    }
    $monthlySchedule = @{
      Minute = 30    
      Hour = 1        
      DaysOfMonth = "2,11,21"
      SnapshotsToKeep = 6
    }
	New-AzNetAppFilesSnapshotPolicy -ResourceGroupName "${azurerm_resource_group.main.name}" -Location "${var.rg_region}" -AccountName "${azurerm_netapp_account.main.name}" -Name "${var.prefix}_snap_policy" -Enabled -HourlySchedule $hourlySchedule -DailySchedule $dailySchedule -WeeklySchedule $weeklySchedule -MonthlySchedule $monthlySchedule
	EOT
	interpreter = ["PowerShell", "-Command"]
  }
}