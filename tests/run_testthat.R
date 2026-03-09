#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(testthat))

get_script_path <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- "--file="
  hit <- grep(paste0("^", file_arg), args, value = TRUE)
  if (!length(hit)) stop("Unable to resolve script path from commandArgs().")
  normalizePath(sub(file_arg, "", hit[[1]]), winslash = "/", mustWork = TRUE)
}

script_dir <- dirname(get_script_path())
repo_root <- normalizePath(file.path(script_dir, ".."), winslash = "/", mustWork = TRUE)
setwd(repo_root)

cat("[INFO] Running testthat suite in tests/testthat/\n")
test_dir("tests/testthat", reporter = StopReporter$new())
cat("[PASS] testthat suite\n")
