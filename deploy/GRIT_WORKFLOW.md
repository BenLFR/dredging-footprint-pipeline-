# GRIT UCSB Cluster Workflow

## Configuration SSH

**Username**: `bloe`
**Clé SSH**: `~/.ssh/id_ed25519_new`
**Architecture**: Connexion via ProxyJump (bastion → HPC)

### Hosts configurés

```bash
# Connexion rapide au cluster HPC
ssh grit

# Ou explicitement
ssh grit-hpc

# Bastion (rarement utilisé directement)
ssh grit-bastion
```

**Fichier de config**: `~/.ssh/config_grit`
Pour utiliser : `ssh -F ~/.ssh/config_grit grit`

### Authentification automatique (ssh-agent)

**✅ Configuration automatique activée**

À chaque ouverture de Git Bash :
1. `ssh-agent` démarre automatiquement
2. Vous entrez la passphrase **une seule fois**
3. Toutes les connexions SSH suivantes fonctionnent sans redemander la passphrase

**Fichiers** :
- `~/.bashrc` : Configuration Git Bash
- `~/.ssh/ssh-agent-auto.sh` : Script de démarrage automatique
- Voir `SETUP.md` pour plus de détails

---

## Workflow de développement

### Principe
- **Local (Windows)** : Éditer et corriger le code
- **Cluster GRIT** : Exécuter le code (calculs R lourds)

### Scripts disponibles

#### 1. Synchroniser le code vers GRIT
```bash
bash deploy/sync_to_grit.sh
```
Envoie les fichiers nécessaires vers `~/ais-pipeline/` sur le cluster.

Synchronise automatiquement:
- `scripts_principaux/` → Scripts R d'entraînement et analyse
- `configuration/` → Configuration YAML, INI, specs navires
- `submission/` → Scripts de soumission de jobs

#### 2. Exécuter un script R sur GRIT
```bash
# Script d'entraînement V6
bash deploy/run_on_grit.sh "scripts_principaux/Entrainement_modele_V6_seuil_adaptatif.R"

# Autres scripts
bash deploy/run_on_grit.sh "scripts_principaux/global_dredging_footprint.R"
bash deploy/run_on_grit.sh "scripts_principaux/heatmap_dragage.R"
```

#### 3. Récupérer les résultats
```bash
# Tout récupérer
bash deploy/fetch_results.sh

# Récupérer un dossier spécifique
bash deploy/fetch_results.sh Resultats
bash deploy/fetch_results.sh output_V6
bash deploy/fetch_results.sh outputs_step6
```

---

## Politiques GRIT & Usage de Claude

### ✅ Autorisé
- Utiliser Claude/Codex pour coder, débugger, documenter
- Partager du code non-sensible (scripts R publics, analyses statistiques)
- Usage dans le cadre de la recherche universitaire

### ❌ Interdit
- **Données P3/P4** :
  - PII/PHI (données personnelles, santé)
  - FERPA (dossiers étudiants)
  - Export-controlled research
  - **Credentials** (mots de passe, clés API, tokens)

### Alternative pour données sensibles
Si besoin : utiliser `llm.grit.ucsb.edu` (LLM interne GRIT)

