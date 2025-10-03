@echo off
REM ==============================================================================
REM Script de transfert automatique vers Beluga
REM ==============================================================================

echo === TRANSFERT VERS BELUGA ===
echo.

REM Configuration - MODIFIEZ CES VALEURS
set USERNAME=benl
set BELUGA_HOST=beluga.alliancecan.ca
set PROJECT_DIR=def-benl

echo Configuration:
echo   Utilisateur: %USERNAME%
echo   Serveur: %BELUGA_HOST%
echo   Projet: %PROJECT_DIR%
echo.

REM Vérification de la connexion
echo 1. Test de connexion...
ssh %USERNAME%@%BELUGA_HOST% "echo 'Connexion OK'" 2>nul
if errorlevel 1 (
    echo ERREUR: Impossible de se connecter à Beluga
    echo Vérifiez votre nom d'utilisateur et votre connexion SSH
    pause
    exit /b 1
)
echo ✓ Connexion réussie
echo.

REM Création des répertoires sur Beluga
echo 2. Création des répertoires sur Beluga...
ssh %USERNAME%@%BELUGA_HOST% "mkdir -p ~/projects/%PROJECT_DIR%/%USERNAME%/R_scripts"
ssh %USERNAME%@%BELUGA_HOST% "mkdir -p ~/scratch/AIS_data"
ssh %USERNAME%@%BELUGA_HOST% "mkdir -p ~/scratch/output"
echo ✓ Répertoires créés
echo.

REM Transfert des scripts R
echo 3. Transfert des scripts R...
scp "Entrainement modele V5 tri années cluster.R" %USERNAME%@%BELUGA_HOST%:~/projects/%PROJECT_DIR%/%USERNAME%/R_scripts/
if errorlevel 1 goto :error

scp install_packages_beluga.R %USERNAME%@%BELUGA_HOST%:~/projects/%PROJECT_DIR%/%USERNAME%/R_scripts/
if errorlevel 1 goto :error

scp submit_beluga.sh %USERNAME%@%BELUGA_HOST%:~/projects/%PROJECT_DIR%/%USERNAME%/R_scripts/
if errorlevel 1 goto :error

scp check_before_submit.sh %USERNAME%@%BELUGA_HOST%:~/projects/%PROJECT_DIR%/%USERNAME%/R_scripts/
if errorlevel 1 goto :error

scp README_BELUGA.md %USERNAME%@%BELUGA_HOST%:~/projects/%PROJECT_DIR%/%USERNAME%/R_scripts/
if errorlevel 1 goto :error

echo ✓ Scripts R transférés
echo.

REM Transfert des données AIS
echo 4. Transfert des données AIS...
echo    Cela peut prendre du temps selon la taille de vos données...
set DATA_DIR=C:\Users\loeff\OneDrive\Bureau\Master thesis\Datasets\AIS Tracks\Track data
scp "%DATA_DIR%\*.csv" %USERNAME%@%BELUGA_HOST%:~/scratch/AIS_data/
if errorlevel 1 (
    echo ATTENTION: Erreur lors du transfert des données
    echo Vérifiez le chemin: %DATA_DIR%
    echo Vous pouvez transférer manuellement avec:
    echo scp "chemin\vers\vos\données\*.csv" %USERNAME%@%BELUGA_HOST%:~/scratch/AIS_data/
) else (
    echo ✓ Données AIS transférées
)
echo.

REM Rendre les scripts exécutables
echo 5. Configuration des permissions...
ssh %USERNAME%@%BELUGA_HOST% "chmod +x ~/projects/%PROJECT_DIR%/%USERNAME%/R_scripts/*.sh"
echo ✓ Permissions configurées
echo.

REM Instructions finales
echo === TRANSFERT TERMINÉ ===
echo.
echo Prochaines étapes sur Beluga:
echo   1. Connectez-vous: ssh %USERNAME%@%BELUGA_HOST%
echo   2. Allez dans le répertoire: cd ~/projects/%PROJECT_DIR%/%USERNAME%/R_scripts/
echo   3. Modifiez submit_beluga.sh avec vos informations
echo   4. Installez les packages: Rscript install_packages_beluga.R
echo   5. Vérifiez la configuration: ./check_before_submit.sh
echo   6. Soumettez le job: sbatch submit_beluga.sh
echo.
pause
exit /b 0

:error
echo ERREUR lors du transfert
pause
exit /b 1 