"""
ETL local : SIRENE Parquet -> nettoyage -> ADLS curated/
Même logique que le notebook Databricks mais sans Spark.
Utilise pyarrow (lecture filtrée) + pandas + azure-storage-blob.

Usage :
    python databricks/etl_local.py
"""

import io
import os
from datetime import date
from itertools import chain

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
from azure.storage.blob import BlobServiceClient, ContentSettings

# ============================================================
# CONFIGURATION — même valeurs que terraform.tfvars
# ============================================================
STORAGE_ACCOUNT   = "adlselbrek2025"
CONTAINER_RAW     = "raw"
CONTAINER_CURATED = "curated"

# Clé d'accès : portail Azure -> adlselbrek2025 -> Access keys -> key1
STORAGE_KEY = os.getenv("ADLS_STORAGE_KEY", "<COLLE_ICI_TA_CLE>")

BLOB_SOURCE = "Parquet/StockEtablissement_utf8.parquet"
PREFIX_OUTPUT = "etablissements_hdf_actifs"

DEPARTEMENTS_HDF = ["02", "59", "60", "62", "80"]

NOM_DEPARTEMENT = {
    "02": "Aisne",
    "59": "Nord",
    "60": "Oise",
    "62": "Pas-de-Calais",
    "80": "Somme",
}

COLONNES_ESSENTIELLES = [
    "siret", "siren", "nic",
    "etablissementSiege",
    "etatAdministratifEtablissement",
    "dateCreationEtablissement",
    "dateDebut",
    "dateDernierTraitementEtablissement",
    "activitePrincipaleEtablissement",
    "nomenclatureActivitePrincipaleEtablissement",
    "activitePrincipaleRegistreMetiersEtablissement",
    "trancheEffectifsEtablissement",
    "anneeEffectifsEtablissement",
    "caractereEmployeurEtablissement",
    "numeroVoieEtablissement",
    "typeVoieEtablissement",
    "libelleVoieEtablissement",
    "codePostalEtablissement",
    "libelleCommuneEtablissement",
    "codeCommuneEtablissement",
    "denominationUsuelleEtablissement",
    "enseigne1Etablissement",
]

RENOMMAGE = {
    "etablissementSiege":                           "est_siege",
    "etatAdministratifEtablissement":               "etat",
    "dateCreationEtablissement":                    "date_creation",
    "dateDebut":                                    "date_debut_periode",
    "dateDernierTraitementEtablissement":           "date_maj",
    "activitePrincipaleEtablissement":              "code_naf",
    "nomenclatureActivitePrincipaleEtablissement":  "nomenclature_naf",
    "activitePrincipaleRegistreMetiersEtablissement": "code_rma",
    "trancheEffectifsEtablissement":                "tranche_effectifs",
    "anneeEffectifsEtablissement":                  "annee_effectifs",
    "caractereEmployeurEtablissement":              "est_employeur",
    "numeroVoieEtablissement":                      "num_voie",
    "typeVoieEtablissement":                        "type_voie",
    "libelleVoieEtablissement":                     "nom_voie",
    "codePostalEtablissement":                      "code_postal",
    "libelleCommuneEtablissement":                  "commune",
    "codeCommuneEtablissement":                     "code_commune",
    "denominationUsuelleEtablissement":             "nom_commercial",
    "enseigne1Etablissement":                       "enseigne",
}


def get_blob_service() -> BlobServiceClient:
    conn_str = (
        f"DefaultEndpointsProtocol=https;"
        f"AccountName={STORAGE_ACCOUNT};"
        f"AccountKey={STORAGE_KEY};"
        f"EndpointSuffix=core.windows.net"
    )
    return BlobServiceClient.from_connection_string(conn_str)