**Références**:
- [GRIT Docs](https://bookstack.grit.ucsb.edu)
- [UCSB IT Policies](https://policy.ucsb.edu)
- [Data Protection Levels](https://www.it.ucsb.edu/information-security/ucsb-data-classification)

---

## Structure du projet sur GRIT

```
~/ais-pipeline/
├── scripts_principaux/
│   ├── Entrainement_modele_V6_seuil_adaptatif.R
│   ├── global_dredging_footprint.R
│   ├── heatmap_dragage.R
│   └── ...
├── configuration/
│   ├── outlier_config_V6.yaml
│   ├── constants V2.ini
│   ├── ship_specs.yaml
│   └── ...
├── submission/
│   └── submit_beluga_FINAL.sh (peut être adapté pour GRIT)
├── Resultats/
├── output_V6/
└── outputs_step6/
```

---

## Commandes utiles

```bash
# Vérifier la connexion
ssh -F ~/.ssh/config_grit grit "hostname && whoami"

# Vérifier l'environnement R sur GRIT
ssh -F ~/.ssh/config_grit grit "Rscript --version"

# Session interactive
ssh -F ~/.ssh/config_grit grit

# Transférer un fichier unique
scp -F ~/.ssh/config_grit local_file.R grit:~/ais-pipeline/

# Transférer un dossier
scp -r -F ~/.ssh/config_grit Resultats/ grit:~/ais-pipeline/
```

---

## Configuration R sur GRIT

### Installation des packages nécessaires

```bash
# Connexion à GRIT
ssh -F ~/.ssh/config_grit grit

# Charger R (vérifier la version disponible)
module load R

# Créer répertoire de librairies personnelles
mkdir -p ~/R/library

# Installer les packages
R
```

Dans R:
```r
# Configurer le chemin de la librairie
.libPaths("~/R/library")

# Installer les packages nécessaires
packages <- c(
  'data.table', 'lubridate', 'mclust', 'caret', 'pROC',
  'ggplot2', 'zoo', 'pbapply', 'matrixStats', 'outliers',
  'dbscan', 'dplyr', 'depmixS4', 'geosphere', 'yaml',
  'sf', 'terra', 'rnaturalearth', 'rnaturalearthdata'
)

install.packages(packages, repos='https://cloud.r-project.org/')

# Vérifier l'installation
for(pkg in packages) {
  if(require(pkg, character.only=TRUE, quietly=TRUE)) {
    cat('✅', pkg, 'OK\n')
  } else {
    cat('❌', pkg, 'FAILED\n')
  }
}
```

### Configuration automatique dans ~/.bashrc

Ajouter à votre `~/.bashrc` sur GRIT:
```bash
# Configuration R
export R_LIBS_USER=~/R/library
alias r_setup='module load R && export R_LIBS_USER=~/R/library'
```

---

## Exemples d'utilisation

### Workflow complet pour une analyse V6

```bash
# 1. Sur Windows - Modifier le script localement
# Éditer scripts_principaux/Entrainement_modele_V6_seuil_adaptatif.R

# 2. Synchroniser vers GRIT
bash deploy/sync_to_grit.sh

# 3. Exécuter sur GRIT
bash deploy/run_on_grit.sh "scripts_principaux/Entrainement_modele_V6_seuil_adaptatif.R"

# 4. Récupérer les résultats
bash deploy/fetch_results.sh output_V6
```

### Exécution manuelle sur GRIT (pour debugging)

```bash
# Connexion
ssh -F ~/.ssh/config_grit grit

# Configuration R
r_setup  # si vous avez créé l'alias

# Navigation
cd ~/ais-pipeline/scripts_principaux

# Exécution
Rscript Entrainement_modele_V6_seuil_adaptatif.R
```

### Soumission de job SLURM (si disponible sur GRIT)

```bash
# Créer un script de soumission (à adapter)
cd ~/ais-pipeline/submission
sbatch submit_grit.sh
```

---

## Transition depuis Beluga

### Principales différences

| Aspect | Beluga | GRIT |
|--------|--------|------|
| Username | `benl` | `bloe` |
| Hostname | `beluga.alliancecan.ca` | `hpc.grit.ucsb.edu` |
| Compte | `def-wailung` | À vérifier |
| Chemin projet | `~/R_scripts/` | `~/ais-pipeline/` |
| SSH Config | Direct | Via ProxyJump (bastion) |

### Migration des scripts

Les scripts SLURM de `submission/` peuvent nécessiter des ajustements:
- Changer le compte (`#SBATCH --account=...`)
- Vérifier les modules disponibles (`module avail`)
- Adapter les chemins de fichiers

---

## Dépannage

### Test de connexion
```bash
bash deploy/test_connection.sh
```

### Si ssh-agent ne fonctionne pas
```bash
# Vérifier l'agent
ssh-add -l

# Ajouter manuellement la clé
ssh-add ~/.ssh/id_ed25519_new
```

### Si la synchronisation échoue
```bash
# Vérifier la connexion
ssh -F ~/.ssh/config_grit grit "echo 'Connection OK'"

# Vérifier l'espace disque sur GRIT
ssh -F ~/.ssh/config_grit grit "df -h ~"

# Synchroniser avec plus de verbosité
rsync -avvz -e "ssh -F ~/.ssh/config_grit" scripts_principaux/ grit:~/ais-pipeline/scripts_principaux/
```

### Si R ne trouve pas les packages
```bash
# Sur GRIT
echo $R_LIBS_USER
ls -la ~/R/library

# Vérifier .libPaths() dans R
R --vanilla --slave -e ".libPaths()"
```

---

## Notes pour Claude

**Dans toutes les conversations futures** :
1. Lire ce fichier pour comprendre le workflow GRIT
2. Toujours éditer le code localement (ne pas créer de nouveaux fichiers sur GRIT directement)
3. Utiliser les scripts de déploiement pour tester sur GRIT
4. Ne jamais partager de données sensibles P3/P4 dans les prompts
5. Le projet utilise maintenant GRIT au lieu de Beluga
