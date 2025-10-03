# ==============================================================================
# Script de test pour vérifier l'environnement R
# ==============================================================================

cat("Test de l'environnement R...\n")

# Test 1: Vérification des packages de base
tryCatch({
  library(data.table)
  cat("✓ data.table OK\n")
}, error = function(e) {
  cat("✗ Erreur data.table:", e$message, "\n")
})

# Test 2: Vérification du répertoire de travail
cat("Répertoire de travail:", getwd(), "\n")

# Test 3: Vérification de l'accès aux fichiers
ais_directory <- "C:/Users/loeff/OneDrive/Bureau/Master thesis/Datasets/AIS Tracks/Track data"
if (dir.exists(ais_directory)) {
  files <- list.files(ais_directory, pattern = "\\.csv$")
  cat("✓ Répertoire AIS trouvé avec", length(files), "fichiers CSV\n")
} else {
  cat("✗ Répertoire AIS non trouvé:", ais_directory, "\n")
}

# Test 4: Test de création de répertoire de sortie
out_dir <- "C:/Users/loeff/OneDrive/Bureau/Master thesis/Datasets/AIS Tracks/R code/Beluga/output"
tryCatch({
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  cat("✓ Répertoire de sortie créé/vérifié\n")
}, error = function(e) {
  cat("✗ Erreur création répertoire:", e$message, "\n")
})

# Test 5: Test simple de data.table
tryCatch({
  dt <- data.table(x = 1:5, y = letters[1:5])
  cat("✓ Test data.table réussi\n")
}, error = function(e) {
  cat("✗ Erreur test data.table:", e$message, "\n")
})

cat("\nTest terminé. Si tous les tests sont OK (✓), vous pouvez exécuter le script principal.\n")

# ==============================================================================
# Script de test pour vérifier les fonctions de débogage
# ==============================================================================

# Test des fonctions de débogage
cat("Test des fonctions de débogage...\n")

# Définition des fonctions (comme dans le script principal)
dbg_head <- function(msg) {
  cat(sprintf("[%s] %s\n", Sys.time(), msg))
  flush.console()
}

dbg_mem_mb <- function() {
  round(sum(gc()[,2]) * 8 / 1024, 1)  # Approximation en Mo
}

dbg_time <- function() {
  format(Sys.time(), "%H:%M:%S")
}

# Test des fonctions
dbg_head("Test de la fonction dbg_head")
cat("Mémoire utilisée:", dbg_mem_mb(), "Mo\n")
cat("Heure actuelle:", dbg_time(), "\n")

cat("✓ Toutes les fonctions de débogage fonctionnent correctement\n") 