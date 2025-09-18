variable "resource_group_name" {
  type        = string
  description = "Nom du groupe de ressources Azure"
}

variable "resource_group_location" {
  type        = string
  description = "Région Azure où le groupe de ressources est créé"
}

variable "blob_storage_account_name" {
  type        = string
  description = "Nom du compte de stockage Blob (3-24, minuscules et chiffres)"
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.blob_storage_account_name))
    error_message = "Le nom du Storage Account doit être 3-24 caractères alphanumériques minuscules."
  }
}

variable "datalake_storage_account_name" {
  type        = string
  description = "Nom du compte ADLS Gen2 (3-24, minuscules et chiffres)"
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.datalake_storage_account_name))
    error_message = "Le nom du Storage Account doit être 3-24 caractères alphanumériques minuscules."
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

# Key Vault
variable "key_vault_name" {
  type        = string
  description = "Nom du Key Vault (3-24, lettres/chiffres et tirets, commence/finit par alphanum)"
  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{1,22}[a-zA-Z0-9])$", var.key_vault_name))
    error_message = "Le nom du Key Vault doit faire 3-24 caractères, alphanumériques et tirets, sans commencer/finir par un tiret."
  }
}

variable "kv_additional_reader_object_ids" {
  type        = list(string)
  description = "(Optionnel) Liste d'Object IDs (Azure AD) à autoriser en lecture de secrets (rôle Secrets User)"
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
  description = "Répertoire local (relatif à Terraform/) contenant les fichiers à uploader"
  default     = "../uploads/landing"
}

variable "upload_container_name" {
  type        = string
  description = "Conteneur cible pour l'upload (par défaut: landing)"
  default     = "landing"
}
