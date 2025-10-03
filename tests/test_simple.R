# Test simple de base
cat("Test de base R\n")

# Test 1: Packages essentiels
tryCatch({
  library(data.table)
  cat("✅ data.table OK\n")
}, error = function(e) {
  cat("❌ data.table:", e$message, "\n")
})

tryCatch({
  library(mclust)
  cat("✅ mclust OK\n")
}, error = function(e) {
  cat("❌ mclust:", e$message, "\n")
})

# Test 2: Données de base
dt <- data.table(x = 1:10, y = rnorm(10))
cat("✅ data.table creation OK\n")

# Test 3: Feature engineering de base
dt[, z := x + y]
cat("✅ data.table operations OK\n")

cat("Test terminé\n") 