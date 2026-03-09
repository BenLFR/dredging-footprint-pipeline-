repo_root <- normalizePath(file.path("..", ".."), winslash = "/", mustWork = TRUE)
repo_path <- function(...) file.path(repo_root, ...)

test_that("critical transparency and FAIR docs exist", {
  required <- c(
    "documentation/LIMITATIONS.md",
    "documentation/BENCHMARKING_PROTOCOL.md",
    "documentation/VALIDATION_PROTOCOL.md",
    "documentation/UNCERTAINTY_BUDGET.md",
    "documentation/RESULT_TRACEABILITY_MATRIX.md",
    "ARCHIVE_MANIFEST.yaml",
    "configuration/codemeta.json",
    "documentation/ZENODO_INTEGRATION_GUIDE.md"
  )
  for (path in required) {
    expect_true(file.exists(repo_path(path)), info = path)
  }
})

test_that("wrappers steps 3-7 point to LIMITATIONS.md", {
  wrappers <- c(
    "pipeline/step3_merge_final.sh",
    "pipeline/step4_add_lithology.sh",
    "pipeline/step5_merge_slurm.sh",
    "pipeline/step6_calculate_cri.sh",
    "pipeline/step7_export_jtrawl.sh"
  )
  for (path in wrappers) {
    txt <- paste(readLines(repo_path(path), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    expect_match(txt, "LIMITATIONS\\.md", info = path)
  }
})

test_that("AIS provenance wording is aligned with user source", {
  policy <- paste(readLines(repo_path("docs/data_policy.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  data_readme <- paste(readLines(repo_path("data/README.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  expect_false(grepl("Exact Earth", policy, ignore.case = TRUE))
  expect_false(grepl("Exact Earth", data_readme, ignore.case = TRUE))

  expect_true(grepl("Global Fishing Watch", policy, fixed = TRUE))
  expect_true(grepl("David Kroodsma", policy, fixed = TRUE))
  expect_true(grepl("Global Fishing Watch", data_readme, fixed = TRUE))
  expect_true(grepl("David Kroodsma", data_readme, fixed = TRUE))
})

test_that("step6 wrapper references canonical local script candidate", {
  txt <- paste(
    readLines(repo_path("pipeline/step6_calculate_cri.sh"), warn = FALSE, encoding = "UTF-8"),
    collapse = "\n"
  )
  expect_match(txt, "pipeline/step6_calculate_cri\\.R")
})

test_that("HPC template files remain cluster-neutral", {
  submit <- paste(
    readLines(repo_path("config/templates/slurm/submit_step.sh"), warn = FALSE, encoding = "UTF-8"),
    collapse = "\n"
  )
  env <- paste(
    readLines(repo_path("config/templates/slurm/cluster_overrides.env.example"), warn = FALSE, encoding = "UTF-8"),
    collapse = "\n"
  )

  expect_match(submit, "sbatch", fixed = TRUE)
  expect_match(submit, "SBATCH_PARTITION", fixed = TRUE)
  expect_match(env, "PIPELINE_DIR", fixed = TRUE)
  expect_false(grepl("grit\\.ucsb\\.edu", submit, ignore.case = TRUE))
  expect_false(grepl("Beluga", submit, ignore.case = TRUE))
  expect_false(grepl("config_grit", env, ignore.case = TRUE))
})
