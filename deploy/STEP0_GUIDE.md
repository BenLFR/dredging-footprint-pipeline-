# Step 0 Enhanced: Temporal Coverage Analysis - GRIT Setup Guide

## Overview

Step 0 Enhanced analyzes the temporal coverage of AIS data to determine the optimal time window for analysis. This enhanced version provides comprehensive analysis of all candidate windows.

**Enhanced Features:**
- Complete analysis of all candidate time windows (not just the best one)
- Ship × Year coverage matrix export
- Top 20 best windows ranking
- Detailed annual statistics
- Progress tracking during analysis

**Outputs Generated:**
- Coverage matrix (ship × year)
- Complete windows analysis
- Top 20 best windows
- Annual statistics
- Best time window selection
- Coverage visualizations

## Files Required on GRIT

### 1. Scripts (synced automatically)
```bash
# After running: bash deploy/sync_to_grit.sh

~/ais-pipeline/
├── pipeline_V6/
│   ├── step0_core_window_enhanced.R       # Enhanced core window selection ⭐
│   └── step0_window_select_enhanced.sh    # Enhanced SLURM submission ⭐
└── configuration/
    └── [any YAML configs if needed]
```

**Note:** We use the **enhanced** versions which provide more comprehensive analysis.

### 2. Input Data (must be uploaded manually)

**Required**: AIS data CSV file(s) on GRIT

```bash
# Upload AIS data to GRIT
# From Windows (Git Bash):
scp -F ~/.ssh/config_grit "path/to/benjamin2.csv" grit:~/scratch/AIS_data/

# Or if you have multiple CSV files:
scp -F ~/.ssh/config_grit "path/to/*.csv" grit:~/scratch/AIS_data/
```

Expected structure on GRIT:
```
~/scratch/AIS_data/
└── benjamin2.csv         # Main AIS data file (or other CSV files)
```

### 3. Required R Packages

These packages must be installed on GRIT (see installation section below):
- data.table
- lubridate
- parallel
- ggplot2
- yaml
- digest
- matrixStats

---

## Step-by-Step Setup on GRIT

### Step 1: Sync Code to GRIT

From your local Windows machine (Git Bash):
```bash
# Navigate to repository
cd "/c/Users/loeff/OneDrive/Bureau/Master thesis/Datasets/AIS Tracks/R code/Beluga"

# Sync all necessary files
bash deploy/sync_to_grit.sh
```

This will sync:
- Step 0 R scripts
- Pipeline V6 scripts
- Configuration files
- Submission scripts

### Step 2: Upload AIS Data to GRIT

```bash
# Upload the main data file
scp -F ~/.ssh/config_grit "AIS_with_lithology_clean.csv" grit:~/scratch/AIS_data/benjamin2.csv

# Or if you have the original benjamin2.csv
scp -F ~/.ssh/config_grit "path/to/benjamin2.csv" grit:~/scratch/AIS_data/
```

### Step 3: Install Required R Packages on GRIT

Connect to GRIT and install packages:
```bash
# Connect to GRIT
ssh -F ~/.ssh/config_grit grit

# Load R module
module load R

# Create personal library directory
mkdir -p ~/R/library
export R_LIBS_USER=~/R/library

# Launch R
R
```

In R:
```r
# Set library path
.libPaths("~/R/library")

# Install required packages
packages <- c('data.table', 'lubridate', 'parallel', 'ggplot2',
              'yaml', 'digest', 'matrixStats')

install.packages(packages, repos='https://cloud.r-project.org/')

# Verify installation
for(pkg in packages) {
  if(require(pkg, character.only=TRUE, quietly=TRUE)) {
    cat('✅', pkg, 'OK\n')
  } else {
    cat('❌', pkg, 'FAILED\n')
  }
}

quit()
```

### Step 4: Prepare Directory Structure

