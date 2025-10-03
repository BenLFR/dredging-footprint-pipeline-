# Organisation du Dossier Beluga

Ce dossier a été organisé de manière logique pour faciliter la navigation et la maintenance du code. Voici la structure :

## 📁 Structure des Dossiers

### `scripts_principaux/`
Contient les scripts R principaux pour le traitement des données et l'entraînement des modèles :
- `01_preprocess_AIS_core.R` - Script de préprocessement principal des données AIS
- `02_add_lithology_to_AIS_cluster.R` - Ajout des données de lithologie aux clusters AIS
- `Entrainement modele V5 tri années.R` - Script d'entraînement du modèle V5
- `Entrainement modele V5 tri années cluster.R` - Version avec clustering
- `Entrainement modele V5 tri années cluster_NO_SF.R` - Version sans SF

### `tests/`
Scripts de test et validation :
- Tous les fichiers `test_*.R`
- Scripts de validation des corrections et fonctionnalités

### `installation/`
Scripts d'installation et vérification des packages R :
- `install_packages_*.R` - Scripts d'installation des packages
- `check_*.R` - Scripts de vérification des packages et prérequis

### `submission/`
Scripts de soumission sur le cluster Beluga :
- `submit_*.sh` - Différentes versions des scripts de soumission
- `check_before_submit.sh` - Vérifications avant soumission

### `maintenance/`
Scripts de correction et maintenance :
- `fix_*.sh` - Scripts de correction des problèmes

### `batch_windows/`
Scripts batch pour Windows :
- `*.bat` - Scripts de transfert et vérification pour Windows

### `documentation/`
Documentation et guides :
- `README_BELUGA.md` - Guide principal pour Beluga
- `GUIDE_DEMARRAGE_RAPIDE.md` - Guide de démarrage rapide
- `RESOLUTION_PROBLEME_R.md` - Guide de résolution des problèmes R
- `TESTS_VALIDATION.md` - Documentation des tests

### `configuration/`
Fichiers de configuration :
- `ssh*` - Configuration SSH pour Beluga
- `COMMANDES_FINALES.txt` - Commandes finales de référence

## 🚀 Utilisation

1. **Démarrage rapide** : Consultez `documentation/GUIDE_DEMARRAGE_RAPIDE.md`
2. **Installation** : Utilisez les scripts dans `installation/`
3. **Exécution** : Lancez les scripts principaux depuis `scripts_principaux/`
4. **Tests** : Validez avec les scripts dans `tests/`
5. **Soumission** : Utilisez les scripts dans `submission/`

## 📋 Ordre d'Exécution Recommandé

1. Installation des packages (`installation/`)
2. Tests de validation (`tests/`)
3. Préprocessement des données (`scripts_principaux/01_preprocess_AIS_core.R`)
4. Ajout de lithologie (`scripts_principaux/02_add_lithology_to_AIS_cluster.R`)
5. Entraînement du modèle (`scripts_principaux/Entrainement modele V5...`)
6. Soumission sur Beluga (`submission/`)

Cette organisation permet une meilleure maintenance et compréhension du projet. 