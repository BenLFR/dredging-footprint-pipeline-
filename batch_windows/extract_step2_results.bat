@echo off
REM =============================================================================
REM EXTRACTION DES RESULTATS STEP 2
REM =============================================================================
REM Telecharge les logs depuis GRIT et extrait les statistiques

echo ============================================================================
echo EXTRACTION DES STATISTIQUES STEP 2
echo ============================================================================
echo.

if "%1"=="" (
    echo Usage: extract_step2_results.bat ^<process_job_id^> [split_job_id]
    echo Exemple: extract_step2_results.bat 13289 12990
    exit /b 1
)

set PROCESS_JOB_ID=%1
set SPLIT_JOB_ID=%2

echo Process Job ID: %PROCESS_JOB_ID%
if not "%SPLIT_JOB_ID%"=="" (
    echo Split Job ID: %SPLIT_JOB_ID%
)
echo.

REM Creer le dossier logs s'il n'existe pas
if not exist "logs\" mkdir logs

REM Telecharger les logs depuis GRIT
echo ============================================================================
echo ETAPE 1: Telechargement des logs depuis GRIT
echo ============================================================================
echo.

scp -F "%USERPROFILE%/.ssh/config_grit" "grit:~/ais-pipeline/pipeline_V6/logs/step2_process_%PROCESS_JOB_ID%_*.out" "logs/"

if errorlevel 1 (
    echo.
    echo [ERREUR] Echec du telechargement des logs
    echo Verifiez:
    echo   1. Votre connexion SSH a GRIT
    echo   2. Que le Job ID est correct
    echo   3. Que les logs existent sur GRIT
    pause
    exit /b 1
)

echo.
echo [OK] Logs telecharges avec succes
echo.

REM Extraire les statistiques
echo ============================================================================
echo ETAPE 2: Extraction des statistiques
echo ============================================================================
echo.

if not "%SPLIT_JOB_ID%"=="" (
    Rscript scripts_principaux/extract_step2_stats.R %PROCESS_JOB_ID% %SPLIT_JOB_ID%
) else (
    Rscript scripts_principaux/extract_step2_stats.R %PROCESS_JOB_ID%
)

if errorlevel 1 (
    echo.
    echo [ERREUR] Echec de l'extraction des statistiques
    pause
    exit /b 1
)

echo.
echo ============================================================================
echo EXTRACTION TERMINEE
echo ============================================================================
echo.
echo Fichiers generes:
echo   - step2_statistics_%PROCESS_JOB_ID%.csv
echo.
pause
