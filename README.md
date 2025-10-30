# Projet-Data-ENG

Suites d'outils et d'infrastructure pour collecter, déposer, préparer puis publier des données territoriales (CSV locaux, API, scraping) sur Azure. Le projet automatise les étapes critiques : stockage dans un Data Lake, préparation analytique, et chargement vers Azure SQL Database.

## 1. Vue d’ensemble

Flux principal :

1. **Collecte des sources**  
   - CSV déposés dans `uploads/landing/` (ex : statistiques INSEE, démographie).  
   - API `ingestion/fetch_communes.py` pour récupérer un JSON consolidé des communes.  
   - Jeux scrappés/externes ajoutés dans le dossier `uploads/`.
2. **Atterrissage dans Azure Data Lake**  
   - `terraform apply` peut téléverser automatiquement `uploads/landing/` dans le filesystem `raw`.  
   - Le script `analytics/data_loader.py` permet aussi de rapatrier les données depuis ADLS.
3. **Préparation & nettoyage**  
   - Notebook `analytics/notebooks/data_preparation.ipynb` ou module Python `analytics.lib.data_prep` pour transformer les fichiers en tables normalisées (`stg_population`, `dim_commune`, etc.).
4. **Publication dans Azure SQL Database**  
   - `analytics/export_to_sql.py` charge les tables préparées vers la base `projet_data_eng` (schéma `dbo` par défaut).  
   - Le script lit automatiquement la configuration SQL dans `Terraform/terraform.tfvars`.

![Flux logique](docs/img/dataflow.png "Collecte -> Data Lake -> Préparation -> SQL") *(image optionnelle à ajouter)*

## 2. Prérequis

| Outil | Version mini | Commentaires |
|-------|--------------|--------------|
| Terraform | 1.5+ | Provisionnement infra |
| Azure CLI | 2.52+ | Authentification & diagnostics |
| Python | 3.10+ | Scripts d’ingestion et de préparation |
| ODBC Driver for SQL Server | 18 (ou 17) | Requis pour l’export vers Azure SQL |

Installer les dépendances Python :

```powershell
python -m pip install -r requirements.txt
```

## 3. Provisionner l’infrastructure

```powershell
cd Terraform
terraform init
terraform plan
terraform apply
```

Variables essentielles à définir dans `Terraform/terraform.tfvars` :

```hcl
resource_group_name       = "rg-exemple"
resource_group_location   = "francecentral"
datalake_storage_account_name = "nomstockage"
key_vault_name            = "kv-exemple"
data_factory_name         = "adf-exemple"

# Azure SQL
sql_server_name        = "sqlexemple"
sql_admin_login        = "sqladmin"
sql_admin_password     = "MotDePasse!2024"
sql_database_name      = "projet_data_eng"
sql_firewall_rules = [
  { name = "Home", start_ip = "X.X.X.X", end_ip = "X.X.X.X" }
]
```

Sorties Terraform utiles :

```powershell
terraform output datalake_primary_connection_string
terraform output sql_server_fqdn
terraform output sql_database_name
```

## 4. Collecter et déposer les données

### 4.1 Chargement local -> Data Lake

1. Placer les fichiers CSV/XLSX dans `uploads/landing/` (structure libre).  
2. Activer l’upload automatique :
   ```hcl
   upload_files_enabled = true
   upload_source_dir    = "../uploads/landing"
   upload_datalake_filesystem = "raw"
   ```
3. `terraform apply` téléverse les fichiers dans `abfss://raw@<storage>.dfs.core.windows.net/`.

### 4.2 Ingestion API communes

```powershell
python ingestion/fetch_communes.py `
  --connection-string "<chaîne ADLS>" `
  --departements 02 59 60 62 80 `
  --container raw `
  --local-output data/communes.json
```

Paramètres additionnels : `--departements ""` pour tout récupérer, `--datalake-path` pour changer le chemin distant.

### 4.3 Exploration depuis le Data Lake

Lister/télécharger ce qui est dans ADLS :

```powershell
python analytics/data_loader.py list --csv-prefix csv/
python analytics/data_loader.py fetch --csv-prefix csv/ --json-prefix geo/ --save-local
```

Variables possibles :

- `--connection-string` ou variable `AZURE_STORAGE_CONNECTION_STRING`
- `--filesystem` (`raw`, `staging`, …)
- `--keep-json` pour conserver les payloads brut.

## 5. Préparer les tables analytiques

Deux options :

1. **Notebook interactif** : `analytics/notebooks/data_preparation.ipynb`
   - Auto-détection du projet (`PROJECT_ROOT`).
   - Harmonise les colonnes (noms normalisés, zfill, conversions numériques).
   - Produit des tables `stg_*`, `dim_commune`, `bridge_commune_code_postal`.
   - Permet un export local Parquet (`data/prepared/silver/`) via `SAVE_TO_PARQUET = True`.

2. **Module réutilisable** : `analytics/lib/data_prep.py`
   - Fonction `prepare_tables()` renvoyant un dict `{nom_table: DataFrame}`.
   - Utilisé par le script d’export SQL (et testable en ligne de commande).

Exemple rapide :

```python
from analytics.lib.data_prep import prepare_tables, tables_summary

tables = prepare_tables()
print(tables_summary(tables))
```

## 6. Charger vers Azure SQL Database

### 6.1 Préparer la connexion

Le script `analytics/export_to_sql.py` lit automatiquement :

- `Terraform/terraform.tfvars` (`sql_server_name`, `sql_admin_login`, `sql_admin_password`, `sql_database_name`)
- Variables d’environnement `AZURE_SQL_SERVER`, `AZURE_SQL_USERNAME`, `AZURE_SQL_PASSWORD`, `AZURE_SQL_DATABASE`
- Paramètres CLI (`--server`, `--username`, …)

Assurez-vous d’avoir le driver ODBC 18 (ou 17) installé.

### 6.2 Commande d’export

```powershell
python analytics/export_to_sql.py
```

Options utiles :

- `--chunksize 200` pour ajuster la taille des lots envoyés.
- `--schema analytics` pour changer le schéma cible.
- `--preview` pour afficher uniquement le résumé des tables sans les charger.

Le script :

1. Prépare les DataFrames via `prepare_tables()`.
2. Affiche un résumé des lignes/colonnes.
3. Tente de se connecter en testant plusieurs drivers (`ODBC 18`, `ODBC 17`, …).
4. Insère les données table par table (`replace` sur le premier lot, `append` ensuite).
5. Ignore les tables vides (ex : `dim_commune_geojson` si aucun contour n’est disponible).

### 6.3 Vérification rapide

```sql
SELECT TABLE_NAME, COUNT(*) AS rows
FROM INFORMATION_SCHEMA.TABLES t
JOIN sys.tables s ON s.name = t.TABLE_NAME
WHERE t.TABLE_SCHEMA = 'dbo';
```
python generate_env.py  # g�n�re .env � partir de Terraform/terraform.tfvars si possible
$env:PYTHONPATH = "D:\data eng\Projet-Data-ENG"  # important pour pointer sur le package local
python -m uvicorn analytics.api.app.main:app --reload --port 8000
## 7. Exposer les tables via l’API FastAPI
$env:PYTHONPATH = "D:\data eng\Projet-Data-ENG"  # important pour pointer sur le package local
"
