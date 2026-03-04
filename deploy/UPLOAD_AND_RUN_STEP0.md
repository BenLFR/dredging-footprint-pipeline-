# Guide Complet : Upload des Données et Lancement de Step 0 Enhanced

## 📋 Prérequis

Fichier à uploader : **benjamin3.csv** (1.4 GB)
- Localisation : `C:\Users\loeff\OneDrive\Bureau\Master thesis\Datasets\AIS Tracks\R code\Beluga\ORGANISATION_BELUGA\DATA_CLEANING\benjamin3.csv`

---

## Étape 1 : Upload du Fichier AIS vers GRIT

### Option A : Upload Direct (Recommandé)

Ouvrez **Git Bash** et exécutez :

```bash
# 1. Naviguer vers le dossier contenant benjamin3.csv
cd "/c/Users/loeff/OneDrive/Bureau/Master thesis/Datasets/AIS Tracks/R code/Beluga/ORGANISATION_BELUGA/DATA_CLEANING"

# 2. Upload vers GRIT (cela prendra 5-15 minutes)
scp -F ~/.ssh/config_grit benjamin3.csv grit:~/scratch/AIS_data/benjamin3_clean.csv
```

**Temps estimé** : 5-15 minutes selon votre connexion

### Option B : Upload avec Compression (Plus Rapide)

Si l'option A est trop lente, compressez d'abord :

```bash
# 1. Compresser le fichier (réduit la taille de ~70%)
gzip -c benjamin3.csv > benjamin3.csv.gz

# 2. Uploader le fichier compressé (plus rapide)
scp -F ~/.ssh/config_grit benjamin3.csv.gz grit:~/scratch/AIS_data/

# 3. Se connecter à GRIT et décompresser
ssh -F ~/.ssh/config_grit grit
cd ~/scratch/AIS_data
gunzip benjamin3.csv.gz
mv benjamin3.csv benjamin3_clean.csv
exit
```

---

## Étape 2 : Vérifier que Tout est Prêt

```bash
# Vérifier les fichiers sur GRIT
ssh -F ~/.ssh/config_grit grit "ls -lh ~/scratch/AIS_data/ && ls -lh ~/ais-pipeline/pipeline_V6/step0*"
```

**Vous devriez voir :**
```
~/scratch/AIS_data/:
-rw-r--r-- 1 bloe emlab 1.4G Jan  8 XX:XX benjamin3_clean.csv

~/ais-pipeline/pipeline_V6/:
-rw-r--r-- 1 bloe emlab 13K Jan  8 XX:XX step0_core_window_enhanced.R
-rw-r--r-- 1 bloe emlab 1.8K Jan  8 XX:XX step0_window_select_grit.sh
```

---

## Étape 3 : Installer les Packages R sur GRIT (Une seule fois)

```bash
# 1. Se connecter à GRIT
ssh -F ~/.ssh/config_grit grit

# 2. Charger R
module load R

# 3. Créer le répertoire de librairies
mkdir -p ~/R/library
export R_LIBS_USER=~/R/library

# 4. Lancer R
R
```

**Dans R**, exécutez :
```r
# Configurer le chemin de la librairie
.libPaths("~/R/library")

# Installer les packages nécessaires pour Step 0
packages <- c('data.table', 'lubridate', 'matrixStats', 'digest', 'yaml')
install.packages(packages, repos='https://cloud.r-project.org/')

# Vérifier l'installation
for(pkg in packages) {
  if(require(pkg, character.only=TRUE, quietly=TRUE)) {
    cat('✅', pkg, 'OK\n')
  } else {
    cat('❌', pkg, 'FAILED\n')
  }
}

# Quitter R
quit()
```

---

## Étape 4 : Lancer Step 0 Enhanced

### Méthode 1 : Via SLURM (Recommandé)

```bash
# Se connecter à GRIT (si pas déjà connecté)
ssh -F ~/.ssh/config_grit grit

# Naviguer vers le répertoire du pipeline
cd ~/ais-pipeline/pipeline_V6

# Soumettre le job Step 0
sbatch step0_window_select_grit.sh

# Noter le JOB_ID retourné (exemple: "Submitted batch job 123456")
```

### Surveiller l'Exécution

```bash
# Vérifier le statut du job
squeue -u bloe

# Suivre les logs en temps réel (remplacer JOBID)
tail -f ~/ais-pipeline/logs/step0_window_enhanced_JOBID.out

# En cas d'erreur, vérifier les erreurs
tail -f ~/ais-pipeline/logs/step0_window_enhanced_JOBID.err
```

