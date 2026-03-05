terraform {
  required_version = ">=1.1.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.46.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.58.0"
    }
  }
}

# Provider Azure Resource Manager
provider "azurerm" {
  features {}
}

# Provider Databricks (utilise seulement si create_databricks = true)
# Si desactive, host et token peuvent rester vides
provider "databricks" {
  host  = var.databricks_host != "" ? var.databricks_host : "https://placeholder.azuredatabricks.net"
  token = var.databricks_token != "" ? var.databricks_token : "placeholder"
}
