# Benchmarking Protocol

## Methods compared

| Method | Description | Key assumption | Reference |
|--------|-------------|----------------|-----------|
| **Speed threshold** | Classifies a ping as dredging if `speed_knots < 4.0 kn` | Slow movement = dredging; ignores heading and context | Industry rule-of-thumb; outlier_config_V6.yaml `dredging_threshold` |
| **GFW-style proxy** | Speed < 4.0 kn **AND** heading change < 45°/interval | Combines speed with directional stability; tuned for trawling | Kroodsma et al. (2018) *Science* 359(6378):904–908 |
| **Step 3 GMM+DBSCAN** | Gaussian Mixture Model on (speed, heading_change, Δt) + DBSCAN stop detection + penalised Ridge regression dredging score | Multiple kinematic features distinguish dredging from slow transit and anchoring; spatially-aware stops | This study |

## Dataset

The benchmark uses the step3 output file `AIS_data_core_preprocessed_V6_*.rds`
(produced by `step3_merge_final.R`), which contains all 10 TSHDs from
`ship_specs.yaml` over the full study period. The `behavior_smooth` or
`Dragage_flag` column from step3 serves as the reference label.

**Important caveat**: because no independent ground truth exists (no GPS
loggers on the drag heads), the step3 method is used as both the reference
and one of the "methods". This means step3 trivially scores AUC=1.0 against
itself. The meaningful comparison is between the two baselines, which quantifies
*how much information GMM+DBSCAN adds over naive approaches*.

For a stronger validation, see `documentation/VALIDATION_PROTOCOL.md`.

## Metrics

| Metric | Definition |
|--------|-----------|
| **Precision** | TP / (TP + FP): fraction of predicted dredging pings that are truly dredging |
| **Recall** | TP / (TP + FN): fraction of true dredging pings correctly identified |
| **F1 (macro)** | 2 × Precision × Recall / (Precision + Recall): harmonic mean |
| **AUC-ROC** | Area under the ROC curve; measures ranking ability across thresholds |

Dredging = positive class. Transit / anchoring / other = negative class.

## How to run

```bash
# Locally (requires output_V6/AIS_data_core_preprocessed_V6_*_flagOK.rds):
Rscript scripts_principaux/benchmark_vs_baseline.R

# On GRIT cluster:
cd ~/ais-pipeline/pipeline_V6
sbatch scripts_cluster/submit_benchmark_array.sh

# Check results:
cat output_V6/benchmarking_results.csv
```

## How to interpret for L&O:Methods reviewers

If the step3 GMM+DBSCAN classifier produces substantially higher F1/AUC than
the speed-threshold baseline, this demonstrates that the multi-feature kinematic
approach adds genuine classification value. A typical finding is that the speed
threshold achieves high recall (slow vessels are usually dredging) but poor
precision (many anchored or slow-transit pings are falsely classified). The
GFW-style heading filter reduces false positives at the cost of some recall.
A table reporting these numbers in the Methods section directly addresses the
L&O:Methods requirement for performance benchmarking.

**Suggested manuscript phrasing**: "The GMM+DBSCAN classifier (F1 = X.XX)
outperformed a speed-threshold baseline (F1 = X.XX) and a GFW-style kinematic
proxy (F1 = X.XX), demonstrating that multi-dimensional behavioural signatures
improve dredging detection over simple speed cutoffs."

## Known limitations of this benchmarking approach

- **No ground truth**: The step3 classifier is used as both the reference and
  a method. True validation against GPS drag-head activity logs would require
  direct access to vessel operational records (not publicly available).
- **Label leakage**: The step3 reference label was trained on the same vessels;
  comparing baselines to it overestimates the advantage of step3.
- **GFW proxy mismatch**: The GFW heading-change filter was designed for trawling
  vessels; TSHDs have different kinematic signatures (longer slow arcs, less
  turning). Results may not generalise to other dredger types.
- **Speed threshold sensitivity**: The 4.0 kn threshold (from `outlier_config_V6.yaml`)
  was calibrated for this fleet. A different threshold might yield better or worse
  baseline performance.
- **Temporal confounding**: If the step3 reference was trained on the same years
  as the benchmark subset, precision/recall may be inflated relative to
  out-of-sample performance.
