# Projet-Data-ENG

Infrastructure Terraform pour deployer un socle de stockage Azure compose d un compte Blob "landing", d un Data Lake Gen2, d un Key Vault et d un Data Factory. Le depot fournit egalement un mecanisme d upload local de fichiers CSV vers le conteneur landing.

## Apercu

- Resource group unique definissable (nom et region variables).
- Storage account Blob (HTTPS only, TLS1_2) destine a la zone landing.
- Storage account ADLS Gen2 (HNS active) avec filesystems `raw`, `staging`, `curated` par defaut.
- Azure Key Vault en mode Access Policies avec purge protection.
- Azure Data Factory avec identite managee system-assigned et acces lecture au Key Vault.
- Upload Terraform optionnel, limite aux fichiers CSV.

Un descriptif detaille figure dans `docs/architecture.md`.

## Prerequis

- Terraform 1.5+ (teste avec 1.6.x).
- Azure CLI 2.52+ et un compte habilite a creer les ressources.
- Acces au reseau sortant vers `login.microsoftonline.com` pour l authentification Azure.
- Python (facultatif) si vous souhaitez ajouter des scripts d ingestion plus tard (voir `requirements.txt`).

## Mise en route rapide

```bash
# depuis la racine du projet
cd Terraform
terraform init
terraform plan
terraform apply
```

Repondez `yes` pour appliquer les changements. Listez ensuite les sorties utiles via `terraform output`.

### Upload local (optionnel)

1. Placez vos fichiers CSV dans `uploads/landing/csv/` (dossier ignore par Git).
2. Dans `Terraform/terraform.tfvars`, positionnez:
   - `upload_files_enabled = true`
   - adaptez `upload_source_dir` et `upload_container_name` si besoin
3. Relancez `terraform apply`. Seuls les fichiers se terminant par `.csv` sont pris en compte.
4. Consultez `terraform output upload_file_count` pour confirmer le nombre de fichiers publies.

## Configuration

`Terraform/terraform.tfvars` contient un jeu de valeurs exemple (le fichier est ignore par Git). Adaptez notamment:

- `resource_group_name`
- `resource_group_location`
- `blob_storage_account_name`
- `datalake_storage_account_name`
- `key_vault_name`
- `data_factory_name`
- `kv_additional_reader_object_ids`
- Parametres d upload optionnel (`upload_files_enabled`, `upload_source_dir`, `upload_container_name`)

Les noms de comptes de stockage doivent etre uniques a l echelle Azure, en minuscules et 3 a 24 caracteres.

## Arborescence

```
Terraform/
  main.tf
  variables.tf
  providers.tf
  outputs.tf
  terraform.tfvars        # valeurs locales (ignorees)
docs/
  architecture.md
requirements.txt
.gitignore
README.md
```

> Astuce: creez un fichier `Terraform/terraform.tfvars.example` pour partager des valeurs d exemple sans exposer vos secrets.

## Nettoyage

Pour supprimer les ressources Azure creees:

```bash
cd Terraform
terraform destroy
```

## Depannage

- **Erreur Azure CLI SSL / proxy**: si `az login` echoue avec `Certificate verification failed`, importez le certificat racine du proxy d entreprise et initialisez `REQUESTS_CA_BUNDLE` (`setx REQUESTS_CA_BUNDLE C:\chemin\proxy.pem`).
- **Noms de comptes de stockage rejetes**: choisissez un nom unique conforme (lowercase, 3-24 caracteres).
- **Fichiers ignores lors de l upload**: verifier que `upload_files_enabled` est `true` et que l extension est bien `.csv`.

## Publier sur GitHub

1. Effacez les artefacts locaux (ex: `Terraform/.terraform/`, fichiers `.tfstate` si vous ne souhaitez pas les partager).
2. Initialisez le depot si necessaire:
   ```bash
   git init
   git add .
   git commit -m "Initial infrastructure"
   ```
3. Configurez le depot distant et poussez:
   ```bash
   git remote add origin https://github.com/<organisation>/projet-data-eng.git
   git push -u origin main
   ```

Pensez a maintenir `uploads/` hors du versionnement pour eviter de publier des donnees sensibles.

## Ressources complementaires

- Documentation detaillee: `docs/architecture.md`
- Terraform provider AzureRM: https://registry.terraform.io/providers/hashicorp/azurerm/latest
- Azure CLI: https://learn.microsoft.com/cli/azure
