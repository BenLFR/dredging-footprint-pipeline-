# Analysis Tests Concept Guide

This note explains, in plain language, what each analysis test is for.

The goal is not to restate code line by line. The goal is to answer the first
questions a reader usually has:

- What question does this test answer?
- Why would I run it?
- What does a strong result mean?
- What does this test *not* prove?

## Where these scripts live

In this repository, the local analysis scripts currently exist under
`scripts_principaux/analysis/`.

On the publication branch, the canonical public copies may live under
`analysis/`.

This guide is conceptual, so the purpose of each script is the same even if the
path differs by branch.

## The big picture

These tests fall into six families.

### 1. Benchmarking tests

Purpose:
compare the step 3 internal labelling scheme against simpler alternatives.

Core question:
"Does the pipeline behave differently from a crude speed rule?"

### 2. Sensitivity tests

Purpose:
find which parameters matter most in the `f_i` / `C_ri` formula.

Core question:
"Which assumptions move the result the most?"

### 3. Uncertainty tests

Purpose:
propagate uncertain assumptions through repeated simulations.

Core question:
"How wide is the plausible spread of results once uncertainty is admitted?"

### 4. Convergence tests

Purpose:
check whether stochastic analyses have stabilized numerically.

Core question:
"Did I run enough samples, or are the results still moving?"

### 5. Scenario-comparison tests

Purpose:
compare several saved outputs produced under different assumptions.

Core question:
"How much do totals and maps change between scenarios?"

### 6. Integrity tests

Purpose:
check internal coherence of formulas, files, and exported objects.

Core question:
"Is the object mathematically and structurally sane?"

## Recommended reading order

If your goal is understanding, this order is the most useful:

1. `check_fi_grid_consistency.R`
2. `extract_step3_auc_metrics.R`
3. `benchmark_vs_baseline.R`
4. `sensitivity_oat_analysis.R`
5. `plot_sensitivity_tornado.R`
6. `sensitivity_sobol.R`
7. `diagnose_sobol_convergence.R`
8. `monte_carlo_uncertainty.R`
9. `diagnose_monte_carlo_convergence.R`
10. `compare_scenarios.R`
11. `synthetic_validation.R`

Why this order:

- first understand whether a saved `fi_grid` is trustworthy
- then understand how step 3 performance is summarized
- then understand the internal benchmark against simple rules
- then move from simple sensitivity to global sensitivity
- then move from sensitivity to uncertainty
- finish with scenario comparison and formula-integrity checks

## Script-by-script guide

## `check_fi_grid_consistency.R`

Question answered:
"Is this `fi_grid` internally coherent?"

What it does:

- loads a saved `fi_grid`
- checks expected columns and structure
- checks whether saved values are consistent with the step 5 logic
- flags mismatches or suspicious patterns

Why it matters:

- you should not interpret a result before checking the object itself is sane
- this is the fastest sanity check before downstream analysis

What it does **not** prove:

- external scientific validity
- classifier quality
- uncertainty bounds

Plain-language meaning:
this is the "is the object broken?" test.

## `extract_step3_auc_metrics.R`

Question answered:
"What was the internal cross-validation performance of step 3?"

What it does:

- reads saved step 3 validation outputs
- extracts fold-level AUC metrics
- summarizes mean performance and spread

Why it matters:

- it gives the internal validation number for the classifier
- it helps distinguish internal model performance from downstream impact metrics

What it does **not** prove:

- external real-world accuracy
- end-to-end validity of the full dredging footprint pipeline

Plain-language meaning:
this is the "how well did step 3 score in its own validation protocol?" test.

## `benchmark_vs_baseline.R`

Question answered:
"How different is the step 3 internal labelling scheme from simple speed-based
rules?"

What it does:

- loads the step 3 output table
- uses the internal step 3 label as a reference
- compares it against simple rule-based alternatives such as a speed threshold
- reports precision, recall, F1, and simple discrimination summaries

Why it matters:

- it contextualizes the benefit of the step 3 workflow
- it shows whether the pipeline is doing more than a crude heuristic

What it does **not** prove:

- absolute classifier accuracy
- independent ground-truth validation
- that the internal reference is perfect

Important interpretation:
this is an internal discriminative comparison, not an external benchmark.

Plain-language meaning:
this is the "does the pipeline do better than a simple speed filter?" test.

## `sensitivity_oat_analysis.R`

Question answered:
"If I perturb one parameter at a time, how much does `C_ri` move?"

What it does:

- changes one parameter while holding the others fixed
- recomputes the resulting `C_ri`
- writes one row of one-at-a-time sensitivity output

Why it matters:

- it is the easiest way to see which assumptions have local leverage
- it gives a first ranking of influential parameters

What it does **not** prove:

- interaction effects between parameters
- full global sensitivity in the Sobol sense

