# Procédure complète Databricks — De la création à l'exécution du Notebook

**Projet :** Projet Data Engineering E4
**Workspace :** `dbw-elbrek-e4`
**URL :** `https://adb-XXXXXXXXXXXXXXXX.XX.azuredatabricks.net`
**Utilisateur :** `<votre-email-azure-ad>`

---

## Vue d'ensemble

```
ÉTAPE 1 → Prérequis et configuration Terraform
ÉTAPE 2 → Déploiement Terraform (création workspace + cluster + job)
ÉTAPE 3 → Récupération de la clé ADLS
ÉTAPE 4 → Génération du token Databricks
ÉTAPE 5 → Création du notebook /Shared/parquet_etl
ÉTAPE 6 → Ajout du code dans le notebook
ÉTAPE 7 → Lancement du job depuis Workflows
ÉTAPE 8 → Vérification des résultats
```

---

## ÉTAPE 1 — Prérequis

### 1.1 Outils nécessaires
Vérifie que ces outils sont installés sur ta machine :

```bash
# Vérifier Terraform
terraform --version
# Attendu : Terraform v1.x.x

# Vérifier Azure CLI
az --version
# Attendu : azure-cli 2.x.x
```

### 1.2 Connexion Azure
```bash
# Se connecter à Azure
az login

# Vérifier le bon abonnement
az account show
```

### 1.3 Vérifier le fichier terraform.tfvars
Le fichier `Terraform/terraform.tfvars` doit contenir :

```hcl
create_databricks         = true
databricks_workspace_name = "dbw-elbrek-e4"
databricks_host           = "https://adb-XXXXXXXXXXXXXXXX.XX.azuredatabricks.net"
databricks_token          = "<votre-token-databricks>"
databricks_single_user    = "<votre-email-azure-ad>"
```

> **Note :** `databricks_host` et `databricks_token` sont nécessaires
> uniquement après la première création du workspace.

---

## ÉTAPE 2 — Déploiement Terraform

### 2.1 Se placer dans le dossier Terraform
```bash
cd "/media/ha-brek/Data/DATA ENG/E4/Projet-Data-ENG/Terraform"
```

### 2.2 Initialiser Terraform (première fois uniquement)
```bash
terraform init
```
Résultat attendu :
```
Terraform has been successfully initialized!
```

### 2.3 Vérifier le plan
```bash
terraform plan
```
Tu dois voir dans le plan :
- `databricks_cluster.etl_parquet` → cluster `etl-parquet`
- `databricks_job.parquet_etl` → job `parquet-etl`
- `azurerm_databricks_workspace.dbw` → workspace `dbw-elbrek-e4`

### 2.4 Appliquer
```bash
terraform apply
```
Tape `yes` quand demandé.

Durée : **5 à 15 minutes** (la création du workspace Databricks est longue).

### 2.5 Vérifier les outputs
```bash
terraform output databricks_workspace_url
```
Résultat attendu :
```
"https://adb-XXXXXXXXXXXXXXXX.XX.azuredatabricks.net"
```

---

## ÉTAPE 3 — Récupérer la clé d'accès ADLS

La clé est nécessaire pour que le notebook Databricks lise les fichiers dans le Data Lake.

### Option A — Via Terraform output
```bash
cd "/media/ha-brek/Data/DATA ENG/E4/Projet-Data-ENG/Terraform"
terraform output -raw datalake_primary_connection_string
```
Résultat (exemple) :
```
DefaultEndpointsProtocol=https;AccountName=adlselbrek2025;AccountKey=XXXXXXXXXXXX==;...
```
Copie uniquement la valeur après `AccountKey=` jusqu'au `;` suivant.

### Option B — Via le portail Azure
1. Va sur `portal.azure.com`
2. Recherche **adlselbrek2025** dans la barre de recherche
3. Clique sur le Storage Account
4. Menu gauche → **Security + networking** → **Access keys**
5. Clique sur **Show** à côté de `key1`
6. Copie la valeur du champ **Key**

