variable "resource_group_name" {
  type        = string
  description = "Nom du groupe de ressources Azure"
}

variable "resource_group_location" {
  type        = string
  description = "RÃƒÂ©gion Azure oÃƒÂ¹ le groupe de ressources est crÃƒÂ©ÃƒÂ©"
}

variable "blob_storage_account_name" {
  type        = string
  description = "Nom du compte de stockage Blob (3-24, minuscules et chiffres)"
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.blob_storage_account_name))
    error_message = "Le nom du Storage Account doit ÃƒÂªtre 3-24 caractÃƒÂ¨res alphanumÃƒÂ©riques minuscules."
  }
}

variable "datalake_storage_account_name" {
  type        = string
  description = "Nom du compte ADLS Gen2 (3-24, minuscules et chiffres)"
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.datalake_storage_account_name))
    error_message = "Le nom du Storage Account doit ÃƒÂªtre 3-24 caractÃƒÂ¨res alphanumÃƒÂ©riques minuscules."
  }
}

variable "blob_containers" {
  type        = list(string)
  description = "Liste des conteneurs Blob pour le compte 'landing'"
  default     = ["landing", "archive"]
}

variable "datalake_filesystems" {
  type        = list(string)
  description = "Liste des filesystems ADLS Gen2 (zones)"
  default     = ["raw", "staging", "curated"]
}

variable "vnet_name" {
  type        = string
  description = "Nom du reseau virtuel pour la plateforme data"
  default     = "vnet-dataeng"
}

variable "vnet_address_space" {
  type        = string
  description = "CIDR du reseau virtuel"
  default     = "10.20.0.0/16"
}

variable "databricks_private_subnet_name" {
  type        = string
  description = "Nom du subnet prive destine aux workers Databricks"
  default     = "snet-databricks-private"
}

variable "databricks_private_subnet_prefix" {
  type        = string
  description = "CIDR du subnet prive Databricks"
  default     = "10.20.1.0/24"
}

variable "databricks_public_subnet_name" {
  type        = string
  description = "Nom du subnet public (front-end) Databricks"
  default     = "snet-databricks-public"
}

variable "databricks_public_subnet_prefix" {
  type        = string
  description = "CIDR du subnet public Databricks"
  default     = "10.20.2.0/24"
}

variable "databricks_workspace_name" {
  type        = string
  description = "Nom du workspace Azure Databricks"
}
# Key Vault
variable "key_vault_name" {
  type        = string
  description = "Nom du Key Vault (3-24, lettres/chiffres et tirets, commence/finit par alphanum)"
  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{1,22}[a-zA-Z0-9])$", var.key_vault_name))
    error_message = "Le nom du Key Vault doit faire 3-24 caractÃƒÂ¨res, alphanumÃƒÂ©riques et tirets, sans commencer/finir par un tiret."
  }
}

variable "kv_additional_reader_object_ids" {
  type        = list(string)
  description = "(Optionnel) Liste d'Object IDs (Azure AD) ÃƒÂ  autoriser en lecture de secrets (rÃƒÂ´le Secrets User)"
  default     = []
}

# Data Factory
variable "data_factory_name" {
  type        = string
  description = "Nom de l'Azure Data Factory"
}

# Upload local -> Blob via Terraform (optionnel)
variable "upload_files_enabled" {
  type        = bool
  description = "Activer l'upload de fichiers locaux vers le conteneur Blob"
  default     = false
}

variable "upload_source_dir" {
  type        = string
  description = "RÃƒÂ©pertoire local (relatif ÃƒÂ  Terraform/) contenant les fichiers ÃƒÂ  uploader"
  default     = "../uploads/landing"
}

variable "upload_container_name" {
  type        = string
  description = "Conteneur cible pour l'upload (par dÃƒÂ©faut: landing)"
  default     = "landing"
}


