# 📊 Gap Analysis for L&O: Methods Publication
## Dredging Impact Assessment Pipeline - Method Validation Requirements

**Analysis Date**: 2026-01-08
**Pipeline Version**: V6 (ETAPE5_ORGANISEE - Production Ready)
**Objective**: Assess readiness for publication in Limnology & Oceanography: Methods

---

## 📋 EXECUTIVE SUMMARY

The pipeline calculates **fishing intensity (f_i)** and **carbon remineralization (C_ri)** from AIS data using a multi-step approach (Steps 0-6). While the methodology is technically sound with good computational validation, **significant gaps exist** in method validation, benchmarking, uncertainty quantification, and sensitivity analysis required for L&O: Methods publication.

**Current Status**: 🟡 **Partially Ready** (50% complete)
- ✅ Proof of concept demonstrated
- ⚠️ Limited benchmarking
- ❌ Incomplete uncertainty analysis
- ⚠️ Partial sensitivity analysis
- ❌ No validation with independent data
- ⚠️ Limited discussion of limitations

---

## 🔍 PIPELINE OVERVIEW

### Method: Dredging Impact Assessment from AIS Data

**Steps:**
1. **Step 0**: Temporal window selection (optimal time period)
2. **Step 1**: Ship-based data splitting
3. **Step 2**: Outlier detection (Isolation Forest) + trajectory processing
4. **Step 3**: Dredging classification (GMM, DBSCAN, HMM) + **Grid Search optimization**
5. **Step 4**: Lithology enrichment
6. **Step 5**: Fishing intensity calculation (f_i) - **Modular tile-based approach**
7. **Step 6**: Carbon remineralization index (C_ri) calculation

**Key Innovation**: Modular tile-based processing (525 tiles × 1000km) to avoid memory overflow (OOM), replacing monolithic approach that required >380 GB.

---

## ✅ WHAT EXISTS (Strengths)

### 1. **Proof of Concept** ✅ STRONG
**Location**: Full pipeline Steps 0-6 operational

**Evidence**:
- ✅ Pipeline runs end-to-end on real AIS data (10.4M+ observations, 11 ships)
- ✅ Produces final outputs: `fi_grid_*.parquet`, `cri_final_*.rds`, GeoTIFF rasters
- ✅ Modular approach validated: 525 tiles processed successfully
- ✅ Computational validation: Memory optimization from >380GB to 16-64GB per tile
- ✅ Multiple test scripts: `test_tuile_temoin.sh`, `test_fusion.sh`, `diagnostic_*.sh`

**Files**:
- `pipeline_V6/step5_modulaire/README_STEP5_MODULAIRE.md` - Full documentation
- `ETAPE5_ORGANISEE/` - Production-ready corrected scripts
- `pipeline_V6/step5_modulaire/CORRECTIFS_APPLIQUES.md` - 10 major corrections documented

**Strength**: Method clearly works and processes real-world data.

---

### 2. **Parameter Optimization (Grid Search)** ✅ PARTIAL
**Location**: `pipeline_V6/step3_merge_final.R` (lines 1-1527)

**Evidence**:
- ✅ **Grid search for dredging classification weights** (Step 3)
- ✅ **Leave-One-Year-Out (LOYO) cross-validation** implemented
- ✅ **AUC metric** calculated per fold for model performance
- ✅ **Data leakage prevention**: Explicit code to avoid using derived labels
- ✅ Multiple performance metrics tracked: AUC, sensitivity, specificity

**Code Example**:
```r
# Grid-search (poids score dragage) - CORRIGÉ POUR ÉVITER DATA LEAKAGE
cv_folds <- length(unique(ais$Annee))  # Force exactement 1 année = 1 fold
ais[, fold := frank(Annee, ties.method="dense")]
cat("   Validation croisée LOYO stricte:", cv_folds, "folds (1 année = 1 fold)\n")
```

**Gaps**:
- ⚠️ Grid search only for Step 3 (dredging classification), **not for f_i parameters**
- ⚠️ No systematic exploration of f_i parameter space (Step 5)
- ⚠️ AUC results not systematically reported/analyzed

