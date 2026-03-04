# Licence

## Status: TBD — choose before journal submission

**Recommendation**: **MIT** for code + **CC-BY 4.0** for data products.
This is the most common combination for methods papers in marine sciences and
is required by several open-access mandates (NWO, Horizon Europe).

## Why MIT for code?

- Permissive: allows commercial and academic reuse with attribution
- Required by L&O:Methods open-science policy (ASLO)
- Compatible with all third-party licences used in this project

## Why CC-BY 4.0 for data outputs?

- Standard for Zenodo deposits in earth sciences
- Requires attribution, prevents silent republication
- Compatible with the Atwood et al. C0 raster (also CC-BY 4.0)

## Action items before submission

1. Add a `LICENSE` file with the MIT licence text:
   ```
   MIT License
   Copyright (c) 2026 Benjamin Loeffler
   [standard MIT text]
   ```
2. Add `LICENSE` to `CITATION.cff`:
   ```yaml
   license: MIT
   ```
3. Add ORCID to `CITATION.cff`:
   ```yaml
   orcid: "https://orcid.org/XXXX-XXXX-XXXX-XXXX"
   ```
4. Reserve Zenodo DOI and update placeholders in:
   - `CITATION.cff`
   - `README.md`
   - `data/README.md`
   - `docs/data_policy.md`
5. Delete this file and add `LICENSE` instead.
