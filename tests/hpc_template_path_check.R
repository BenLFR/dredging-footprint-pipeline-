#!/usr/bin/env Rscript
# Verifies that deploy/ HPC scripts remain cluster-neutral.

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

required <- c(
  "deploy/hpc_submit.sh",
  "deploy/config.example.env",
  "deploy/hpc_sync.sh",
  "deploy/hpc_fetch.sh"
)

for (p in required) {
  if (!file.exists(p)) stop(sprintf("Missing deploy file: %s", p))
}

submit <- paste(readLines("deploy/hpc_submit.sh",       warn = FALSE, encoding = "UTF-8"), collapse = "\n")
env    <- paste(readLines("deploy/config.example.env",  warn = FALSE, encoding = "UTF-8"), collapse = "\n")

must_have_submit <- c("SLURM_PARTITION", "SLURM_ACCOUNT", "SLURM_QOS", "sbatch")
for (needle in must_have_submit) {
  if (!grepl(needle, submit, fixed = TRUE)) {
    stop(sprintf("deploy/hpc_submit.sh missing token: %s", needle))
  }
}

must_have_env <- c("HPC_BASEDIR", "HPC_SCRATCH", "REMOTE_LOG_DIR", "PIPELINE_DIR_REMOTE", "SLURM_PARTITION")
for (needle in must_have_env) {
  if (!grepl(needle, env, fixed = TRUE)) {
    stop(sprintf("deploy/config.example.env missing token: %s", needle))
  }
}

blocked_tokens <- c("grit.ucsb.edu", "Beluga", "/home/bloe", "config_grit")
for (needle in blocked_tokens) {
  if (grepl(needle, submit, fixed = TRUE) || grepl(needle, env, fixed = TRUE)) {
    stop(sprintf("Cluster-specific hard-code found in deploy/ templates: %s", needle))
  }
}

cat("[PASS] hpc_template_path_check.R\n")
