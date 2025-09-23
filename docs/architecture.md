# Architecture Azure Storage

Ce document complete le README et decrit l infrastructure fournie par Terraform pour le projet "Projet-Data-ENG".

## Apercu fonctionnel

L infrastructure vise a fournir un socle de stockage pour un projet data analytique:
- un compte de stockage "landing" pour recevoir les extractions brutes;
- un compte Azure Data Lake Storage Gen2 avec hierarchie HNS pour les zones `raw`, `staging`, `curated`;
- un Azure Key Vault pour proteger les secrets operationnels;
- un Azure Data Factory avec identite managee system-assigned pour orchestrer de futurs pipelines;
- un mecanisme optionnel d upload local de fichiers CSV directement dans le conteneur Blob "landing".

## Ressources provisionnees

| Ressource | Definition Terraform | Points clefs |
|-----------|----------------------|--------------|
| Resource group | `azurerm_resource_group.rg` | Regroupe toutes les ressources dans la region definie par `var.resource_group_location`. |
| Storage Account landing | `azurerm_storage_account.blob` | Compte Standard LRS, HTTPS only, TLS1_2. Concu sans HNS pour un usage Blob classique. |
| Conteneurs landing | `azurerm_storage_container.landing` | Liste definie par `var.blob_containers`. Chaque conteneur est prive. |
| Data Lake (ADLS Gen2) | `azurerm_storage_account.datalake` | HNS active pour disposer d un namespace hierarchique. Stockage Standard LRS. |
| Filesystems ADLS | `azurerm_storage_data_lake_gen2_filesystem.zones` | Filesystems `raw`, `staging`, `curated` par defaut. |
| Key Vault | `azurerm_key_vault.kv` | Mode Access Policies, purge protection et soft delete 90 jours. Une policy donne acces complet aux secrets pour le deployeeur. |
| Data Factory | `azurerm_data_factory.adf` | Identite system-assigned. `azurerm_key_vault_access_policy.kv_adf_reader` autorise Get/List sur les secrets. |
| Upload local optionnel | `azurerm_storage_blob.uploaded` | Parcourt `local.upload_files` et cree un blob Block pour chaque fichier CSV detecte localement. |

## Variables principales

Les valeurs se parametrent via `Terraform/terraform.tfvars` (non committe). Variables clefs:
- `resource_group_name`, `resource_group_location`
- `blob_storage_account_name`, `datalake_storage_account_name`
- `blob_containers`, `datalake_filesystems`
- `key_vault_name`, `kv_additional_reader_object_ids`
- `data_factory_name`
- Upload optionnel: `upload_files_enabled`, `upload_source_dir`, `upload_container_name`

## Upload local vers Blob

Lorsque `upload_files_enabled = true`, Terraform calcule `local.upload_files` a partir du dossier configure. Le filtrage conserve uniquement les fichiers dont le nom termine par `.csv` (regex insensible a la casse). Chaque fichier est cree dans le conteneur Blob cible avec le meme chemin virtuel que sur disque. Le checksum MD5 detecte les modifications.

Bonnes pratiques:
- ne versionner aucune donnee dans `uploads/` (le dossier est ignore par Git)
- structurer en sous-dossiers si necessaire (`csv/source/date=YYYY-MM-DD/fichier.csv`)

## Sorties Terraform

Les outputs exposes dans `Terraform/outputs.tf` facilitent les integrations aval:
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

Destruction lorsque necessaire:

```bash
terraform destroy
```

## Securite et conformite

- HTTPS obligatoire et TLS 1.2 minimum sur les comptes de stockage
- Key Vault protege par purge protection et soft delete 90 jours
- Aucun secret ne doit etre committe dans le code ou `terraform.tfvars`
- Les donnees locales d upload sont ignorees par Git

## Evolutions envisagees

- Basculement du Key Vault en mode RBAC avec des `azurerm_role_assignment`
- Ajout de diagnostics et de metrics sur les comptes de stockage
- Automatisation des pipelines Data Factory et integration CI/CD Terraform
- Attribution des roles Storage (Blob Data Contributor) aux identites consommatrices

## Scripts d ingestion

- `ingestion/fetch_communes.py` : interroge une API de communes (par defaut `geo.api.gouv.fr`), agrege les donnees par departement (Hauts-de-France par defaut), extrait coordonnees/attributs, puis charge un JSON unique dans Azure Blob Storage. Options pour personnaliser les departements, fournir une cle API et choisir le chemin de sortie.





## Notes d execution et de depannage

- Provisionnement via Terraform : 	erraform init && terraform apply dans Terraform/.
- Execution ingestion : python ingestion/fetch_communes.py --connection-string "DefaultEndpointsProtocol=..." --departements 02 59 60 62 80 --container landing (option --local-output pour conserver une copie).
- Erreurs rencontrees :
  - Connection string is either blank or malformed -> variable non definie : recuperer la chaine avec 	erraform output -raw blob_primary_connection_string et la passer a la commande ou exporter AZURE_STORAGE_CONNECTION_STRING.
  - AuthenticationFailed ... string to sign -> terminal non relance apres setx : rouvrir la session ou passer la chaine directement via --connection-string.
  - can't open file ... terraform\ingestion\fetch_communes.py -> chemin incorrect : lancer la commande depuis la racine du projet (D:\data eng\Projet-Data-ENG).
