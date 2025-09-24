resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.resource_group_location
}

############################################
# Reseau virtuel pour Databricks
############################################

resource "azurerm_virtual_network" "data" {
  name                = var.vnet_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [var.vnet_address_space]

  tags = {
    env     = "demo"
    purpose = "network"
  }
}

resource "azurerm_subnet" "databricks_private" {
  name                 = var.databricks_private_subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.data.name
  address_prefixes     = [var.databricks_private_subnet_prefix]
  service_endpoints    = ["Microsoft.Storage", "Microsoft.Sql"]

  delegation {
    name = "databricks_private"

    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action"
      ]
    }
  }
}

resource "azurerm_subnet" "databricks_public" {
  name                 = var.databricks_public_subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.data.name
  address_prefixes     = [var.databricks_public_subnet_prefix]
  service_endpoints    = ["Microsoft.Storage", "Microsoft.Sql"]

  delegation {
    name = "databricks_public"

    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action"
      ]
    }
  }
}

resource "azurerm_network_security_group" "databricks_private" {
  name                = "nsg-${var.databricks_private_subnet_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow-vnet-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "allow-all-outbound"
    priority                   = 101
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    env     = "demo"
    purpose = "databricks"
  }
}

resource "azurerm_network_security_group" "databricks_public" {
  name                = "nsg-${var.databricks_public_subnet_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow-vnet-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "allow-all-outbound"
    priority                   = 101
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    env     = "demo"
    purpose = "databricks"
  }
}

resource "azurerm_subnet_network_security_group_association" "databricks_private" {
  subnet_id                 = azurerm_subnet.databricks_private.id
  network_security_group_id = azurerm_network_security_group.databricks_private.id
}

resource "azurerm_subnet_network_security_group_association" "databricks_public" {
  subnet_id                 = azurerm_subnet.databricks_public.id
  network_security_group_id = azurerm_network_security_group.databricks_public.id
}

resource "azurerm_databricks_workspace" "dbw" {
  name                = var.databricks_workspace_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "standard"

  custom_parameters {
    virtual_network_id                                   = azurerm_virtual_network.data.id
    public_subnet_name                                   = azurerm_subnet.databricks_public.name
    private_subnet_name                                  = azurerm_subnet.databricks_private.name
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.databricks_public.id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.databricks_private.id
  }

  tags = {
    env     = "demo"
    purpose = "databricks"
  }
}

############################################
# Stockage : Blob (landing) et ADLS Gen2
############################################

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
  name                   = each.value
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
