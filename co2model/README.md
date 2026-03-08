# CO2 Model Dependency (External, Not Vendored)

This repository does not redistribute the third-party MATLAB OCIM CO2 solver
source code.

To run the optional CO2 step, fetch the dependency from the upstream author
repository at a pinned tag or commit:

```bash
bash deploy/fetch_co2model_dependency.sh \
  --repo <author_repo_url> \
  --ref <tag_or_commit> \
  --dest data/external/co2model_vendor
```

Then upload from that source directory:

```bash
bash deploy/upload_step7_to_grit.sh --co2model-src data/external/co2model_vendor
```

Legal tracking and attribution are maintained in `THIRD_PARTY_NOTICES.md`.