---

### 3. **Multiple Scenarios** ✅ GOOD
**Location**: `configuration/fi_parameters.yaml`

**Evidence**:
- ✅ **3 scenarios defined**: `default`, `conservative`, `upper_bound`
- ✅ **Scenario inheritance** system (conservative inherits from default)
- ✅ **56 Longhurst provinces** with region-specific k_fast values
- ✅ **Freshness factors** for high/low export regions

**Parameters**:
```yaml
scenarios:
  default:
    alpha_dep: 0.25          # Depth attenuation
    fast_fraction: 0.3       # Fast pool fraction
    slow_k: 0.05             # Slow remineralization rate
    preservation_factor: 0.87
    k_fast: {56 regions}     # Region-specific rates

  conservative:
    inherit: default
    k_fast_multiplier: 0.5   # Reduces all k_fast by 50%
    slow_k: 0.025

  upper_bound:
    inherit: default
    alpha_dep: 1.0
    fast_fraction: 1.0
    slow_k: 0.0
```

**Gaps**:
- ⚠️ Only 3 scenarios (not systematic parameter sweep)
- ❌ No uncertainty ranges for parameters
- ❌ No justification for default parameter values

---

### 4. **Uncertainty Bounds** ⚠️ LIMITED
**Location**: `ETAPE5_ORGANISEE/01_scripts_principaux/step6_calculate_cri_corrected.R`

**Evidence**:
- ✅ **C0i carbon stock bounds**: `C0i_global_error_lower_bound`, `C0i_upper_bound`
- ✅ **Conservative scenario** provides lower bound estimate
- ✅ **Output includes uncertainty columns**: `C_ri_lower`, `C_ri_upper`

**Code Example**:
```r
fi_dt[, C_ri := pmin(C0i * f_i_full * di, C0i)]
if ("C0i_lower" %in% names(fi_dt))
  fi_dt[, C_ri_lower := pmin(C0i_lower * f_i_full * di, C0i_lower)]
if ("C0i_upper" %in% names(fi_dt))
  fi_dt[, C_ri_upper := pmin(C0i_upper * f_i_full * di, C0i_upper)]
```

**Gaps**:
- ❌ No uncertainty propagation from AIS positioning errors
- ❌ No uncertainty from dredging classification (Step 3 AUC not propagated)
- ❌ No Monte Carlo or bootstrap uncertainty estimation
- ❌ Missing uncertainty budget

---

### 5. **Robustness Checks** ✅ PARTIAL
**Location**: Multiple validation and diagnostic scripts

**Evidence**:
- ✅ `validation_step3.R` - Basic statistics validation
- ✅ `diagnostic_etape5_complet.R` - Step 5 diagnostics
- ✅ `diagnostic_arret.sh` - Failure diagnostics
- ✅ `monitoring_avance.sh` - Progress monitoring
- ✅ Checkpoint system for reproducibility (Step 3)

**Code Example**:
```r
# Caps f_i par sécurité
if ("f_i_full" %in% names(fi_dt))
  fi_dt[, f_i_full := pmin(pmax(f_i_full, 0), 1)]
```

**Gaps**:
- ⚠️ Diagnostics focus on computational success, not method validation
- ❌ No systematic robustness testing (e.g., subsampling data)
- ❌ No tests with synthetic/known data

---

## ❌ WHAT'S MISSING (Critical Gaps)

### 1. **BENCHMARKING AGAINST EXISTING METHODS** ❌ CRITICAL GAP
**L&O Requirement**: *"Compare new method to previous standard methods"*

**Current Status**: ❌ **No benchmarking found**

**What's Needed**:
1. **Literature review** of existing dredging impact assessment methods
2. **Side-by-side comparison** on same dataset:
   - Traditional methods (if any)
   - Alternative AIS-based approaches
   - Expert manual classification (gold standard)
3. **Quantitative comparison metrics**:
   - Correlation of f_i values
   - Agreement in high-impact area identification
   - Computational efficiency (time, memory)