def download_parquet(service: BlobServiceClient) -> pa.Table:
    """Télécharge et filtre le fichier Parquet directement depuis ADLS."""
    print(f"[1/5] Téléchargement depuis {CONTAINER_RAW}/{BLOB_SOURCE} ...")
    blob_client = service.get_blob_client(
        container=CONTAINER_RAW, blob=BLOB_SOURCE
    )
    data = blob_client.download_blob().readall()

    # Lecture avec pyarrow — filtres appliqués dès la lecture (économise la RAM)
    filters = [
        ("etatAdministratifEtablissement", "=", "A"),
    ]
    table = pq.read_table(
        io.BytesIO(data),
        columns=COLONNES_ESSENTIELLES,
        filters=filters,
    )
    print(f"    -> {table.num_rows:,} lignes après filtre ACTIF")
    return table


def transform(table: pa.Table) -> pd.DataFrame:
    """Applique tous les filtres et enrichissements."""
    df = table.to_pandas()

    # Filtre Hauts-de-France
    print("[2/5] Filtre Hauts-de-France ...")
    df["_dept"] = df["codeCommuneEtablissement"].str[:2]
    df = df[df["_dept"].isin(DEPARTEMENTS_HDF)].copy()
    print(f"    -> {len(df):,} établissements en Hauts-de-France")

    # Suppression colonnes entièrement vides
    print("[3/5] Suppression colonnes vides ...")
    colonnes_vides = [c for c in df.columns if df[c].isna().all()]
    if colonnes_vides:
        df.drop(columns=colonnes_vides, inplace=True)
        print(f"    -> Supprimées : {colonnes_vides}")
    else:
        print("    -> Aucune colonne entièrement vide")

    # Enrichissement
    df["code_departement"] = df["_dept"]
    df["nom_departement"]  = df["_dept"].map(NOM_DEPARTEMENT)
    df["region"]           = "Hauts-de-France"
    df["date_traitement"]  = str(date.today())
    df.drop(columns=["_dept"], inplace=True)

    # Conversion dates
    for col in ["dateCreationEtablissement", "dateDebut",
                "dateDernierTraitementEtablissement"]:
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], errors="coerce").dt.date

    # Renommage
    df.rename(columns=RENOMMAGE, inplace=True)

    print(f"    -> {len(df.columns)} colonnes finales")
    return df


def upload_to_adls(df: pd.DataFrame, service: BlobServiceClient) -> None:
    """Upload le résultat partitionné par département dans la zone curated."""
    print("[4/5] Upload vers ADLS curated/ ...")

    for dept, group in df.groupby("code_departement"):
        buf = io.BytesIO()
        group.to_parquet(buf, engine="pyarrow", index=False)
        blob_name = f"{PREFIX_OUTPUT}/code_departement={dept}/data.parquet"
        client = service.get_blob_client(
            container=CONTAINER_CURATED, blob=blob_name
        )
        client.upload_blob(
            buf.getvalue(),
            overwrite=True,
            content_settings=ContentSettings(
                content_type="application/octet-stream"
            ),
        )
        print(f"    -> {CONTAINER_CURATED}/{blob_name} "
              f"({len(group):,} lignes)")

    print("[OK] Upload terminé.")


def verify(service: BlobServiceClient) -> None:
    """Liste les fichiers écrits dans curated/."""
    print("[5/5] Vérification dans ADLS curated/ ...")
    container = service.get_container_client(CONTAINER_CURATED)
    blobs = list(container.list_blobs(
        name_starts_with=f"{PREFIX_OUTPUT}/"
    ))
    for b in blobs:
        print(f"    {b.name}  ({b.size:,} bytes)")
    print(f"\n[OK] {len(blobs)} fichier(s) dans curated/{PREFIX_OUTPUT}/")


def main():
    if STORAGE_KEY == "<COLLE_ICI_TA_CLE>":
        raise SystemExit(
            "ERREUR : Configure STORAGE_KEY dans le script "
            "ou via la variable d'env ADLS_STORAGE_KEY"
        )

    service = get_blob_service()
    table   = download_parquet(service)
    df      = transform(table)
    upload_to_adls(df, service)
    verify(service)
    print("\n Pipeline ETL terminé avec succès.")
    print(f" Résultat : curated/{PREFIX_OUTPUT}/")


if __name__ == "__main__":
    main()