### Méthode 2 : Exécution Interactive (Pour Debug)

```bash
# Se connecter à GRIT
ssh -F ~/.ssh/config_grit grit

# Charger R et configurer l'environnement
module load R
export R_LIBS_USER=~/R/library

# Naviguer vers le pipeline
cd ~/ais-pipeline/pipeline_V6

# Exécuter directement
Rscript step0_core_window_enhanced.R
```

---

## Étape 5 : Récupérer les Résultats

Une fois Step 0 terminé (environ 20-30 minutes), récupérez les résultats :

```bash
# Depuis votre machine Windows (Git Bash)
cd "/c/Users/loeff/OneDrive/Bureau/Master thesis/Datasets/AIS Tracks/R code/Beluga"

# Récupérer tous les résultats Step 0
bash deploy/fetch_results.sh output_V6
```

**Ou manuellement :**
```bash
# Créer le dossier local si nécessaire
mkdir -p output_V6

# Récupérer les fichiers
scp -F ~/.ssh/config_grit -r grit:~/scratch/output_V6/* ./output_V6/
```

---

## Fichiers de Sortie Attendus

Après Step 0 Enhanced, vous devriez avoir dans `output_V6/` :

```
output_V6/
├── coverage_matrix.csv          # Matrice navire × année
├── all_windows_analysis.csv     # Analyse complète des fenêtres
├── top_20_windows.csv           # Top 20 meilleures fenêtres
├── annual_statistics.csv        # Statistiques annuelles
├── core_window_report.md        # Rapport compréhensif
└── plots/                       # Visualisations (si générées)
```

---

## Vérification Rapide

```bash
# Sur GRIT, vérifier que les résultats existent
ssh -F ~/.ssh/config_grit grit "ls -lh ~/scratch/output_V6/*.csv ~/scratch/output_V6/*.md"

# Afficher les 10 meilleures fenêtres
ssh -F ~/.ssh/config_grit grit "head -n 11 ~/scratch/output_V6/top_20_windows.csv"
```

---

## Dépannage

### Problème : "Connection closed" pendant l'upload
**Solution** : Utilisez l'option B (compression) ou rsync :
```bash
rsync -avz --progress -e "ssh -F ~/.ssh/config_grit" benjamin3.csv grit:~/scratch/AIS_data/benjamin3_clean.csv
```

### Problème : "Package not found" dans R
**Solution** : Vérifier que R_LIBS_USER est bien configuré :
```bash
ssh -F ~/.ssh/config_grit grit
echo $R_LIBS_USER
# Devrait afficher: /home/bloe/R/library
```

### Problème : Job SLURM ne démarre pas
**Solution** : Vérifier la file d'attente et les quotas :
```bash
squeue -u bloe        # Voir vos jobs
sinfo                 # Voir les nœuds disponibles
```

### Problème : "No CSV files found" dans Step 0
**Solution** : Vérifier que le fichier est au bon endroit :
```bash
ssh -F ~/.ssh/config_grit grit "ls -lh ~/scratch/AIS_data/benjamin3_clean.csv"
```

---

## Temps Estimés

| Étape | Durée |
|-------|-------|
| Upload benjamin3.csv | 5-15 min |
| Installation packages R | 10-15 min |
| Exécution Step 0 Enhanced | 20-30 min |
| Téléchargement résultats | 1-2 min |
| **TOTAL** | **~40-65 min** |

---

## Commandes Résumées

```bash
# 1. Upload des données
cd "/c/Users/loeff/OneDrive/Bureau/Master thesis/Datasets/AIS Tracks/R code/Beluga/ORGANISATION_BELUGA/DATA_CLEANING"
scp -F ~/.ssh/config_grit benjamin3.csv grit:~/scratch/AIS_data/benjamin3_clean.csv

# 2. Lancer Step 0
ssh -F ~/.ssh/config_grit grit
cd ~/ais-pipeline/pipeline_V6
sbatch step0_window_select_grit.sh

# 3. Surveiller
squeue -u bloe
tail -f logs/step0_window_enhanced_*.out

# 4. Récupérer les résultats
# (depuis Windows Git Bash)
cd "/c/Users/loeff/OneDrive/Bureau/Master thesis/Datasets/AIS Tracks/R code/Beluga"
bash deploy/fetch_results.sh output_V6
```