4. **Advantages/disadvantages analysis**

**Implementation Priority**: 🔴 **HIGH** (Required for publication)

**Estimated Effort**: 3-4 weeks
- 1 week: Literature review + method selection
- 2 weeks: Implementation of comparison method(s)
- 1 week: Analysis and write-up

---

### 2. **VALIDATION WITH INDEPENDENT DATA** ❌ CRITICAL GAP
**L&O Requirement**: *"Use reference materials, standards, or independent data"*

**Current Status**: ❌ **No independent validation**

**What's Needed**:
1. **Independent AIS dataset** (different time period/region)
   - Test generalization of dredging classifier
   - Validate f_i calculations in known regions
2. **Ground truth comparison** (if available):
   - Port records of dredging activity
   - Satellite imagery validation
   - Expert annotations of dredging events
3. **Cross-validation with external databases**:
   - Global Fishing Watch data
   - Regional dredging permits/reports
4. **Synthetic data validation**:
   - Create known dredging patterns
   - Test if method recovers known f_i values

**Implementation Priority**: 🔴 **HIGH** (Strongly recommended)

**Estimated Effort**: 4-6 weeks
- 2 weeks: Acquire independent data
- 2 weeks: Validation analysis
- 1-2 weeks: Write-up

---

### 3. **COMPREHENSIVE SENSITIVITY ANALYSIS** ❌ CRITICAL GAP
**L&O Requirement**: *"Examine how changes in key parameters affect output"*

**Current Status**: ⚠️ **3 scenarios, but not systematic**

**What's Needed**:

#### A. **Step 3 (Dredging Classification) Sensitivity**
- ❌ Isolation Forest contamination rate: `contamination_rate: 0.03`
- ❌ DBSCAN parameters: `eps`, `minPts`
- ❌ GMM number of components
- ❌ Speed thresholds for dredging detection

**Test**: Vary each parameter ±20%, ±50% → measure impact on classification accuracy

#### B. **Step 5 (f_i Calculation) Sensitivity**
**Key Parameters** (from `fi_parameters.yaml`):
- ❌ `alpha_dep: 0.25` - Depth attenuation factor
- ❌ `fast_fraction: 0.3` - Fast vs slow remineralization
- ❌ `slow_k: 0.05` - Slow remineralization rate
- ❌ `k_fast: {regional}` - Fast remineralization rates (56 regions)
- ❌ `preservation_factor: 0.87` - Carbon preservation

**Recommended Analysis**:
```r
# One-at-a-time (OAT) sensitivity
parameters <- list(
  alpha_dep = seq(0.1, 0.5, by=0.05),
  fast_fraction = seq(0.1, 0.5, by=0.05),
  slow_k = seq(0.01, 0.10, by=0.01),
  preservation_factor = seq(0.5, 1.0, by=0.05)
)

# For each parameter:
#  - Vary parameter while holding others constant
#  - Calculate f_i and C_ri for 5-10 test tiles
#  - Plot: parameter value vs output metrics
#  - Identify robust vs sensitive parameters
```

**Output**: Tornado plot showing relative sensitivity of each parameter

#### C. **Spatial Resolution Sensitivity**
- ❌ Test tile sizes: 500km, 1000km (current), 2000km
- ❌ Test grid resolution: 500m, 1km (current), 2km
- ❌ Measure: How does f_i distribution change?

#### D. **Buffer Size Sensitivity** (Already partially implemented!)
**Good news**: `constants.R` has buffer test system:
```r
BUFFER_TEST_VALUES <- c(2000, 10000, 20000, 50000, 100000)
BUFFER_IDX <- as.integer(Sys.getenv("BUFFER_IDX", "1"))
TILE_BUFFER_M <- BUFFER_TEST_VALUES[BUFFER_IDX]
```

**Action**: ✅ Run Step 5 with all 5 buffer values → compare results

**Implementation Priority**: 🔴 **HIGH** (Required for publication)

