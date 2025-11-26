resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.resource_group_location
}

############################################
# Stockage : Data Lake (ADLS Gen2)
############################################

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

# Conteneur blob existant (ex: "raw") référencé en data pour éviter les conflits d'import
data "azurerm_storage_container" "upload" {
  name                 = var.upload_datalake_filesystem
  storage_account_name = azurerm_storage_account.datalake.name
}

############################################
# Upload local -> Data Lake (optionnel)
############################################

locals {
  upload_files = var.upload_files_enabled ? [
    for file in fileset("${path.module}/${var.upload_source_dir}", "**")
    : file
    if length(regexall("(?i)\\.(csv|xlsx)$", file)) > 0
  ] : []
  sql_firewall_rules = var.sql_allow_azure_services ? concat([
    {
      name     = "Allow_Azure_Services"
      start_ip = "0.0.0.0"
      end_ip   = "0.0.0.0"
    }
  ], var.sql_firewall_rules) : var.sql_firewall_rules
}

resource "azurerm_storage_blob" "uploaded" {
  for_each               = toset(local.upload_files)
  name                   = each.value
  storage_account_name   = azurerm_storage_account.datalake.name
  storage_container_name = data.azurerm_storage_container.upload.name
  type                   = "Block"
  source                 = "${path.module}/${var.upload_source_dir}/${each.value}"
  content_md5            = filemd5("${path.module}/${var.upload_source_dir}/${each.value}")
}

resource "null_resource" "run_fetch_communes" {
  count = var.run_fetch_communes ? 1 : 0

  triggers = {
    script_hash = filesha256("${path.module}/../ingestion/API/fetch_communes.py")
    args_hash   = md5(var.fetch_communes_extra_args)
    filesystem  = var.upload_datalake_filesystem
  }

  provisioner "local-exec" {
    command     = "python ../ingestion/API/fetch_communes.py --container ${var.upload_datalake_filesystem}${var.fetch_communes_extra_args != "" ? " ${var.fetch_communes_extra_args}" : ""}"
    working_dir = path.module
    environment = {
      AZURE_STORAGE_CONNECTION_STRING = azurerm_storage_account.datalake.primary_connection_string
    }
  }

  depends_on = [
    azurerm_storage_data_lake_gen2_filesystem.zones
  ]
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

  enable_rbac_authorization  = false
  purge_protection_enabled   = true
  soft_delete_retention_days = 90

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge", "Recover"
    ]
  }

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

resource "azurerm_key_vault_access_policy" "kv_adf_reader" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_data_factory.adf.identity[0].principal_id

  secret_permissions = ["Get", "List"]
  depends_on         = [azurerm_data_factory.adf]
}

############################################
# Azure SQL Database
############################################

resource "azurerm_mssql_server" "sql" {
  name                = var.sql_server_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  version             = "12.0"

  administrator_login          = var.sql_admin_login
  administrator_login_password = var.sql_admin_password
  minimum_tls_version          = "1.2"
  public_network_access_enabled = true

  tags = {
    env     = "demo"
    purpose = "sql"
  }
}

resource "azurerm_mssql_database" "sql" {
  name      = var.sql_database_name
  server_id = azurerm_mssql_server.sql.id
  sku_name  = var.sql_database_sku_name
  collation = var.sql_database_collation

  tags = {
    env     = "demo"
    purpose = "sqldb"
  }
}

locals {
  sql_firewall_rule_map = { for rule in local.sql_firewall_rules : rule.name => rule }
}

resource "azurerm_mssql_firewall_rule" "sql" {
  for_each = local.sql_firewall_rule_map

  name                = each.value.name
  server_id           = azurerm_mssql_server.sql.id
  start_ip_address    = each.value.start_ip
  end_ip_address      = each.value.end_ip
}


