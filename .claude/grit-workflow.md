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
- Voir `scripts/deploy/SETUP.md` pour plus de détails

---

## Workflow de développement

### Principe
- **Local (Windows)** : Éditer et corriger le code
- **Cluster GRIT** : Exécuter le code (calculs R lourds)

### Scripts disponibles

#### 1. Synchroniser le code vers GRIT
```bash
bash scripts/deploy/sync_to_grit.sh
```
Envoie les fichiers nécessaires vers `~/dredging-database/` sur le cluster.

#### 2. Exécuter un script R sur GRIT
```bash
bash scripts/deploy/run_on_grit.sh "scripts/01_pipeline/01_create_master_IMO.R"
```

#### 3. Récupérer les résultats
```bash
bash scripts/deploy/fetch_results.sh
```
Télécharge les fichiers `results/` depuis le cluster.

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
~/dredging-database/
├── scripts/
│   ├── 00_setup/
│   ├── 01_pipeline/
│   └── deploy/
├── results/
├── data/
└── .claude/
```

---

## Commandes utiles

```bash
# Vérifier la connexion
ssh grit "hostname && whoami"

# Vérifier l'environnement R sur GRIT
ssh grit "Rscript --version"

# Session interactive
ssh grit

# Transférer un fichier unique
scp -F ~/.ssh/config_grit local_file.R grit:~/dredging-database/

# Transférer un dossier
scp -r -F ~/.ssh/config_grit results/ grit:~/dredging-database/
```

---

## Notes pour Claude

**Dans toutes les conversations futures** :
1. Lire ce fichier pour comprendre le workflow
2. Toujours éditer le code localement (ne pas créer de nouveaux fichiers sur GRIT)
3. Utiliser les scripts de déploiement pour tester sur GRIT
4. Ne jamais partager de données sensibles P3/P4 dans les prompts
