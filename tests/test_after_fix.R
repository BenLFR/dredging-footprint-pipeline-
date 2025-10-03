# Test packages R après correction
# ===================================

cat("🧪 TEST PACKAGES R APRÈS CORRECTION\n")
cat("===================================\n")

# Configuration library
.libPaths("~/R/library")
cat("Library path:", .libPaths()[1], "\n")

# Test chargement packages essentiels
packages_test <- c("data.table", "lubridate", "mclust", "pROC", "dplyr")

cat("\n📦 Test chargement packages:\n")
for (pkg in packages_test) {
  tryCatch({
    library(pkg, character.only = TRUE)
    cat("✅", pkg, "- OK\n")
  }, error = function(e) {
    cat("❌", pkg, "- ERREUR:", e$message, "\n")
  })
}

# Test fonctionnalités de base
cat("\n🔬 Test fonctionnalités:\n")

# Test data.table
tryCatch({
  dt <- data.table(x = 1:5, y = letters[1:5])
  cat("✅ data.table - création OK\n")
}, error = function(e) {
  cat("❌ data.table - ERREUR:", e$message, "\n")
})

# Test mclust
tryCatch({
  set.seed(123)
  data_test <- rnorm(100)
  gmm <- Mclust(data_test, G = 2)
  cat("✅ mclust - GMM OK\n")
}, error = function(e) {
  cat("❌ mclust - ERREUR:", e$message, "\n")
})

# Test pROC
tryCatch({
  set.seed(123)
  response <- sample(0:1, 50, replace = TRUE)
  predictor <- rnorm(50)
  roc_obj <- roc(response, predictor, quiet = TRUE)
  cat("✅ pROC - AUC OK\n")
}, error = function(e) {
  cat("❌ pROC - ERREUR:", e$message, "\n")
})

cat("\n🎉 TESTS TERMINÉS\n")
cat("Si tous les packages sont OK, vous pouvez relancer vos analyses !\n") 