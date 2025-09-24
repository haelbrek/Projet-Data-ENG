# Architecture Azure Storage

Ce document complete le README et decrit l infrastructure fournie par Terraform pour le projet "Projet-Data-ENG".

## Apercu fonctionnel

- Compte Blob "landing" pour recevoir les donnees brutes
- Compte Azure Data Lake Storage Gen2 (zones `raw`, `staging`, `curated`)
- Azure Key Vault (Access Policies, purge protection)
- Azure Data Factory (identite system-assigned)
- Upload local optionnel de fichiers CSV via Terraform

## Ressources provisionnees

| Ressource | Definition Terraform | Points clefs |
|-----------|----------------------|--------------|
| Resource group | `azurerm_resource_group.rg` | Region definie par `var.resource_group_location` |
| Storage Account landing | `azurerm_storage_account.blob` | Standard LRS, HTTPS only, TLS1_2 |
| Conteneurs landing | `azurerm_storage_container.landing` | Liste `var.blob_containers`, acces prive |
| Data Lake (ADLS Gen2) | `azurerm_storage_account.datalake` | HNS actif, Standard LRS |
| Filesystems ADLS | `azurerm_storage_data_lake_gen2_filesystem.zones` | `raw`, `staging`, `curated` |
| Key Vault | `azurerm_key_vault.kv` | Access Policies, purge protection 90 jours |
| Data Factory | `azurerm_data_factory.adf` | Identite managée, taggee `orchestration` |
| Upload local optionnel | `azurerm_storage_blob.uploaded` | Un blob Block par fichier local detecte |

## Variables principales

A definir dans `Terraform/terraform.tfvars` :
- `resource_group_name`, `resource_group_location`
- `blob_storage_account_name`, `datalake_storage_account_name`
- `blob_containers`, `datalake_filesystems`
- `key_vault_name`, `kv_additional_reader_object_ids`
- `data_factory_name`
- Upload optionnel : `upload_files_enabled`, `upload_source_dir`, `upload_container_name`

## Upload local via Terraform

`local.upload_files` est calcule depuis `upload_source_dir` lorsque `upload_files_enabled = true`.
- Seuls les fichiers terminant par `.csv` sont retains (regex insensible a la casse)
- Le chemin virtuel du blob respecte l arborescence locale
- Un MD5 est calcule pour detecter les changements

Bonnes pratiques :
- Ne pas versionner `uploads/`
- Organiser les sous-dossiers (`csv/source/date=YYYY-MM-DD/fichier.csv`)

## Sorties Terraform

`Terraform/outputs.tf` expose :
- `blob_storage_account_name`, `blob_containers`
- `datalake_storage_account_name`, `datalake_filesystems`
- `blob_primary_connection_string`
- `datalake_dfs_endpoint`
- `key_vault_name`, `key_vault_uri`
- `data_factory_name`, `data_factory_identity_principal_id`
- `upload_files_enabled`, `upload_file_count`

## Deploiement type

```bash
cd Terraform
terraform init
terraform plan
terraform apply
```

Pour detruire :
```bash
terraform destroy
```

## Securite et conformite

- HTTPS obligatoire, TLS 1.2 minimum sur les comptes de stockage
- Key Vault : purge protection + soft delete 90 jours
- Aucun secret ne doit etre committe (`terraform.tfvars` ignore)
- Donnees locales (uploads) ignorees par Git

## Evolutions envisagees

- Basculer Key Vault en mode RBAC (ajouter `azurerm_role_assignment`)
- Activer diagnostic et logs sur les comptes de stockage
- Mettre en place CI/CD Terraform
- Attribuer les roles Storage (Blob Data Contributor) aux identites consommatrices

## Script d ingestion

- `ingestion/fetch_communes.py` : appelle geo.api.gouv.fr (Hauts-de-France par defaut), enrichit les donnees et charge un JSON unique dans Azure Blob. Options pour changer les departements, fournir une cle API et personnaliser le chemin du blob.

## Notes d execution et depannage

- Provisionnement : `cd Terraform && terraform init && terraform apply`
- Ingestion : `python ingestion/fetch_communes.py --connection-string "DefaultEndpointsProtocol=..." --departements 02 59 60 62 80 --container landing` (ajouter `--local-output` pour une copie locale)
- Erreurs courantes :
  - `Connection string is either blank or malformed` -> recuperer la chaine via `terraform output -raw blob_primary_connection_string` et la fournir (`--connection-string` ou variable `AZURE_STORAGE_CONNECTION_STRING`)
  - `AuthenticationFailed ... string to sign` -> rouvrir le terminal apres `setx` ou passer la chaine directement en argument
  - `can't open file ... terraform\ingestion\fetch_communes.py` -> lancer le script depuis la racine `D:\data eng\Projet-Data-ENG`
