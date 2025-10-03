@echo off
echo 🚀 Lancement automatique du script sur Beluga...
echo.

rem Se connecter et lancer le script directement
ssh benl@beluga.alliancecan.ca "scancel -u benl && cd ~/R_scripts && module load r/4.5.0 && echo '✅ Module R chargé' && Rscript 'Entrainement modele V5 tri années cluster_NO_SF.R'"

echo.
echo ✅ Script terminé
pause 