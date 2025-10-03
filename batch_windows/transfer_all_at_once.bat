@echo off
echo === TRANSFERT GROUPÉ VERS BELUGA + INSTALLATION PACKAGES ===
echo.

REM Créer un fichier temporaire avec tous les fichiers à transférer
echo Préparation des fichiers...

REM Créer un répertoire temporaire
mkdir temp_transfer 2>nul

REM Copier tous les fichiers dans le répertoire temporaire
copy "Entrainement modele V5 tri années cluster_NO_SF.R" temp_transfer\
copy install_packages_beluga_fixed.R temp_transfer\
copy check_packages_status.R temp_transfer\
copy fix_packages_working.sh temp_transfer\
copy submit_beluga_robuste.sh temp_transfer\
copy test_beluga_corrections.R temp_transfer\
copy submit_test_corrections.sh temp_transfer\

echo 1. Transfert de tous les fichiers en une fois...
scp -r temp_transfer/* benl@beluga.alliancecan.ca:~/R_scripts/

echo 2. Nettoyage local...
rmdir /s /q temp_transfer

echo 3. Lancement installation packages R sur Beluga...
ssh benl@beluga.alliancecan.ca "cd ~/R_scripts && sbatch fix_packages_working.sh"

echo 4. Vérification jobs en cours...
ssh benl@beluga.alliancecan.ca "squeue -u benl"

echo.
echo === TRANSFERT ET INSTALLATION LANCÉS ===
echo.
echo Surveillance :
echo   - Vérifiez logs: ssh benl@beluga.alliancecan.ca "ls ~/R_scripts/logs/"
echo   - Status jobs: ssh benl@beluga.alliancecan.ca "squeue -u benl"
echo.
echo Une fois installation terminée, lancez les tests :
echo   ssh benl@beluga.alliancecan.ca "cd ~/R_scripts && sbatch submit_test_corrections.sh"
pause 