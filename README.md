# Projet-Data-ENG

Infrastructure-as-Code (Terraform) et scripts d ingestion pour provisionner un socle Azure Storage (landing + Data Lake), un Key Vault, un Data Factory et automatiser l import des communes via l API geo.api.gouv.fr.

## 1. Infrastructure

- Groupe de ressources Azure (nom et region parametrables)
- Compte de stockage Blob "landing" (HTTPS only, TLS1_2)
- Compte ADLS Gen2 (HNS actif) avec filesystems `raw`, `staging`, `curated`
- Azure Key Vault (Access Policies, purge protection)
- Azure Data Factory avec identite system-assigned
- Reseau virtuel avec sous-reseaux dedies Databricks (private/public + NSG)
- Workspace Azure Databricks en mode VNet injection
- Upload local optionnel des fichiers CSV via Terraform

Documentation detaillee : `docs/architecture.md`.

## 2. Prerequis

- Terraform 1.5+
- Azure CLI 2.52+
- Compte Azure avec droits de creation
- Python 3.10+ et `pip`

## 3. Deploiement rapide

```bash
cd Terraform
terraform init
terraform plan
terraform apply
```

Repondez `yes` pour appliquer. Les sorties utiles sont visibles via `terraform output`.

### Upload Terraform optionnel

1. Placer les CSV dans `uploads/landing/csv/`
2. Dans `Terraform/terraform.tfvars`, fixer `upload_files_enabled = true` (adapter `upload_source_dir`, `upload_container_name` si besoin)
3. `terraform apply`
4. ContrÃ´ler `terraform output upload_file_count`

## 4. Configuration projet

Parametres principaux (`Terraform/terraform.tfvars` non versionne) :
- `resource_group_name`
- `resource_group_location`
- `blob_storage_account_name`
- `datalake_storage_account_name`
- `key_vault_name`
- `data_factory_name`
- `kv_additional_reader_object_ids`
- Variables reseau Databricks (`vnet_name`, `vnet_address_space`, `databricks_*_subnet_*`)
- `databricks_workspace_name`
- Variables d upload optionnel (`upload_files_enabled`, `upload_source_dir`, `upload_container_name`)

Les comptes de stockage doivent respecter : minuscules, chiffres, 3-24 caracteres, nom globalement unique.

## 5. Ingestion des communes (API geo.api.gouv.fr)

Le repertoire `ingestion/` contient `fetch_communes.py`. Le script :
- interroge l API geo.api.gouv.fr (departements Hauts-de-France par defaut)
- enrichit la reponse (longitude/latitude, libelles departement/region, contour GeoJSON)
- construit un JSON unique et l envoie dans le conteneur Blob `landing`
- optionnellement, ecrit un fichier JSON local

### Installation dependances

```bash
python -m pip install -r requirements.txt
```

### Recuperer la chaine de connexion Azure Storage

```bash
cd Terraform
terraform output -raw blob_primary_connection_string
cd ..
```

### Execution standard

```bash
python ingestion/fetch_communes.py \
  --connection-string "DefaultEndpointsProtocol=..." \
  --departements 02 59 60 62 80 \
  --container landing \
  --local-output data/communes_hauts_de_france.json
```

Options utiles :
- Omettre `--departements` (ou passer `--departements ""`) pour recuperer toutes les communes
- `--blob-path` pour fixer le nom du JSON dans le conteneur
- `--api-key`, `--api-key-header` (X-API-Key par exemple) ou `--api-key-param` pour les APIs protegees

### Difficultes rencontrees

| Probleme | Cause | Solution |
|----------|-------|----------|
| `Connection string is either blank or malformed` | chaine non fournie | recuperer la chaine via Terraform/portail et la transmettre (`--connection-string` ou variable d environnement) |
| `AuthenticationFailed ... string to sign '/bselbrek/landing restype:container'` | `setx` pris en compte uniquement apres ouverture d un nouveau terminal | rouvrir la session ou passer la chaine en argument |
| `can't open file ... terraform\ingestion\fetch_communes.py` | commande lancee depuis le dossier Terraform | executer depuis la racine `D:\data eng\Projet-Data-ENG` |

### Commandes resumees

