# API Projet-Data-ENG

API FastAPI qui expose les tables Azure SQL g�n�r�es par la pr�paration de donn�es du projet.

## Installation locale

`powershell
cd analytics/api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python generate_env.py  # cr�e analytics/api/.env avec les valeurs Terraform si disponibles
uvicorn analytics.api.app.main:app --reload --port 8000
`

Endpoints principaux :
- GET /health : statut simple
- GET /tables/summary : description des tables pr�par�es
- GET /tables/{table_name}?limit=100 : extrait les donn�es d�une table autoris�e

Les param�tres SQL sont lus selon la priorit� suivante : .env > variables d�environnement > defaults.

## D�ploiement Azure App Service (exemple)

1. Cr�e un App Service plan Linux :
   `powershell
   az group create --name rg-elbrek-infra --location francecentral
   az appservice plan create --name plan-projet-data --resource-group rg-elbrek-infra --sku B1 --is-linux
   `
2. Cr�e le webapp :
   `powershell
   az webapp create --name proj-data-api --resource-group rg-elbrek-infra \
     --plan plan-projet-data --runtime "PYTHON|3.10" --deployment-local-git
   `
3. D�finis les variables d�environnement SQL :
   `powershell
   az webapp config appsettings set --name proj-data-api --resource-group rg-elbrek-infra --settings \
     AZURE_SQL_SERVER="sqlelbrek-prod.database.windows.net" \
     AZURE_SQL_DATABASE="projet_data_eng" \
     AZURE_SQL_USERNAME="sqladmin" \
     AZURE_SQL_PASSWORD="<motdepasse>" \
     ALLOWED_TABLES="stg_population,dim_commune,..."
   `
4. Pour les drivers ODBC, ajoute un script de startup (startup.sh) :
   `ash
   #!/usr/bin/env bash
   apt-get update && apt-get install -y curl apt-transport-https
   curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
   curl https://packages.microsoft.com/config/ubuntu/20.04/prod.list > /etc/apt/sources.list.d/mssql-release.list
   apt-get update && ACCEPT_EULA=Y apt-get install -y msodbcsql18 unixodbc-dev
   uvicorn analytics.api.app.main:app --host 0.0.0.0 --port 
   `
   Puis :
   `powershell
   az webapp config set --resource-group rg-elbrek-infra --name proj-data-api \
     --startup-file "bash startup.sh"
   `
5. D�ploie le code (git push, zip deploy, etc.).

## S�curit�

- Restreindre les tables expos�es via ALLOWED_TABLES
- Utiliser HTTPS, configurer une authentification (token, API Key, etc.) si l�API est publique
- Stocker les secrets dans Azure Key Vault + App Service Managed Identity
