# CO2 Model Dependency (External, Not Vendored)

This repository does not redistribute the third-party MATLAB OCIM CO2 solver
source code.

According to the data availability statement used in Atwood-related materials,
the OCIM code is available upon email request to TD:

- `tdevries@geog.ucsb.edu`

There is no confirmed public GitHub repository for the exact OCIM MATLAB code
bundle used in this workflow.

## Recommended workflow

1. Request the OCIM code package by email from TD.
2. Place the received files in `data/external/co2model_vendor/`.
3. Upload that source directory to GRIT:

```bash
bash deploy/upload_step7_to_grit.sh --co2model-src data/external/co2model_vendor
```

Legal tracking and attribution are maintained in `THIRD_PARTY_NOTICES.md`.
