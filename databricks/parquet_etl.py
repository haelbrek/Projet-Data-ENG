# Databricks notebook source
# Notebook : /Shared/parquet_etl
# Objectif : Nettoyer le fichier SIRENE - Hauts-de-France, entreprises actives uniquement
# Copie chaque cellule séparée par "# COMMAND ----------" dans ton notebook Databricks

# COMMAND ----------

# ============================================================
# CELLULE 1 — Configuration ADLS
# ============================================================
STORAGE_ACCOUNT   = "adlselbrek2025"
CONTAINER_RAW     = "raw"
CONTAINER_STAGING = "staging"

# Clé d'accès : portail Azure → adlselbrek2025 → Access keys → key1
STORAGE_KEY = "<COLLE_ICI_TA_CLE_DACCES>"

spark.conf.set(
    f"fs.azure.account.key.{STORAGE_ACCOUNT}.dfs.core.windows.net",
    STORAGE_KEY
)

print("[OK] Connexion ADLS configurée")

# COMMAND ----------

# ============================================================
# CELLULE 2 — Chemins ADLS
# ============================================================
PATH_SOURCE = f"abfss://{CONTAINER_RAW}@{STORAGE_ACCOUNT}.dfs.core.windows.net/Parquet/StockEtablissement_utf8.parquet"
PATH_OUTPUT = f"abfss://{CONTAINER_STAGING}@{STORAGE_ACCOUNT}.dfs.core.windows.net/etablissements_hdf_actifs/"

print(f"[INFO] Source : {PATH_SOURCE}")
print(f"[INFO] Sortie : {PATH_OUTPUT}")

# COMMAND ----------

# ============================================================
# CELLULE 3 — Lecture du fichier brut
# ============================================================
df_raw = spark.read.parquet(PATH_SOURCE)

print("[OK] Fichier chargé")
print(f"     Lignes totales   : {df_raw.count():,}")
print(f"     Colonnes totales : {len(df_raw.columns)}")

# COMMAND ----------

# ============================================================
# CELLULE 4 — Sélection des colonnes essentielles (21/53)
# ============================================================
COLONNES_ESSENTIELLES = [
    # Identifiants
    "siret",
    "siren",
    "nic",
    # Statut établissement
    "etablissementSiege",
    "etatAdministratifEtablissement",
    # Dates
    "dateCreationEtablissement",
    "dateDebut",
    "dateDernierTraitementEtablissement",
    # Activité
    "activitePrincipaleEtablissement",
    "nomenclatureActivitePrincipaleEtablissement",
    "activitePrincipaleRegistreMetiersEtablissement",
    # Effectifs
    "trancheEffectifsEtablissement",
    "anneeEffectifsEtablissement",
    "caractereEmployeurEtablissement",
    # Adresse
    "numeroVoieEtablissement",
    "typeVoieEtablissement",
    "libelleVoieEtablissement",
    "codePostalEtablissement",
    "libelleCommuneEtablissement",
    "codeCommuneEtablissement",
    # Nom commercial
    "denominationUsuelleEtablissement",
    "enseigne1Etablissement",
]

df = df_raw.select(COLONNES_ESSENTIELLES)
print(f"[OK] Colonnes sélectionnées : {len(COLONNES_ESSENTIELLES)}/53")

# COMMAND ----------

# ============================================================
# CELLULE 5 — Filtre 1 : Entreprises ACTIVES uniquement
# etatAdministratifEtablissement = 'A' (Actif)
#                                  'F' (Fermé) → exclu
# ============================================================
from pyspark.sql.functions import col

df = df.filter(col("etatAdministratifEtablissement") == "A")
print(f"[OK] Après filtre ACTIF : {df.count():,} établissements")

# COMMAND ----------

# ============================================================
# CELLULE 6 — Filtre 2 : Région Hauts-de-France uniquement
# Départements : 02 (Aisne), 59 (Nord), 60 (Oise),
#                62 (Pas-de-Calais), 80 (Somme)
# ============================================================
from pyspark.sql.functions import substring

DEPARTEMENTS_HDF = ["02", "59", "60", "62", "80"]

df = df.filter(
    substring(col("codeCommuneEtablissement"), 1, 2).isin(DEPARTEMENTS_HDF)
)
print(f"[OK] Après filtre Hauts-de-France : {df.count():,} établissements")

# COMMAND ----------

# ============================================================
# CELLULE 7 — Suppression des colonnes entièrement vides
# ============================================================
from pyspark.sql.functions import count, when, isnan

total = df.count()
colonnes_vides = []

for col_name in df.columns:
    nb_nulls = df.filter(col(col_name).isNull()).count()
    if nb_nulls == total:
        colonnes_vides.append(col_name)

