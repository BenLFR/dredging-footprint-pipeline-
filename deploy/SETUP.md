# Configuration SSH Agent - GRIT

## ✅ Configuration automatique activée

Vous n'avez **plus rien à faire** ! 🎉

## Comment ça marche ?

### À chaque ouverture de Git Bash :

1. Le script `~/.ssh/ssh-agent-auto.sh` démarre automatiquement
2. Une fenêtre vous demandera la passphrase **une seule fois**
3. Toutes les connexions SSH suivantes se feront sans redemander la passphrase

### Fichiers créés :

```
~/.bashrc                      # Configuration Git Bash (appelle le script SSH)
~/.ssh/ssh-agent-auto.sh       # Script de démarrage automatique de ssh-agent
~/.ssh/agent-env               # Informations sur l'agent en cours
```

## 🔧 Commandes utiles

### Vérifier que l'agent fonctionne :
```bash
ssh-add -l
```
Devrait afficher : `256 SHA256:... loeff@SpectreBen (ED25519)`

### Ajouter manuellement la clé (si besoin) :
```bash
ssh-add ~/.ssh/id_ed25519_new
```

### Tuer l'agent (redémarrage) :
```bash
killall ssh-agent
# Puis fermer/rouvrir Git Bash
```

## 🚀 Workflow quotidien

1. **Ouvrir Git Bash** → Entrer passphrase (une seule fois)
2. **Travailler normalement** → Toutes les connexions SSH fonctionnent sans passphrase
3. **Fermer Git Bash** → L'agent s'arrête
4. **Rouvrir Git Bash** → Retaper la passphrase (une fois), etc.

## 🔒 Sécurité

- L'agent garde la clé **en mémoire** (pas sur le disque)
- L'agent s'arrête automatiquement quand vous fermez Git Bash
- La passphrase n'est jamais stockée nulle part

---

**Note** : Cette configuration fonctionne uniquement dans Git Bash. Si vous utilisez PowerShell ou CMD, vous devrez entrer la passphrase à chaque connexion (ou configurer Pageant pour Windows).