---

## ÉTAPE 4 — Générer/Vérifier le token Databricks

Le token permet à Terraform de créer les ressources dans Databricks (cluster, job).

### 4.1 Se connecter au workspace
Va sur l'URL de ton workspace Databricks (visible dans les outputs Terraform).
Connecte-toi avec ton compte Azure AD.

### 4.2 Générer un nouveau token (si l'actuel est expiré)
1. En haut à droite → clique sur ton **profil** (initiales)
2. Clique sur **User Settings**
3. Onglet **Developer** → **Access tokens**
4. Clique **Generate new token**
5. Description : `terraform-etl`
6. Durée : `90 days` (ou plus)
7. Clique **Generate**
8. **Copie le token** (ne se réaffiche plus après)

### 4.3 Mettre à jour terraform.tfvars
Remplace la valeur dans `Terraform/terraform.tfvars` :
```hcl
databricks_token = "dapi<ton-nouveau-token>"
```

---

## ÉTAPE 5 — Créer le notebook dans Databricks

### 5.1 Accéder au Workspace
1. Dans la barre de gauche, clique sur l'icône **Workspace** (dossier)
2. Dans l'arborescence, clique sur **Shared**

### 5.2 Créer le notebook
1. **Clic droit** sur `Shared`
2. **Create** → **Notebook**
3. Remplis le formulaire :
   - **Name :** `parquet_etl`
   - **Default Language :** `Python`
4. Clique **Create**

### 5.3 Vérifier le chemin
En haut du notebook, tu dois voir :
```
Workspace > Shared > parquet_etl
```
Chemin Databricks : `/Shared/parquet_etl`
Ce chemin correspond exactement à la variable `databricks_notebook_path` dans Terraform.

---

## ÉTAPE 6 — Ajouter le code dans le notebook

Le fichier source est disponible localement :
```
databricks/parquet_etl.py
```

### 6.1 Ouvrir le fichier local
```bash
cat "/media/ha-brek/Data/DATA ENG/E4/Projet-Data-ENG/databricks/parquet_etl.py"
```

### 6.2 Remplacer la clé ADLS
Dans le fichier, remplace :
```python
STORAGE_KEY = "<COLLE_ICI_TA_CLE_DACCES>"
```
par la clé récupérée à l'**ÉTAPE 3**.

### 6.3 Copier chaque cellule dans Databricks

Le fichier contient 7 cellules séparées par `# COMMAND ----------`.
Pour chaque cellule :
1. Clique dans la cellule du notebook (ou **+ Code** pour en ajouter une)
2. Colle le contenu de la cellule correspondante
3. Répète pour les 7 cellules

**Résumé des cellules :**

| # | Contenu |
|---|---------|
| 1 | Configuration connexion ADLS (`STORAGE_KEY`) |
| 2 | Chemin du fichier Parquet dans ADLS |
| 3 | Lecture du fichier avec Spark |
| 4 | Affichage du schéma (colonnes + types) |
| 5 | Aperçu des 20 premières lignes |
| 6 | Statistiques (nombre de lignes, colonnes) |
| 7 | (Optionnel) Écriture en zone staging |

### 6.4 Chemin du fichier Parquet
Le fichier uploadé par Terraform est :
```
Fichier local  : uploads/landing/Parquet/StockEtablissement_utf8.parquet
Chemin ADLS    : abfss://raw@adlselbrek2025.dfs.core.windows.net/Parquet/StockEtablissement_utf8.parquet
```

---

## ÉTAPE 7 — Lancer le job depuis Workflows

Le job `parquet-etl` a été créé automatiquement par Terraform.
Il utilise le cluster `etl-parquet` et exécute le notebook `/Shared/parquet_etl`.

### 7.1 Accéder aux Workflows
Dans la barre de gauche, clique sur **Workflows** (icône horloge/engrenage)

### 7.2 Trouver le job
Tu dois voir dans la liste :
```
parquet-etl    [Run now]
```

