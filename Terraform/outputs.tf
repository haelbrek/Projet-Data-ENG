output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "blob_storage_account_name" {
  value = azurerm_storage_account.blob.name
}

output "blob_containers" {
  value = [for c in azurerm_storage_container.landing : c.name]
}

output "datalake_storage_account_name" {
  value = azurerm_storage_account.datalake.name
}

output "datalake_filesystems" {
  value = [for fs in azurerm_storage_data_lake_gen2_filesystem.zones : fs.name]
}

output "blob_primary_connection_string" {
  value       = azurerm_storage_account.blob.primary_connection_string
  description = "Ã€ utiliser pour Ã©crire localement dans les conteneurs de landing"
  sensitive   = true
}

output "datalake_dfs_endpoint" {
  value       = azurerm_storage_account.datalake.primary_dfs_endpoint
  description = "Endpoint DFS pour les opÃ©rations ADLS Gen2"
}

output "key_vault_name" {
  value       = azurerm_key_vault.kv.name
  description = "Nom du Key Vault"
}

output "key_vault_uri" {
  value       = azurerm_key_vault.kv.vault_uri
  description = "URI du Key Vault (https://<nom>.vault.azure.net)"
}

output "data_factory_name" {
  value       = azurerm_data_factory.adf.name
  description = "Nom de l'Azure Data Factory"
}

output "data_factory_identity_principal_id" {
  value       = azurerm_data_factory.adf.identity[0].principal_id
  description = "Object ID de l'identitÃ© managÃ©e de Data Factory"
}

output "upload_files_enabled" {
  value       = var.upload_files_enabled
  description = "Upload local -> Blob activÃ©"
}

output "upload_file_count" {
  value       = length(local.upload_files)
  description = "Nombre de fichiers dÃ©tectÃ©s dans upload_source_dir"
}
output "virtual_network_name" {
  value       = azurerm_virtual_network.data.name
  description = "Nom du reseau virtuel cree pour la plateforme data"
}

output "databricks_private_subnet_id" {
  value       = azurerm_subnet.databricks_private.id
  description = "ID du subnet prive a utiliser pour les workers Databricks"
}

output "databricks_public_subnet_id" {
  value       = azurerm_subnet.databricks_public.id
  description = "ID du subnet public a utiliser pour le front-end Databricks"
}
output "databricks_workspace_url" {
  value       = azurerm_databricks_workspace.dbw.workspace_url
  description = "URL du workspace Databricks"
}

