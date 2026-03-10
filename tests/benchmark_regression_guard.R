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

cfg_path <- "config/runtime_thresholds.csv"
if (!file.exists(cfg_path)) {
  stop(sprintf("Missing benchmark config: %s", cfg_path))
}

cfg <- read.csv(cfg_path, stringsAsFactors = FALSE)
if (!nrow(cfg)) {
  stop("Benchmark config is empty.")
}

cat(sprintf("[INFO] Loaded %d benchmark threshold(s) from %s\n", nrow(cfg), cfg_path))

timed_run <- function(exec, args) {
  start <- proc.time()[["elapsed"]]
  out <- tryCatch(
    system2(exec, args = args, stdout = TRUE, stderr = TRUE),
    error = function(e) e
  )
  elapsed <- proc.time()[["elapsed"]] - start

  if (inherits(out, "error")) {
    return(list(status = 127L, elapsed = elapsed, output = conditionMessage(out)))
  }

  status <- attr(out, "status")
  if (is.null(status)) status <- 0L
  list(status = as.integer(status), elapsed = as.numeric(elapsed), output = out)
}

results <- vector("list", nrow(cfg))

for (i in seq_len(nrow(cfg))) {
  metric <- cfg$metric[[i]]
  exec <- cfg$exec[[i]]
  args <- trimws(cfg$args[[i]])
  args_vec <- if (nzchar(args)) strsplit(args, "[[:space:]]+")[[1]] else character()

  baseline <- as.numeric(cfg$baseline_sec[[i]])
  pct <- as.numeric(cfg$max_regression_pct[[i]])
  margin <- as.numeric(cfg$absolute_margin_sec[[i]])
  threshold <- baseline * (1 + pct / 100) + margin

  cat(sprintf("[INFO] Running benchmark metric '%s' -> %s %s\n", metric, exec, args))
  run <- timed_run(exec, args_vec)
  cat(sprintf("[INFO] %s elapsed: %.3fs (threshold: %.3fs)\n", metric, run$elapsed, threshold))

  if (run$status != 0L) {
    cat("[ERROR] Command output:\n")
    cat(paste(run$output, collapse = "\n"), "\n")
    stop(sprintf("Benchmark command failed for metric '%s' (exit code %d).", metric, run$status))
  }

  if (run$elapsed > threshold) {
    stop(
      sprintf(
        "Regression detected for metric '%s': elapsed %.3fs > threshold %.3fs",
        metric, run$elapsed, threshold
      )
    )
  }

  results[[i]] <- data.frame(
    metric = metric,
    elapsed_sec = run$elapsed,
    baseline_sec = baseline,
    threshold_sec = threshold,
    stringsAsFactors = FALSE
  )
}

res <- do.call(rbind, results)
print(res, row.names = FALSE)
cat("[PASS] benchmark regression guard\n")
