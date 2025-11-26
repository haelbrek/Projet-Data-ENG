# Procedure de creation et chargement des donnees

## 1. Preparation
- Prerequis installes : Terraform 1.5+, Python 3.10+, Azure CLI (optionnel pour verifier).
- Fichier `Terraform/terraform.tfvars` renseigne (resource_group_name, datalake_storage_account_name, sql_*, etc.).
- Fichiers a uploader places dans `uploads/landing/` (CSV/XLSX).

## 2. Provisionner l'infrastructure avec Terraform
Depuis le dossier `Terraform/` :
```powershell
cd Terraform
terraform init
terraform plan
terraform apply --auto-approve
```
Parametres d'upload (dans `terraform.tfvars`) pour pousser automatiquement `uploads/landing/` :
```hcl
upload_files_enabled       = true
upload_source_dir          = "../uploads/landing"
upload_datalake_filesystem = "raw"
```
Apres `apply`, les fichiers de `uploads/landing/` sont copies dans ADLS Gen2 (`raw`).

## 3. Recuperer les communes via le script fetch_communes.py
1) Renseigner la chaine de connexion ADLS (apres recréation du compte, utiliser la nouvelle cle) :
   - PowerShell :
   ```powershell
   $env:AZURE_STORAGE_CONNECTION_STRING = "DefaultEndpointsProtocol=https;AccountName=adlselbrek;AccountKey=...;EndpointSuffix=core.windows.net"
   ```
   - Bash :
   ```bash
   export AZURE_STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=adlselbrek;AccountKey=...;EndpointSuffix=core.windows.net"
   ```
   - Pour recuperer la nouvelle chaine : Azure Portal > Storage account `adlselbrek` > Access keys > Connection string (cle1 ou cle2).

2) Depuis le dossier `Terraform/`, lancer le script :
```powershell
python ..\ingestion\API\fetch_communes.py --container raw
```
ou en Bash :
   ```bash
   python ../ingestion/API/fetch_communes.py --container raw
   ```
Le script recupere les communes depuis l'API geo, transforme, puis deverse un JSON dans le filesystem `raw` du Data Lake.

Notes :
- Adapter `--departements` si besoin (ex: `--departements 59 62` ou `--departements ""` pour tout prendre).
- `--datalake-path` permet de changer le chemin cible (par defaut `geo/communes-<timestamp>.json`).
- En cas de changement de compte ADLS, regénérer la chaine de connexion et remettre la variable d'environnement avant de relancer.

## 4. Charger les donnees dans Azure SQL avant d'exposer l'API
1) Depuis la racine du projet (ou en definissant `PYTHONPATH`), lancer l'export SQL :
   ```powershell
   python analytics/export_to_sql.py
   ```
   - Le script lit les creds dans `Terraform/terraform.tfvars` et/ou les variables `AZURE_SQL_*`.
   - Prerequis : ODBC Driver 18/17 installe, firewall SQL ouvert pour ton IP.

2) Une fois les tables chargees, demarrer l'API :
   - PowerShell :
   ```powershell
   python -m uvicorn analytics.api.app.main:app --reload --port 8000
   ```
   - Bash :
   ```bash
   python -m uvicorn analytics.api.app.main:app --reload --port 8000
   ```
   Les endpoints `/tables/...` renverront alors les donnees depuis Azure SQL (ex: `/tables/dim_commune?limit=100`).