Plain-language meaning:
this is the "turn one knob and see what happens" test.

## `plot_sensitivity_tornado.R`

Question answered:
"Which single-parameter perturbations produce the biggest changes?"

What it does:

- aggregates OAT outputs
- computes change relative to baseline
- draws a ranked tornado plot

Why it matters:

- it turns many OAT runs into one interpretable visual summary
- it makes the local ranking of assumptions immediately visible

What it does **not** prove:

- parameter interactions
- uncertainty intervals

Plain-language meaning:
this is the "show me the biggest one-knob effects" test.

## `sensitivity_sobol.R`

Question answered:
"When all parameters vary jointly, which ones explain most of the output
variance?"

What it does:

- samples multiple parameters jointly
- estimates first-order and total-effect Sobol indices
- ranks parameters by contribution to output variance

Why it matters:

- unlike OAT, it can account for variance contribution in a multi-parameter
  setting
- it is the main global sensitivity tool in this folder

What it does **not** prove:

- external validity of the formula
- that synthetic proxy settings perfectly represent the full global grid

Plain-language meaning:
this is the "which assumptions dominate once everything can vary together?"
test.

## `diagnose_sobol_convergence.R`

Question answered:
"Did I run enough Sobol samples for the ranking to stabilize?"

What it does:

- reruns the Sobol analysis for several sample sizes
- checks whether `S1` and `ST` values stabilize
- highlights whether ranking changes materially with more samples

Why it matters:

- a Sobol ranking is not trustworthy if the sample size is too small
- this script tells you whether the result is numerically stable

What it does **not** prove:

- that the model itself is correct
- that the chosen uncertainty ranges are scientifically justified

Plain-language meaning:
this is the "can I trust the Sobol ranking yet?" test.

## `monte_carlo_uncertainty.R`

Question answered:
"If I repeatedly perturb uncertain inputs, what spread of `C_ri` do I get?"

What it does:

- draws repeated uncertain parameter combinations
- recomputes the output many times
- stores a distribution of possible outcomes

Why it matters:

- sensitivity tells you what matters
- Monte Carlo tells you how wide the plausible result range is

What it does **not** prove:

- that the uncertainty model is complete
- that stochastic output has converged unless convergence is checked separately

Plain-language meaning:
this is the "how wide is the plausible range once uncertainty is propagated?"
test.

## `diagnose_monte_carlo_convergence.R`

Question answered:
"Did I run enough Monte Carlo iterations?"

What it does:

- compares summaries across increasing iteration counts
- checks whether means, quantiles, or intervals stabilize
- reports whether extra iterations still change the answer materially

Why it matters:

- a Monte Carlo interval is only defensible if it has numerically stabilized
- this separates real uncertainty from simulation noise

What it does **not** prove:

- that the uncertainty assumptions are correct
- that the model has external validation

Plain-language meaning:
this is the "is the Monte Carlo result stable yet?" test.

## `compare_scenarios.R`

Question answered:
"How different are the saved outputs across scenarios?"

What it does:

- loads multiple saved `fi_grid` outputs
- compares totals and spatial patterns
- summarizes differences between scenarios

Why it matters:

- it helps communicate how strong scenario dependence is
- it is often the most policy-relevant summary for readers

What it does **not** prove:

- which scenario is true
- why a scenario differs unless inputs are audited separately

Plain-language meaning:
this is the "how much do conclusions change across plausible setups?" test.

## `synthetic_validation.R`

Question answered:
"Does the implemented formula behave as expected on known synthetic cases?"

What it does:

- creates synthetic examples with known expected behavior
- recomputes the formula
- checks whether the code reproduces the expected algebra

Why it matters:

- it is a useful guard against coding mistakes
- it checks formula integrity in a controlled setting

What it does **not** prove:

- real-world validity
- external scientific validation

Important interpretation:
this is a formula integrity check, not an external validation dataset.

Plain-language meaning:
this is the "does the equation implementation do what the equation says?" test.

## Quick memory aid

If you forget everything else, keep this map:

- `benchmark_vs_baseline.R`: compare the internal classifier to simple rules
- `sensitivity_oat_analysis.R`: change one assumption at a time
- `sensitivity_sobol.R`: vary all assumptions jointly
- `monte_carlo_uncertainty.R`: propagate uncertainty repeatedly
- `compare_scenarios.R`: compare saved scenario outputs
- `synthetic_validation.R`: check formula self-consistency
- `check_fi_grid_consistency.R`: check whether the saved object itself is sane

## Most important caveats

Three misunderstandings must be avoided:

- `benchmark_vs_baseline.R` is an internal comparison, not external ground-truth
  validation
- `sensitivity_sobol.R` measures parameter importance, not scientific truth
- `synthetic_validation.R` checks algebraic self-consistency, not ecological
  validity