**Estimated Effort**: 3-4 weeks
- 1 week: Design sensitivity experiments
- 2 weeks: Run computations (can parallelize)
- 1 week: Analysis and visualization

---

### 4. **COMPLETE UNCERTAINTY ANALYSIS** ❌ CRITICAL GAP
**L&O Requirement**: *"Quantify uncertainty, detection limits, or errors"*

**Current Status**: ⚠️ **Partial** (only C0i bounds, no propagation)

**What's Needed**:

#### A. **Error Propagation Framework**
Implement uncertainty propagation through pipeline:

```
AIS positioning error (±10-50m)
    ↓
Step 3: Dredging classification uncertainty (AUC = 0.XX ± 0.YY)
    ↓
Step 5: f_i uncertainty
    ↓
Step 6: C_ri uncertainty
```

**Method**: Monte Carlo simulation (500-1000 iterations)

#### B. **Source of Errors to Quantify**
1. **AIS positioning error**: ±10-50m (GPS accuracy)
2. **Temporal resolution**: AIS ping frequency varies
3. **Dredging classification error**:
   - False positive rate (transit classified as dredging)
   - False negative rate (dredging missed)
   - Quantified from Step 3 LOYO cross-validation
4. **Parameter uncertainty**:
   - Literature ranges for k_fast, alpha_dep, etc.
   - Expert elicitation if literature insufficient
5. **Grid discretization error**: 1km resolution
6. **C0i measurement uncertainty**: Already included ✅

#### C. **Output Uncertainty Metrics**
For each 1km² grid cell, report:
- `f_i_mean`: Mean fishing intensity
- `f_i_sd`: Standard deviation
- `f_i_95CI_lower`: 95% confidence interval lower bound
- `f_i_95CI_upper`: 95% confidence interval upper bound
- `f_i_sources`: Breakdown by error source

#### D. **Detection Limits**
Document:
- **Minimum detectable dredging intensity**: Below what f_i value is signal unreliable?
- **Spatial detection limit**: Minimum dredged area detectable?
- **Temporal detection limit**: Minimum dredging duration detectable?

**Implementation Priority**: 🟠 **MEDIUM-HIGH** (Important for credibility)

**Estimated Effort**: 4-6 weeks
- 2 weeks: Implement Monte Carlo framework
- 2 weeks: Run simulations
- 1-2 weeks: Analysis and documentation

---

### 5. **EXPLICIT DISCUSSION OF LIMITATIONS** ⚠️ PARTIAL
**L&O Requirement**: *"Openly discuss method's scope and limits"*

**Current Status**: ⚠️ **Scattered in code comments, not documented**

**What Exists** (buried in code/README):
- ✅ Memory limitations acknowledged (→ modular approach)
- ✅ OOM problem documented: ">380 GB" in monolithic version
- ⚠️ Some data quality checks (NA handling, coordinate validation)

**What's Missing**:
#### A. **Method Assumptions** ❌ Not documented
1. **AIS data completeness**: Assumes continuous tracking
2. **Ship behavior**: Assumes speed/course patterns indicate dredging
3. **Spatial accuracy**: 1km grid appropriate for dredging scale
4. **Temporal resolution**: AIS ping frequency adequate
5. **Regional applicability**: k_fast values valid globally?

#### B. **Known Limitations** ❌ Not documented
1. **Small vessels**: AIS not mandatory for ships <300 GT
2. **Illegal dredging**: Ships with disabled AIS
3. **Coastal vs offshore**: Method performance may vary
4. **Shallow vs deep water**: Depth affects detectability
5. **Data gaps**: Missing AIS data periods
6. **Longhurst province boundaries**: Sharp transitions vs gradual

#### C. **Failure Modes** ❌ Not tested
When does the method fail?
- Too few observations per cell?
- High-traffic areas (e.g., shipping lanes)?
- Poor AIS coverage regions?
- Multi-purpose vessels (dredging + other activities)?

