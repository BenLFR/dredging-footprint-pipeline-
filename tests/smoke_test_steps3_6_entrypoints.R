#!/usr/bin/env Rscript

# Lightweight reproducibility smoke test for Steps 3-6 entrypoints.
# Goal: fail fast if canonical scripts are missing or syntactically invalid.

resolve_script <- function(label, candidates) {
  existing <- candidates[file.exists(candidates)]
  if (!length(existing)) {
    stop(
      sprintf(
        "[FAIL] %s: no candidate found.\nChecked:\n - %s",
        label, paste(candidates, collapse = "\n - ")
      )
    )
  }
  path <- existing[[1]]
  parse(file = path)
  cat(sprintf("[OK] %s -> %s\n", label, path))
  path
}

step3 <- resolve_script(
  "Step3 merge",
  c(
    "pipeline/step3_merge_final.R",
    "pipeline_V6/pipeline_V6/step3_merge_final.R"
  )
)

# Guard check requested by audit: t_seuil must be defined before n_min uses it.
step3_lines <- readLines(step3, warn = FALSE, encoding = "UTF-8")
t_seuil_idx <- grep("\\bt_seuil\\s*<-", step3_lines)
n_min_idx <- grep("n_min\\s*:=", step3_lines)
if (!length(t_seuil_idx)) {
  stop("[FAIL] Step3: `t_seuil <- ...` assignment not found.")
}
if (!length(n_min_idx)) {
  stop("[FAIL] Step3: `n_min := ...` expression not found.")
}
if (min(t_seuil_idx) > min(n_min_idx)) {
  stop("[FAIL] Step3: `t_seuil` is defined after `n_min` usage.")
}
cat("[OK] Step3: t_seuil guard logic detected in expected order.\n")

invisible(resolve_script(
  "Step4 lithology",
  c(
    "pipeline_V6/pipeline_V6/step4_add_lithology_vNext.R",
    "pipeline/step4_add_lithology.R"
  )
))

invisible(resolve_script(
  "Step5 merge",
  c(
    "pipeline_V6/step5_merge_tiles_optimized.R",
    "pipeline/step5_merge_tiles.R"
  )
))

invisible(resolve_script(
  "Step6 CRI",
  c(
    "ORGANISATION_BELUGA/pipeline_study/step6_cri/step6_calculate_cri_corrected.R",
    "pipeline/step6_calculate_cri.R"
  )
))

cat("[PASS] smoke_test_steps3_6_entrypoints.R\n")
