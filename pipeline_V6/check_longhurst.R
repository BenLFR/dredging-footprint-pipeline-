# check_longhurst.R
cat("--- Diagnostic du chemin Longhurst ---\n")

# Chemin cible du dossier
dir_path <- path.expand("~/scratch/configuration/longhurst")
cat("Chemin du dossier à vérifier :", dir_path, "\n")

# Est-ce que le dossier existe ?
dir_exists <- dir.exists(dir_path)
cat("Le dossier existe-t-il ? :", dir_exists, "\n\n")

if (dir_exists) {
    # Lister tous les fichiers dans le dossier
    cat("Contenu du dossier :\n")
    files <- list.files(dir_path, full.names = TRUE, recursive = TRUE)
    if (length(files) > 0) {
        print(files)
    } else {
        cat("Le dossier est vide.\n")
    }
    
    cat("\n--- Recherche du shapefile ---\n")
    # Chemin complet du shapefile attendu
    shp_path <- list.files(dir_path, pattern="\\.shp$", full.names=TRUE, recursive = TRUE)

    if (length(shp_path) > 0) {
        shp_to_check <- shp_path[1]
        cat("Shapefile trouvé :", shp_to_check, "\n")

        # Est-ce que le fichier .shp existe ?
        shp_exists <- file.exists(shp_to_check)
        cat("Le fichier .shp existe-t-il ? :", shp_exists, "\n")

    } else {
        cat("Aucun fichier .shp trouvé dans le dossier.\n")
    }
} else {
    cat("Le script ne peut pas continuer car le dossier n'est pas trouvé.\n")
}

cat("\n--- Fin du diagnostic ---\n")
