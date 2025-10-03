# 🚀 GUIDE DE DÉMARRAGE RAPIDE - BELUGA

## ✅ ÉTAT ACTUEL
- ✅ Scripts transférés vers Beluga
- ✅ Données AIS transférées (12 fichiers CSV)
- ✅ 14/15 packages essentiels installés
- ❌ Package `sf` manquant (contourné avec version NO_SF)

## 🎯 PROCHAINES ÉTAPES (5 minutes)

### 1. Connexion à Beluga
```bash
ssh benl@beluga.alliancecan.ca
```

### 2. Aller dans le répertoire de travail
```bash
cd ~/R_scripts/
```

### 3. Vérifier les fichiers
```bash
ls -la
# Vous devriez voir :
# - Entrainement modele V5 tri années cluster_NO_SF.R
# - submit_beluga_NO_SF.sh
# - check_packages_status.R
```

### 4. Vérifier les packages (optionnel)
```bash
module load r/4.5.0
Rscript check_packages_status.R
```

### 5. Modifier le script SLURM
```bash
nano submit_beluga_NO_SF.sh
```
**Changements à faire :**
- Ligne 2 : Remplacer `def-benl` par votre vrai compte
- Ligne 10 : Remplacer `votre.email@example.com` par votre email

### 6. Rendre le script exécutable
```bash
chmod +x submit_beluga_NO_SF.sh
```

### 7. LANCER L'ANALYSE ! 🚀
```bash
sbatch submit_beluga_NO_SF.sh
```

### 8. Surveiller le job
```bash
# Voir le statut
squeue -u benl

# Voir les logs en temps réel
tail -f ais_training_no_sf_*.out
```

## 📊 RÉSULTATS ATTENDUS

**Durée estimée :** 2-4 heures  
**Fichiers de sortie dans `~/scratch/output/` :**
- `AIS_data_core_preprocessed.csv` (données traitées)
- `AIS_data_core_preprocessed.rds` (format R)
- `weights_dragage_score_opt.rds` (poids optimaux)

## 🔧 DÉPANNAGE RAPIDE

### Si le job échoue :
```bash
# Voir les erreurs
cat ais_training_no_sf_*.err

# Vérifier l'espace disque
df -h ~/scratch/
```

### Si problème de packages :
```bash
# Réinstaller
Rscript install_packages_beluga_fixed.R
```

## 📈 OPTIMISATIONS APPLIQUÉES

✅ **Script sans `sf`** - Contourne le problème d'installation  
✅ **Parallélisme automatique** - Utilise tous les cœurs alloués  
✅ **Gestion mémoire optimisée** - Évite les fuites mémoire  
✅ **Logs détaillés** - Suivi en temps réel  

## 🎉 APRÈS L'EXÉCUTION

### Récupérer les résultats :
```bash
# Depuis votre machine locale
scp benl@beluga.alliancecan.ca:~/scratch/output/* ./resultats_beluga/
```

---
**💡 Astuce :** Le script est maintenant optimisé et devrait fonctionner sans problème avec les 14 packages installés ! 