#### D. **Scope of Applicability**
Document valid ranges:
- **Geographic scope**: Global? Coastal only?
- **Temporal scope**: 2015-2024 (from README) - method valid outside this?
- **Vessel types**: Dredgers only? Other bottom-contact gear?
- **Environmental conditions**: All ocean regions? Ice-covered seas?

**Implementation Priority**: 🟡 **MEDIUM** (Essential for honest reporting)

**Estimated Effort**: 2-3 weeks
- 1 week: Compile and test limitations
- 1 week: Document failure modes
- 0.5-1 week: Write discussion section

---

### 6. **REPRODUCIBILITY & TRANSPARENCY** ⚠️ PARTIAL
**L&O Requirement**: *"FAIR principles, methods papers reference standard guides"*

**Current Status**: ⚠️ **Good code, but incomplete documentation**

**What Exists**:
- ✅ Well-organized code structure (`ETAPE5_ORGANISEE/`)
- ✅ Correction log (`CORRECTIFS_APPLIQUES.md`)
- ✅ Step-by-step README (`README_STEP5_MODULAIRE.md`)
- ✅ Configuration files (YAML)
- ✅ Checkpoint system for Step 3

**What's Missing**:
- ❌ **No DOI** for code/data deposit (Zenodo, Dryad)
- ❌ **No sample dataset** for method demonstration
- ❌ **No reference to uncertainty standards** (e.g., GUM - Guide to the Expression of Uncertainty in Measurement)
- ❌ **Parameters not fully justified** (why alpha_dep = 0.25?)
- ❌ **No workflow diagram** (visual representation of Steps 0-6)

---

## 📊 PRIORITY MATRIX

| Gap | Priority | Effort | Impact on Publication | Deadline |
|-----|----------|--------|----------------------|----------|
| **1. Benchmarking** | 🔴 CRITICAL | 3-4 weeks | **Acceptance blocker** | Week 1-4 |
| **2. Sensitivity Analysis** | 🔴 CRITICAL | 3-4 weeks | **Acceptance blocker** | Week 1-4 |
| **3. Independent Validation** | 🔴 HIGH | 4-6 weeks | Strongly recommended | Week 5-10 |
| **4. Uncertainty Analysis** | 🟠 MEDIUM-HIGH | 4-6 weeks | Strengthens credibility | Week 5-10 |
| **5. Limitations Documentation** | 🟡 MEDIUM | 2-3 weeks | Required for discussion | Week 11-13 |
| **6. Reproducibility Package** | 🟡 MEDIUM | 1-2 weeks | Required for acceptance | Week 14-15 |

**Total Estimated Time**: 15-20 weeks (4-5 months) for full publication readiness

---

## ✅ IMPLEMENTATION ROADMAP

### **Phase 1: Critical Gaps (Weeks 1-8)** 🔴

#### **Weeks 1-4: Benchmarking & Sensitivity**
**Objective**: Address reviewers' primary concerns

**Tasks**:
1. **Benchmarking** (Week 1-4):
   - [ ] Literature review: Existing dredging impact methods
   - [ ] Identify 1-2 comparison methods
   - [ ] Implement comparison on subset of data (e.g., 1 year, 1 region)
   - [ ] Generate comparison tables/plots
   - [ ] Write benchmarking section

2. **Sensitivity Analysis - Part 1** (Week 1-4, parallel):
   - [ ] Design OAT sensitivity experiments (5 key parameters)
   - [ ] Run buffer size experiments (already coded - just execute!)
   - [ ] Create sensitivity tornado plot
   - [ ] Identify robust vs sensitive parameters

**Deliverable**: Draft manuscript with benchmarking & sensitivity sections

---

#### **Weeks 5-8: Validation & Uncertainty**
**Objective**: Strengthen method validation

**Tasks**:
1. **Independent Validation** (Week 5-8):
   - [ ] Acquire independent AIS dataset (different region/time)
   - [ ] Generate synthetic dredging patterns (known f_i)
   - [ ] Run pipeline on both datasets
   - [ ] Calculate validation metrics (correlation, RMSE)
   - [ ] Document validation results