On GRIT:
```bash
# Create necessary directories
mkdir -p ~/ais-pipeline/logs
mkdir -p ~/scratch/output_V6
mkdir -p ~/scratch/output_V6/plots
mkdir -p ~/scratch/AIS_data

# Verify structure
ls -la ~/scratch/AIS_data/      # Should show benjamin2.csv
ls -la ~/ais-pipeline/          # Should show synced scripts
```

---

## Running Step 0 on GRIT

### Method 1: Using SLURM Enhanced (Recommended)

```bash
# Connect to GRIT
ssh -F ~/.ssh/config_grit grit

# Navigate to pipeline directory
cd ~/ais-pipeline/pipeline_V6

# Submit Step 0 Enhanced job (GRIT-adapted version)
sbatch step0_window_select_grit.sh

# Monitor job
squeue -u bloe                           # Check job status
tail -f logs/step0_window_enhanced_*.out # Watch output
tail -f logs/step0_window_enhanced_*.err # Watch errors
```

**Note:** `step0_window_select_grit.sh` is the GRIT-adapted version that:
- Uses GRIT module system (`module load R`)
- Sets correct R library path (`~/R/library`)
- Overrides Beluga-specific paths in the R script

### Method 2: Interactive R Session

```bash
# Connect to GRIT
ssh -F ~/.ssh/config_grit grit

# Load R environment
module load R
export R_LIBS_USER=~/R/library

# Navigate to pipeline directory
cd ~/ais-pipeline/pipeline_V6

# Run Step 0 Enhanced directly
Rscript step0_core_window_enhanced.R
```

### Method 3: Using deployment script (from local machine)

```bash
# From Windows Git Bash
bash deploy/run_on_grit.sh "pipeline_V6/step0_core_window_enhanced.R"
```

---

## Expected Outputs

After Step 0 Enhanced completes, you should find these files in `~/scratch/output_V6/`:

### Enhanced Output Files ⭐
```
~/scratch/output_V6/
├── coverage_matrix.csv          # Ship × Year coverage matrix
├── all_windows_analysis.csv     # Complete analysis of all candidate windows
├── top_20_windows.csv           # Top 20 best time windows ranked
├── annual_statistics.csv        # Detailed annual statistics
├── core_window_report.md        # Comprehensive report
└── plots/
    └── [visualization files]
```

**Key files explained:**
- `coverage_matrix.csv` - Matrix showing coverage for each ship and year
- `all_windows_analysis.csv` - Scores and metrics for every possible time window
- `top_20_windows.csv` - The 20 best performing windows to choose from
- `annual_statistics.csv` - Year-by-year statistics
- `core_window_report.md` - Human-readable summary with recommendations

### Retrieve Results

From local Windows machine:
```bash
# Fetch all Step 0 results
bash deploy/fetch_results.sh

# Results will be downloaded to:
# ./Resultats/
# ./output_V6/
```

---

## Verifying Step 0 Success

### Check Enhanced outputs exist:
```bash
# On GRIT
ssh -F ~/.ssh/config_grit grit
ls -lh ~/scratch/output_V6/

# Should show:
# - coverage_matrix.csv
# - all_windows_analysis.csv
# - top_20_windows.csv
# - annual_statistics.csv
# - core_window_report.md
# - plots/ directory
```

### Inspect top windows:
```bash
# On GRIT
head -n 21 ~/scratch/output_V6/top_20_windows.csv

# Should show:
# year_start,year_end,length,Cbar,Cmin,CV,score,n_ships,total_coverage
# 2015,2021,7,0.85,0.72,0.15,432.1,11,0.82
# [... top 20 windows ranked by score ...]
```

### View comprehensive report:
```bash
# On GRIT
cat ~/scratch/output_V6/core_window_report.md

# Should show:
# - Selected optimal window
# - Statistical metrics
# - Ship presence analysis
# - Recommendations
```

### Inspect coverage matrix:
```bash
# On GRIT
head ~/scratch/output_V6/coverage_matrix.csv

# Shows coverage for each ship × year
# Useful to understand which ships have data in which years
```

---

## Troubleshooting