```bash
# Provision infra
cd Terraform
terraform init
terraform apply
cd ..

# Installation dependances Python
python -m pip install -r requirements.txt

# Recuperer la chaine de connexion
cd Terraform
terraform output -raw blob_primary_connection_string
cd ..

# Lancer l ingestion JSON
python ingestion/fetch_communes.py \
  --connection-string "DefaultEndpointsProtocol=..." \
  --departements 02 59 60 62 80 \
  --container landing \
  --local-output data/communes.json
```

### Token Databricks (UI et CLI)

**UI**
1. `terraform output databricks_workspace_url` puis ouvre le lien.
2. Clique sur ton nom (coin haut droit) > **Paramètres** > **Développeur**.
3. Bouton **Gérer** en face de *Jetons d'accès*, puis **Générer un nouveau jeton**.
4. Copie le token (visible une seule fois).

**CLI (Python Microsoft Store)**
```powershell
python -m pip show databricks-cli
Get-ChildItem "C:\Users\elbre\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.10_qbz5n2kfra8p0\LocalCache\local-packages\Python310\Scripts" databricks*.*
python -m pip install --user databricks-cli    # si nécessaire
$Env:PATH += ';C:\Users\elbre\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.10_qbz5n2kfra8p0\LocalCache\local-packages\Python310\Scripts'
# Option : python -m pip install --user pipx ; python -m pipx ensurepath ; pipx install databricks-cli
```
Ferme/rouvre le terminal puis exécute `databricks --version`.

**Configurer le CLI**
```powershell
databricks configure --token
# Workspace URL : terraform output databricks_workspace_url
# Token : jeton généré via l'UI
```
Si besoin : `"C:\Users\elbre\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.10_qbz5n2kfra8p0\LocalCache\local-packages\Python310\Scripts\databricks.exe" configure --token`.

**Commandes utiles** : `databricks secrets list-scopes`, `databricks clusters list`.

**Retrouver l'URL du workspace**
- `terraform output databricks_workspace_url`
- Portail Azure > ressource Databricks (`dbw-elbrek`) > **Launch Workspace** / **Workspace URL**.

## 6. Workspace Databricks (VNet injection)

Terraform cree :
- un reseau virtuel (`virtual_network_name`) et deux sous-reseaux dedies (`databricks_private_subnet_id`, `databricks_public_subnet_id`)
- deux Network Security Groups associes pour controler les flux (lances automatiques)
- un workspace Azure Databricks (`databricks_workspace_name`) deja rattache au VNet

Apres `terraform apply`, recupere les informations utiles :
```bash
cd Terraform
terraform output databricks_workspace_url
terraform output databricks_private_subnet_id
terraform output databricks_public_subnet_id
cd ..
```
Le workspace est pret a recevoir des clusters (mode VNet-injected). Les NSG permettent les communications intra-VNet et la sortie internet. Adapte les regles si ta politique de securite l exige.

## 7. Arborescence

```
Terraform/
  main.tf
  variables.tf
  providers.tf
  outputs.tf
  terraform.tfvars        # valeurs locales (ignorees)
docs/
  architecture.md
ingestion/
  fetch_communes.py
uploads/
  landing/
requirements.txt
.gitignore
README.md
```

Astuce : generer un `Terraform/terraform.tfvars.example` pour partager un gabarit sans secrets.

## 8. Nettoyage

```bash
cd Terraform
terraform destroy
```

## 9. Depannage rapide

- `az login` derriere proxy interceptant TLS : importer le certificat et fixer `REQUESTS_CA_BUNDLE`
- Noms comptes stockage rejetes : respecter le format (lowercase, 3-24, unique)
- Upload Terraform ignore : verifier `upload_files_enabled` et l extension `.csv`

## 10. Publier sur GitHub

```bash
git init
git add .
git commit -m "Initial infrastructure"
git remote add origin https://github.com/<organisation>/projet-data-eng.git
git push -u origin main
```

Ne pas versionner `uploads/` pour eviter toute fuite de donnees.

## 11. Ressources complementaires

- `docs/architecture.md`
- Terraform provider AzureRM : https://registry.terraform.io/providers/hashicorp/azurerm/latest
- Azure CLI : https://learn.microsoft.com/cli/azure