2. **Uncertainty Analysis - Part 1** (Week 5-8, parallel):
   - [ ] Implement simple Monte Carlo (100 iterations, 1 tile)
   - [ ] Propagate AIS positioning error → f_i
   - [ ] Calculate CV (coefficient of variation) for f_i
   - [ ] Identify high-uncertainty regions

**Deliverable**: Validation section + preliminary uncertainty estimates

---

### **Phase 2: Refinement (Weeks 9-15)** 🟡

#### **Weeks 9-12: Complete Uncertainty & Limitations**
**Objective**: Polish method description

**Tasks**:
1. **Uncertainty Analysis - Part 2** (Week 9-12):
   - [ ] Extend Monte Carlo to full dataset (500+ iterations)
   - [ ] Implement error propagation from Step 3 → 6
   - [ ] Create uncertainty budget table
   - [ ] Document detection limits

2. **Limitations Documentation** (Week 9-12, parallel):
   - [ ] Compile method assumptions list
   - [ ] Test failure modes (edge cases)
   - [ ] Define scope of applicability
   - [ ] Write limitations section

**Deliverable**: Complete uncertainty section + discussion

---

#### **Weeks 13-15: Reproducibility & Finalization**
**Objective**: Prepare submission package

**Tasks**:
1. **Reproducibility Package** (Week 13-15):
   - [ ] Create sample dataset (1 ship, 1 month)
   - [ ] Write tutorial notebook (Jupyter/R Markdown)
   - [ ] Deposit code on Zenodo (DOI)
   - [ ] Create workflow diagram (visual abstract)
   - [ ] Reference GUM for uncertainty

2. **Manuscript Finalization** (Week 13-15):
   - [ ] Integrate all sections
   - [ ] Create figures/tables
   - [ ] Write abstract & conclusions
   - [ ] Internal review
   - [ ] Submission!

**Deliverable**: 📤 **Manuscript submitted to L&O: Methods**

---

## 📈 QUICK WINS (Can Start Immediately)

### **1. Buffer Size Sensitivity** ⚡ 1 week
**Status**: ✅ Already coded in `constants.R`!
```r
BUFFER_TEST_VALUES <- c(2000, 10000, 20000, 50000, 100000)
```

**Action**:
```bash
# Run Step 5 with each buffer:
for i in 1 2 3 4 5; do
  export BUFFER_IDX=$i
  sbatch ETAPE5_ORGANISEE/04_scripts_slurm/step5_tile_job.sh
done

# Compare f_i distributions
```

**Output**: Plot showing f_i sensitivity to buffer size → Include in sensitivity section

---

### **2. Extract Step 3 AUC Metrics** ⚡ 1 day
**Status**: ✅ Already calculated in Step 3!
```r
auc_fold[k] <- as.numeric(pROC::auc(roc_test))
```

**Action**:
- Read `dragage_gridsearch_results_V6_*.rds`
- Extract AUC per fold
- Calculate mean ± SD
- Report in manuscript: "Dredging classification achieved AUC = 0.XX ± 0.YY"

**Output**: Classification performance metrics for methods section

---

### **3. Document Existing Scenarios as Sensitivity** ⚡ 1 week
**Status**: ✅ 3 scenarios already run!
```yaml
default, conservative, upper_bound
```

**Action**:
- Compare `f_i_full` vs `f_i_conservative` outputs
- Calculate % difference in C_ri estimates
- Frame as "parameter uncertainty bounds"

**Output**: Preliminary uncertainty analysis (conservative vs upper_bound)

---

### **4. Create Failure Mode Tests** ⚡ 1 week
**Action**:
Create test cases:
```r
# Test 1: Very few observations per cell
test_data_sparse <- dredge_dt[sample(.N, 100)]  # Only 100 pings globally

# Test 2: Single cell with many pings
test_data_dense <- dredge_dt[grid_id == most_common_cell]

# Test 3: Extreme parameter values
test_params <- list(alpha_dep = 0.01, fast_fraction = 0.99)

# Run pipeline → Document failures
```

