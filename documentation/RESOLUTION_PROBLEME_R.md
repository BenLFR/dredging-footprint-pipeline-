# 🚨 RÉSOLUTION PROBLÈME PACKAGES R BELUGA

## **PROBLÈME IDENTIFIÉ**

### Erreur observée :
```
Error: package or namespace load failed for 'data.table' in dyn.load(file, DLLpath = DLLpath, ...):
 unable to load shared object '/home/benl/R/library/data.table/libs/data_table.so':
  /cvmfs/soft.computecanada.ca/gentoo/2020/lib64/libc.so.6: version `GLIBC_2.33' not found 
  (required by /home/benl/R/library/data.table/libs/data_table.so)
Warning: package 'data.table' was built under R version 4.5.0
```

### **CAUSE :**
- **Packages installés** avec R 4.5.0 (version récente)
- **Module Beluga** utilise R 4.2.1 (version stable cluster)  
- **Incompatibilité binaire** des librairies compilées

---

## **SOLUTION ÉTAPE PAR ÉTAPE**

### **1. Nettoyage et réinstallation packages**

```bash
# Transférer scripts de correction
scp fix_r_packages.sh benl@beluga.computecanada.ca:~/R_scripts/
scp test_after_fix.R benl@beluga.computecanada.ca:~/R_scripts/
scp submit_test_fix.sh benl@beluga.computecanada.ca:~/R_scripts/

# Lancer correction
ssh benl@beluga.computecanada.ca "cd ~/R_scripts && sbatch fix_r_packages.sh"
```

### **2. Vérification correction**

```bash
# Attendre fin job (vérifier avec squeue)
ssh benl@beluga.computecanada.ca "squeue -u benl"

# Lancer test validation
ssh benl@beluga.computecanada.ca "cd ~/R_scripts && sbatch submit_test_fix.sh"

# Vérifier résultats
ssh benl@beluga.computecanada.ca "cat ~/R_scripts/logs/test_fix_*.out"
```

### **3. Relancer analyses**

Une fois les packages corrigés :

```bash
# Relancer tests validation
ssh benl@beluga.computecanada.ca "cd ~/R_scripts && sbatch submit_test_corrections.sh"

# Puis grid-search complet
ssh benl@beluga.computecanada.ca "cd ~/R_scripts && sbatch submit_beluga_robuste.sh"
```

---

## **VÉRIFICATIONS ATTENDUES**

### **Après fix_r_packages.sh :**
- ✅ Tous packages installés avec R 4.2.1
- ✅ Aucun warning de version
- ✅ Library path configuré : `~/R/library`

### **Après test_after_fix.R :**
```
✅ data.table - OK
✅ lubridate - OK  
✅ mclust - OK
✅ pROC - OK
✅ dplyr - OK
✅ data.table - création OK
✅ mclust - GMM OK
✅ pROC - AUC OK
🎉 PACKAGES R FONCTIONNELS !
```

---

## **PRÉVENTION FUTURE**

### **Toujours utiliser modules cohérents :**
```bash
module load StdEnv/2020 gcc/9.3.0 r/4.2.1  # Version stable Beluga
```

### **Éviter mélange versions :**
- Ne pas installer packages avec R 4.5.0 puis utiliser R 4.2.1
- Nettoyer `~/R/library` avant changement version
- Vérifier `R --version` avant installation

### **Configuration .Rprofile recommandée :**
```r
.libPaths("~/R/library")
options(repos = c(CRAN = "https://cloud.r-project.org"))
options(timeout = 300)
```

---

## **FICHIERS CRÉÉS**

- `fix_r_packages.sh` : Script SLURM nettoyage/réinstallation
- `test_after_fix.R` : Test validation packages
- `submit_test_fix.sh` : Job SLURM pour test
- `RESOLUTION_PROBLEME_R.md` : Ce guide

---

## **CONTACT SUPPORT**

Si problème persiste :
1. Vérifier logs détaillés dans `logs/fix_r_packages_*.out`
2. Tester manuellement : `ssh benl@beluga.computecanada.ca "module load r/4.2.1 && R --version"`
3. Contacter support Beluga si problème infrastructure 