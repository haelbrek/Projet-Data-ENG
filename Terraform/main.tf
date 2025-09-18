resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.resource_group_location
}

############################################
# Stockage : Blob (landing) et ADLS Gen2   
############################################



# Compte de stockage Blob pour la zone "landing" (sans HNS)
resource "azurerm_storage_account" "blob" {
  name                      = var.blob_storage_account_name
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = azurerm_resource_group.rg.location
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  min_tls_version           = "TLS1_2"
  enable_https_traffic_only = true
  tags = {
    env     = "demo"
    purpose = "landing"
  }
}

resource "azurerm_storage_container" "landing" {
  for_each              = toset(var.blob_containers)
  name                  = each.value
  storage_account_name  = azurerm_storage_account.blob.name
  container_access_type = "private"
}

# Compte de stockage ADLS Gen2 pour le Data Lake (HNS activé)
resource "azurerm_storage_account" "datalake" {
  name                      = var.datalake_storage_account_name
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = azurerm_resource_group.rg.location
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  min_tls_version           = "TLS1_2"
  enable_https_traffic_only = true
  is_hns_enabled            = true
  tags = {
    env     = "demo"
    purpose = "datalake"
  }
}

resource "azurerm_storage_data_lake_gen2_filesystem" "zones" {
  for_each           = toset(var.datalake_filesystems)
  name               = each.value
  storage_account_id = azurerm_storage_account.datalake.id
}

############################################
# Upload local -> Blob (optionnel)
############################################

locals {
  upload_files = var.upload_files_enabled ? [
    for file in fileset("${path.module}/${var.upload_source_dir}", "**")
    : file
    if length(regexall("(?i)\\.csv$", file)) > 0
  ] : []
}

resource "azurerm_storage_blob" "uploaded" {
  for_each               = toset(local.upload_files)
  name                   = each.value # préserve la structure de sous-dossiers
  storage_account_name   = azurerm_storage_account.blob.name
  storage_container_name = azurerm_storage_container.landing[var.upload_container_name].name
  type                   = "Block"
  source                 = "${path.module}/${var.upload_source_dir}/${each.value}"
  content_md5            = filemd5("${path.module}/${var.upload_source_dir}/${each.value}")
}

############################################
# Key Vault (Access Policies)
############################################

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                = var.key_vault_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Modèle Access Policies (RBAC désactivé)
  enable_rbac_authorization = false

  # Sécurité/rétention
  purge_protection_enabled   = true
  soft_delete_retention_days = 90

  # Accès pour le déployeur courant (secrets)
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge", "Recover"
    ]
  }

  # Accès lecture secrets pour identités additionnelles (optionnel)
  dynamic "access_policy" {
    for_each = toset(var.kv_additional_reader_object_ids)
    content {
      tenant_id          = data.azurerm_client_config.current.tenant_id
      object_id          = access_policy.value
      secret_permissions = ["Get", "List"]
    }
  }

  tags = {
    env     = "demo"
    purpose = "secrets"
  }
}

############################################
# Data Factory
############################################

resource "azurerm_data_factory" "adf" {
  name                = var.data_factory_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  identity {
    type = "SystemAssigned"
  }

  tags = {
    env     = "demo"
    purpose = "orchestration"
  }
}

# Donne à l'identité managée de Data Factory un accès lecture aux secrets du Key Vault
resource "azurerm_key_vault_access_policy" "kv_adf_reader" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_data_factory.adf.identity[0].principal_id

  secret_permissions = ["Get", "List"]
  depends_on         = [azurerm_data_factory.adf]
}

