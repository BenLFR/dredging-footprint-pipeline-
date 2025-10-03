#!/bin/bash
# Installation package fst manquant

echo "🔧 Installation package fst..."
module load StdEnv/2020 gcc/9.3.0 r/4.2.1
export R_LIBS=~/.local/R/4.2.1/

R --slave -e "
cat('📦 Installation fst...\n')
install.packages('fst', repos='https://cran.r-project.org', lib='~/.local/R/4.2.1/')
cat('✅ Installation terminée\n')

# Test
library(fst, lib.loc='~/.local/R/4.2.1/')
cat('✅ Package fst chargé avec succès\n')
" 