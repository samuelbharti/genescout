# Data sources

Provenance for every external source CANDID queries. Keep this current: when you
add or change a source, record its endpoint, version/release, access date, and terms.
This table is what a reviewer will ask for and what makes the method reproducible.

> Fill in version/release and access date as you wire each client. `TBD` = not yet
> integrated or not yet recorded.

| Source | Stage | Endpoint | Version / release | Access date | Terms allow programmatic use | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| MyGene | parse / resolve | <https://mygene.info/v3> | v3 | 2026-07-09 | Yes | Symbol → Ensembl / Entrez / UniProt |
| Ensembl VEP | variant effect | <https://rest.ensembl.org> | TBD | TBD | Yes | Functional consequence |
| gnomAD | variant effect | <https://gnomad.broadinstitute.org/api> | TBD | TBD | Yes | Population allele frequency |
| ClinVar (NCBI E-utilities) | variant effect | <https://eutils.ncbi.nlm.nih.gov> | TBD | TBD | Yes | Evidence only; not clinical classification |
| Open Targets Platform | pathway & disease | <https://api.platform.opentargets.org/api/v4/graphql> | v4 (GraphQL) | 2026-07-09 | Yes | Gene–disease associations |
| Reactome | pathway & disease | <https://reactome.org/ContentService> | TBD | TBD | Yes | Pathway membership |
| PAGER | pathway & disease | TBD | TBD | TBD | TBD | Pathway / gene-set enrichment |
| Europe PMC | literature | <https://www.ebi.ac.uk/europepmc/webservices/rest> | TBD | TBD | Yes | Citation retrieval |
| PubTator | literature | <https://www.ncbi.nlm.nih.gov/research/pubtator3-api> | TBD | TBD | Yes | Pre-annotated gene/disease/variant mentions |

## Reproducibility checklist

- [ ] Every integrated source has a real version/release and access date above.
- [ ] Each client sends a descriptive `User-Agent` and respects rate limits.
- [ ] Dependency versions are pinned (`renv.lock` / `DESCRIPTION`).
- [ ] A container recipe reproduces the environment.
- [ ] Example candidates in `data/examples/` are public or synthetic only.
