@echo off
echo ===== VERIFICATION PACKAGES SYSTEME BELUGA =====
echo.

echo 1. Verification modules R disponibles...
ssh benl@beluga.alliancecan.ca "module avail r 2>&1 | grep -E '(r/|R/)"

echo.
echo 2. Verification packages systeme avec R/4.2.1...
ssh benl@beluga.alliancecan.ca "module load StdEnv/2020 gcc/9.3.0 r/4.2.1 && R --slave -e 'installed.packages()[,1]' | grep -E '(data.table|mclust|pROC|lubridate)'"

echo.
echo 3. Test chargement packages systeme...
ssh benl@beluga.alliancecan.ca "module load StdEnv/2020 gcc/9.3.0 r/4.2.1 && R --slave -e 'library(data.table); library(mclust); library(pROC); cat(\"Packages systeme OK\n\")'"

pause 