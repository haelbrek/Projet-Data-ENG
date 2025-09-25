# Architecture Azure Storage

Ce document complete le README et decrit l infrastructure fournie par Terraform pour le projet "Projet-Data-ENG".

## Apercu fonctionnel

- Compte Blob "landing" pour recevoir les donnees brutes
- Compte Azure Data Lake Storage Gen2 (zones `raw`, `staging`, `curated`)
- Azure Key Vault (Access Policies, purge protection)
- Azure Data Factory (identite system-assigned)
- Reseau virtuel + sous-reseaux dedies Databricks (private/public)
- Workspace Azure Databricks en mode VNet injection
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
| Data Factory | `azurerm_data_factory.adf` | Identite managee, orchestration |
| Reseau virtuel | `azurerm_virtual_network.data` | CIDR parametrable (`vnet_address_space`) |
| Subnets Databricks | `azurerm_subnet.databricks_*` | Delegation Databricks + endpoints Storage/SQL |
| Network Security Groups | `azurerm_network_security_group.databricks_*` | Regles VNet<->VNet + sortie Internet |
| Databricks workspace | `azurerm_databricks_workspace.dbw` | Workspace VNet injection (sku Standard) |
| Upload local optionnel | `azurerm_storage_blob.uploaded` | Un blob Block par fichier local detecte |

## Variables principales

A definir dans `Terraform/terraform.tfvars` :
- `resource_group_name`, `resource_group_location`
- `blob_storage_account_name`, `datalake_storage_account_name`
- `blob_containers`, `datalake_filesystems`
- `key_vault_name`, `kv_additional_reader_object_ids`
- `data_factory_name`
- `vnet_name`, `vnet_address_space`
- `databricks_private_subnet_name/prefix`, `databricks_public_subnet_name/prefix`
- `databricks_workspace_name`
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
- `virtual_network_name`
- `databricks_private_subnet_id`, `databricks_public_subnet_id`
- `databricks_workspace_url`
- `upload_files_enabled`, `upload_file_count`

## Databricks (VNet injection)

- Le reseau virtuel (`azurerm_virtual_network.data`) cree deux sous-reseaux (`azurerm_subnet.databricks_private` et `azurerm_subnet.databricks_public`) delegues a Databricks.
- Les Network Security Groups associes autorisent le trafic intra VNet et les sorties Internet (combler ou restreindre selon vos politiques).
- `azurerm_databricks_workspace.dbw` cree un workspace VNet-injecte qui reference automatiquement subnets et NSG.

Sorties utiles :
```bash
terraform output virtual_network_name
terraform output databricks_private_subnet_id
terraform output databricks_public_subnet_id
terraform output databricks_workspace_url
```

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
  - `databricks` non reconnu dans PowerShell -> verifier l'installation (`python -m pip show databricks-cli`), ajouter `...\Python310\Scripts` au `PATH`, redemarrer le terminal, ou utiliser `pipx`
  - Token Databricks -> UI : nom > Parametres > Developpeur > Gerer > Generer un nouveau jeton

