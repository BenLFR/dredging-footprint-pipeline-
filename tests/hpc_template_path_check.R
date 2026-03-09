#!/usr/bin/env Rscript

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
  "config/templates/slurm/README.md",
  "config/templates/slurm/cluster_overrides.env.example",
  "config/templates/slurm/submit_step.sh"
)

for (p in required) {
  if (!file.exists(p)) stop(sprintf("Missing template file: %s", p))
}

submit <- paste(readLines("config/templates/slurm/submit_step.sh", warn = FALSE, encoding = "UTF-8"), collapse = "\n")
env <- paste(readLines("config/templates/slurm/cluster_overrides.env.example", warn = FALSE, encoding = "UTF-8"), collapse = "\n")

must_have_submit <- c("SBATCH_PARTITION", "SBATCH_ACCOUNT", "SBATCH_QOS", "sbatch")
for (needle in must_have_submit) {
  if (!grepl(needle, submit, fixed = TRUE)) {
    stop(sprintf("submit_step.sh missing token: %s", needle))
  }
}

must_have_env <- c("PIPELINE_DIR", "SCRATCH_DIR", "OUTPUT_DIR", "CONFIG_DIR", "LOGS_DIR")
for (needle in must_have_env) {
  if (!grepl(needle, env, fixed = TRUE)) {
    stop(sprintf("cluster_overrides.env.example missing token: %s", needle))
  }
}

blocked_tokens <- c("grit.ucsb.edu", "Beluga", "/home/bloe", "config_grit")
for (needle in blocked_tokens) {
  if (grepl(needle, submit, fixed = TRUE) || grepl(needle, env, fixed = TRUE)) {
    stop(sprintf("Cluster-specific hard-code found in templates: %s", needle))
  }
}

cat("[PASS] hpc_template_path_check.R\n")