**Output**: Documented failure modes for limitations section

---

## 🎯 RECOMMENDED NEXT STEPS (Priority Order)

### **Immediate (Week 1)**
1. ✅ **Read this gap analysis** - Done!
2. 📊 **Extract Step 3 AUC metrics** - 1 day (Quick win #2)
3. 🎲 **Run buffer sensitivity** - 1 week (Quick win #1)
4. 📚 **Literature review for benchmarking** - Start now

### **Short-term (Weeks 2-4)**
5. 🔬 **Design sensitivity experiments** - Key parameters
6. 📊 **Implement first comparison method** - Benchmarking
7. 📝 **Draft limitations section** - Low-hanging fruit

### **Medium-term (Weeks 5-12)**
8. 🧪 **Independent validation** - Critical for acceptance
9. 📐 **Monte Carlo uncertainty** - Strengthen rigor
10. 📈 **Complete sensitivity analysis** - All parameters

### **Long-term (Weeks 13-15)**
11. 📦 **Reproducibility package** - Code deposit
12. ✍️ **Manuscript integration** - Pull it all together
13. 📤 **Submit!**

---

## 📌 KEY RECOMMENDATIONS

### **For the Methods Section:**
1. ✅ **Keep**: Excellent documentation of modular approach (pipeline_V6/step5_modulaire/)
2. ➕ **Add**: Workflow diagram (visual Steps 0-6)
3. ➕ **Add**: Parameter justification table (why these values?)
4. ➕ **Add**: Reference to GUM for uncertainty

### **For the Results Section:**
1. ➕ **Add**: Sensitivity tornado plot
2. ➕ **Add**: Benchmarking comparison table
3. ➕ **Add**: Validation scatter plots (predicted vs independent)
4. ➕ **Add**: Uncertainty maps (f_i ± 95% CI)

### **For the Discussion Section:**
1. ➕ **Add**: Explicit assumptions list
2. ➕ **Add**: Known limitations (bullets 1-6 from Gap #5)
3. ➕ **Add**: Comparison to literature methods (advantages/disadvantages)
4. ➕ **Add**: Recommended use cases (when to use/avoid this method)

---

## 📚 REFERENCES TO INCLUDE

### **Uncertainty Quantification:**
- JCGM 100:2008 - GUM: Guide to the Expression of Uncertainty in Measurement
- ISO/IEC Guide 98-3:2008

### **Cross-Validation:**
- Roberts et al. (2017) - Cross-validation strategies for data with temporal structure
- Bergmeir & Benítez (2012) - On the use of cross-validation for time series

### **Benchmarking:**
- [Literature review needed - existing dredging impact methods]

---

## 💡 FINAL THOUGHTS

**Strengths of Current Pipeline:**
- ✅ Computationally validated
- ✅ Scalable (modular approach)
- ✅ Well-documented code
- ✅ Multiple scenarios (3)
- ✅ Grid search + LOYO CV (Step 3)

**Critical for Publication:**
- 🔴 Benchmarking
- 🔴 Sensitivity analysis (systematic)
- 🔴 Independent validation

**Would Strengthen:**
- 🟠 Full uncertainty propagation
- 🟡 Limitations documentation
- 🟡 Reproducibility package

**Estimated Timeline to Publication:**
- **Fast track** (minimal): 8-10 weeks (Benchmarking + Sensitivity only)
- **Recommended**: 15-20 weeks (All critical + important gaps)
- **Comprehensive**: 20-25 weeks (All gaps addressed)

---

## 📞 QUESTIONS FOR DISCUSSION

1. **Benchmarking**: Do existing dredging impact assessment methods exist for comparison? Or is this novel?
2. **Validation data**: Is independent AIS data or ground truth available?
3. **Parameter justification**: What's the source for alpha_dep=0.25, fast_fraction=0.3, etc.?
4. **Target scope**: Global applicability or specific regions/conditions?
5. **Timeline**: What's the target submission date?

---

**Report prepared for publication readiness assessment**
**Next action**: Discuss priorities and timeline with research team