### 7.3 Lancer le job
1. Clique sur **parquet-etl**
2. Clique sur **Run now** (bouton bleu en haut à droite)

### 7.4 Surveiller l'exécution
1. Dans l'onglet **Runs**, clique sur le run en cours
2. Clique sur la tâche **parquet_etl_task**
3. Tu vois les logs en temps réel

**Durée estimée :** 3 à 8 minutes (démarrage du cluster inclus)

**Statuts possibles :**

| Statut | Signification |
|--------|--------------|
| `Pending` | En attente de démarrage du cluster |
| `Running` | Exécution en cours |
| `Succeeded` | Terminé avec succès |
| `Failed` | Erreur — consulter les logs |

---

## ÉTAPE 8 — Vérifier les résultats

### Option A — Via le portail Azure
1. Va sur `portal.azure.com`
2. Recherche `adlselbrek2025`
3. **Containers** → **raw** → dossier **Parquet/**
4. Tu dois voir `StockEtablissement_utf8.parquet`

### Option B — Via Azure CLI
```bash
az storage blob list \
  --account-name adlselbrek2025 \
  --container-name raw \
  --prefix "Parquet/" \
  --output table
```

### Option C — Directement dans Databricks
Ajoute une cellule dans le notebook :
```python
files = dbutils.fs.ls("abfss://raw@adlselbrek2025.dfs.core.windows.net/Parquet/")
for f in files:
    print(f.name, f.size)
```

---

## Résolution des problèmes fréquents

### Erreur : `AuthorizationPermissionMismatch`
**Cause :** La clé ADLS est incorrecte ou vide.
**Solution :** Refaire l'**ÉTAPE 3** et vérifier que `STORAGE_KEY` est bien renseigné.

### Erreur : `InvalidNotebookPath`
**Cause :** Le notebook n'existe pas à `/Shared/parquet_etl`.
**Solution :** Refaire l'**ÉTAPE 5** — vérifier que le nom est `parquet_etl` (sans espace).

### Erreur : `ClusterNotFound` ou cluster qui ne démarre pas
**Cause :** Le cluster `etl-parquet` n'a pas été créé par Terraform.
**Solution :** Relancer `terraform apply` depuis l'**ÉTAPE 2**.

### Erreur : `403 Forbidden` sur l'ADLS
**Cause :** Le token Databricks est expiré.
**Solution :** Générer un nouveau token (**ÉTAPE 4**) et relancer `terraform apply`.

---

## Architecture complète

```
┌─────────────────────────────────────────────────────────┐
│                    TERRAFORM                            │
│                                                         │
│  terraform apply                                        │
│       ↓                                                 │
│  ┌─────────────────────┐  ┌────────────────────────┐   │
│  │ Cluster "etl-parquet│  │  Job "parquet-etl"     │   │
│  │ Standard_D4s_v5     │  │  → notebook_path:      │   │
│  │ Spark 13.3.x        │◄─┤    /Shared/parquet_etl │   │
│  │ 1-2 workers         │  └────────────────────────┘   │
│  └─────────────────────┘                                │
└─────────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────────┐
│              DATABRICKS WORKSPACE                       │
│                                                         │
│  /Shared/parquet_etl  (notebook créé manuellement)      │
│       ↓                                                 │
│  Lit depuis ADLS :                                      │
│  raw/Parquet/StockEtablissement_utf8.parquet            │
│       ↓                                                 │
│  Affiche : schéma, aperçu, stats                        │
│  (Optionnel) Écrit dans : staging/etablissements/       │
└─────────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────────┐
│              ADLS Gen2 — adlselbrek2025                 │
│                                                         │
│  raw/                                                   │
│    └── Parquet/                                         │
│          └── StockEtablissement_utf8.parquet            │
│  staging/   (zone de sortie optionnelle)                │
│  curated/   (zone finale)                               │
└─────────────────────────────────────────────────────────┘
```

---

*Document généré pour le projet Data Engineering E4 — workspace `dbw-elbrek-e4`*