### Issue: "No CSV files found"
**Solution**: Verify AIS data is uploaded
```bash
ssh -F ~/.ssh/config_grit grit
ls -lh ~/scratch/AIS_data/
# If empty, re-upload the data (see Step 2 above)
```

### Issue: "Package not found"
**Solution**: Install missing R packages
```bash
ssh -F ~/.ssh/config_grit grit
module load R
export R_LIBS_USER=~/R/library
R
# Then in R:
install.packages('package_name', repos='https://cloud.r-project.org/')
```

### Issue: "Cannot create directory"
**Solution**: Check permissions and create manually
```bash
ssh -F ~/.ssh/config_grit grit
mkdir -p ~/scratch/output_V6/plots
mkdir -p ~/ais-pipeline/logs
chmod -R 755 ~/ais-pipeline
```

### Issue: Job fails with memory error
**Solution**: Increase memory in SLURM script
```bash
# Edit step0_window_select_enhanced.sh
# Change: #SBATCH --mem=8G
# To:     #SBATCH --mem=16G
```

### Issue: R cannot find scripts
**Solution**: Check working directory
```bash
# In step0_window_select_enhanced.sh, the working directory should be:
cd ~/ais-pipeline/pipeline_V6

# The script looks for: step0_core_window_enhanced.R
```

### Issue: R library path error
**Solution**: The enhanced script uses different R paths for Beluga vs GRIT
```bash
# The script has: .libPaths("/home/benl/R/library")
# For GRIT, this should be: .libPaths("~/R/library")

# If needed, you can set environment variable before running:
export R_LIBS_USER=~/R/library
```

---

## Configuration Options

### Environment Variables

You can customize Step 0 behavior with environment variables:

```bash
# On GRIT, before running Rscript:
export AIS_INPUT_PATTERN="~/scratch/AIS_data/*.csv"
export AIS_OUTPUT_DIR="~/scratch/output_V6"
export AIS_INPUT_FILE="~/scratch/AIS_data/benjamin2.csv"  # Specific file

Rscript step0_coverage_analysis.R
```

### Parameters in Script

Edit `batch_windows/step0_coverage_analysis.R` (lines 34-40):

```r
params <- list(
  min_window_years = 5,      # Minimum window duration
  min_coverage = 0.15,       # Minimum coverage threshold (15%)
  min_presence_pct = 0.80,   # Minimum vessel presence (80%)
  density_q90 = 0.90,        # Density normalization quantile
  iqr_epsilon = 1e-3         # Epsilon for IQR calculation
)
```

---

## Next Steps

After Step 0 completes successfully:

1. **Review the optimal window**: Check `best_time_window.csv`
2. **Examine coverage plots**: Download plots from `output_V6/plots/`
3. **Proceed to Step 1**: Use the selected time window for vessel splitting
4. **Update pipeline configs**: Set time window parameters in subsequent steps

---

## Quick Reference Commands

```bash
# Sync code to GRIT
bash deploy/sync_to_grit.sh

# Upload data
scp -F ~/.ssh/config_grit benjamin2.csv grit:~/scratch/AIS_data/

# Run Step 0 Enhanced (GRIT version)
ssh -F ~/.ssh/config_grit grit
cd ~/ais-pipeline/pipeline_V6
sbatch step0_window_select_grit.sh

# Monitor
squeue -u bloe
tail -f logs/step0_window_enhanced_*.out

# Fetch results
bash deploy/fetch_results.sh output_V6
```

## Differences: Enhanced vs Standard

| Feature | Standard | Enhanced |
|---------|----------|----------|
| Analysis scope | Best window only | All candidate windows |
| Output files | 4 files | 5+ files |
| Coverage matrix | No | ✅ Yes |
| Top windows ranking | No | ✅ Top 20 |
| Annual statistics | Basic | ✅ Detailed |
| Progress tracking | No | ✅ Progress bar |
| Memory | 6G | 8G |
| Time | 20 min | 30 min |
