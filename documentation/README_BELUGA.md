# Guide d'exécution sur Beluga

## Étapes pour exécuter votre analyse AIS sur le supercalculateur Beluga

### 1. Connexion à Beluga
```bash
ssh votre_username@beluga.alliancecan.ca
```

### 2. Préparation des répertoires
```bash
# Créer les répertoires nécessaires
mkdir -p ~/scratch/AIS_data
mkdir -p ~/scratch/output
mkdir -p ~/projects/def-benl/votre_username/R_scripts
```

### 3. Transfert des fichiers

#### A. Transférer vos scripts R vers Beluga
```bash
# Depuis votre machine locale
scp "Entrainement modele V5 tri années cluster.R" votre_username@beluga.alliancecan.ca:~/projects/def-benl/votre_username/R_scripts/
scp install_packages_beluga.R votre_username@beluga.alliancecan.ca:~/projects/def-benl/votre_username/R_scripts/
scp submit_beluga.sh votre_username@beluga.alliancecan.ca:~/projects/def-benl/votre_username/R_scripts/
```

#### B. Transférer vos données AIS
```bash
# Transférer tous vos fichiers CSV de données AIS
scp "C:/Users/loeff/OneDrive/Bureau/Master thesis/Datasets/AIS Tracks/Track data"/*.csv votre_username@beluga.alliancecan.ca:~/scratch/AIS_data/
```

### 4. Installation des packages R (première fois seulement)
```bash
# Sur Beluga
cd ~/projects/def-benl/votre_username/R_scripts/
module load r/4.3.0
Rscript install_packages_beluga.R
```

### 5. Modification du script SLURM
Éditez le fichier `submit_beluga.sh` pour :
- Remplacer `def-benl` par votre compte de calcul
- Remplacer `votre.email@example.com` par votre vraie adresse email
- Ajuster le temps et les ressources si nécessaire

### 6. Soumission du job
```bash
cd ~/projects/def-benl/votre_username/R_scripts/
chmod +x submit_beluga.sh
sbatch submit_beluga.sh
```

### 7. Surveillance du job
```bash
# Vérifier le statut du job
squeue -u votre_username

# Voir les logs en temps réel
tail -f ais_training_JOBID.out
tail -f ais_training_JOBID.err
```

### 8. Récupération des résultats
```bash
# Vérifier les fichiers de sortie
ls -la ~/scratch/output/

# Transférer les résultats vers votre machine locale
scp votre_username@beluga.alliancecan.ca:~/scratch/output/* ./resultats_beluga/
```

## Configuration recommandée

### Ressources SLURM
- **CPUs**: 8 cœurs (ajustable selon la taille de vos données)
- **Mémoire**: 32 GB (augmentez si vous avez beaucoup de données)
- **Temps**: 4 heures (ajustez selon vos besoins)

### Structure des fichiers sur Beluga
```
~/projects/def-benl/votre_username/R_scripts/
├── Entrainement modele V5 tri années cluster.R
├── install_packages_beluga.R
├── submit_beluga.sh
└── README_BELUGA.md

~/scratch/AIS_data/
├── navire1.csv
├── navire2.csv
└── ...

~/scratch/output/
├── AIS_data_core_preprocessed.csv
├── AIS_data_core_preprocessed.rds
└── weights_dragage_score_opt.rds
```

## Dépannage

### Si le job échoue
1. Vérifiez les logs d'erreur : `cat ais_training_JOBID.err`
2. Vérifiez que vos données sont bien dans `~/scratch/AIS_data/`
3. Vérifiez que tous les packages sont installés
4. Augmentez la mémoire ou le temps si nécessaire

### Si les packages ne s'installent pas
```bash
# Essayez d'installer manuellement les packages problématiques
module load r/4.3.0
R
> install.packages("nom_du_package", dependencies = TRUE)
```

### Commandes utiles
```bash
# Annuler un job
scancel JOBID

# Voir l'utilisation des ressources
sacct -j JOBID --format=JobID,JobName,MaxRSS,Elapsed

# Voir les jobs en cours
squeue -u votre_username
```

## Notes importantes
- Utilisez toujours `~/scratch/` pour les données temporaires et les résultats
- Les fichiers dans `~/scratch/` sont supprimés après 60 jours d'inactivité
- Sauvegardez vos résultats importants dans `~/projects/`
- Le parallélisme est automatiquement configuré selon les ressources SLURM allouées 