if colonnes_vides:
    df = df.drop(*colonnes_vides)
    print(f"[OK] Colonnes entièrement vides supprimées : {colonnes_vides}")
else:
    print("[OK] Aucune colonne entièrement vide trouvée")

print(f"     Colonnes restantes : {len(df.columns)}")

# COMMAND ----------

# ============================================================
# CELLULE 8 — Enrichissement et renommage des colonnes
# Noms lisibles + colonnes utiles ajoutées
# ============================================================
from pyspark.sql.functions import lit, current_date, to_date, substring

NOM_DEPARTEMENT = {
    "02": "Aisne",
    "59": "Nord",
    "60": "Oise",
    "62": "Pas-de-Calais",
    "80": "Somme",
}

from pyspark.sql.functions import create_map
from itertools import chain

mapping = create_map([lit(x) for x in chain(*NOM_DEPARTEMENT.items())])

df = (df
    # Ajout colonne département et région
    .withColumn("code_departement", substring(col("codeCommuneEtablissement"), 1, 2))
    .withColumn("nom_departement", mapping[col("code_departement")])
    .withColumn("region", lit("Hauts-de-France"))
    .withColumn("date_traitement", current_date())

    # Conversion des dates string → date
    .withColumn("dateCreationEtablissement",     to_date(col("dateCreationEtablissement"), "yyyy-MM-dd"))
    .withColumn("dateDebut",                     to_date(col("dateDebut"), "yyyy-MM-dd"))
    .withColumn("dateDernierTraitementEtablissement", to_date(col("dateDernierTraitementEtablissement"), "yyyy-MM-dd"))

    # Renommage pour lisibilité
    .withColumnRenamed("etablissementSiege",                        "est_siege")
    .withColumnRenamed("etatAdministratifEtablissement",            "etat")
    .withColumnRenamed("dateCreationEtablissement",                 "date_creation")
    .withColumnRenamed("dateDebut",                                 "date_debut_periode")
    .withColumnRenamed("dateDernierTraitementEtablissement",        "date_maj")
    .withColumnRenamed("activitePrincipaleEtablissement",           "code_naf")
    .withColumnRenamed("nomenclatureActivitePrincipaleEtablissement", "nomenclature_naf")
    .withColumnRenamed("activitePrincipaleRegistreMetiersEtablissement", "code_rma")
    .withColumnRenamed("trancheEffectifsEtablissement",             "tranche_effectifs")
    .withColumnRenamed("anneeEffectifsEtablissement",               "annee_effectifs")
    .withColumnRenamed("caractereEmployeurEtablissement",           "est_employeur")
    .withColumnRenamed("numeroVoieEtablissement",                   "num_voie")
    .withColumnRenamed("typeVoieEtablissement",                     "type_voie")
    .withColumnRenamed("libelleVoieEtablissement",                  "nom_voie")
    .withColumnRenamed("codePostalEtablissement",                   "code_postal")
    .withColumnRenamed("libelleCommuneEtablissement",               "commune")
    .withColumnRenamed("codeCommuneEtablissement",                  "code_commune")
    .withColumnRenamed("denominationUsuelleEtablissement",          "nom_commercial")
    .withColumnRenamed("enseigne1Etablissement",                    "enseigne")
)

print("[OK] Colonnes enrichies et renommées")
print(f"     Colonnes finales : {df.columns}")

# COMMAND ----------

# ============================================================
# CELLULE 9 — Aperçu et statistiques finales
# ============================================================
print("Résumé final :")
print(f"  Lignes   : {df.count():,}")
print(f"  Colonnes : {len(df.columns)}")
print()
print("Répartition par département :")
df.groupBy("code_departement", "nom_departement") \
  .count() \
  .orderBy("code_departement") \
  .show()

display(df.limit(20))

# COMMAND ----------

# ============================================================
# CELLULE 10 — Sauvegarde dans la zone CURATED
# Partitionné par département pour des requêtes plus rapides
# ============================================================
df.coalesce(1).write \
    .mode("overwrite") \
    .parquet(PATH_OUTPUT)

print("[OK] Données sauvegardées dans :")
print(f"     {PATH_OUTPUT}")
print("     Zone : staging/etablissements_hdf_actifs/")
print("     Partitions : 02 / 59 / 60 / 62 / 80")

# COMMAND ----------

# ============================================================
# CELLULE 11 — Vérification de l'écriture
# ============================================================
files = dbutils.fs.ls(PATH_OUTPUT)
for f in files:
    print(f.name, f"({f.size:,} bytes)" if f.size > 0 else "(dossier partition)")
