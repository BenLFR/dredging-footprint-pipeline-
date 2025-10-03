@echo off
echo ===== VERIFICATION ETAT INSTALLATION PACKAGES BELUGA =====
echo.

echo 1. Verification jobs installation en cours...
ssh benl@beluga.alliancecan.ca "squeue -u benl | grep -E '(JOBID|fix_packages_working)'"
echo.

echo 2. Verification logs installation packages...
ssh benl@beluga.alliancecan.ca "ls -la ~/R_scripts/logs/fix_packages_working_*.out 2>/dev/null || echo 'Log installation pas encore créé'"
echo.

echo 3. Affichage progression installation (dernières lignes)...
ssh benl@beluga.alliancecan.ca "ls -t ~/R_scripts/logs/fix_packages_working_*.out 2>/dev/null | head -1 | xargs tail -20 2>/dev/null || echo 'Installation en cours...'"
echo.

echo 4. Verification statut packages R...
ssh benl@beluga.alliancecan.ca "cd ~/R_scripts && module load StdEnv/2020 gcc/9.3.0 r/4.2.1 && timeout 30 Rscript check_packages_status.R 2>/dev/null || echo 'Packages pas encore installés'"
echo.

echo 5. Verification repertoire R_scripts...
ssh benl@beluga.alliancecan.ca "ls -la ~/R_scripts/ | grep -E '\.(R|sh)$'"

pause 