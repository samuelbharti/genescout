# Data sources

Provenance for every external source CANDID queries. Keep this current: when you
add or change a source, record its endpoint, version/release, access date, and terms.
This table is what a reviewer will ask for and what makes the method reproducible.

> Fill in version/release and access date as you wire each client. `TBD` = not yet
> integrated or not yet recorded.

| Source | Stage | Endpoint | Version / release | Access date | Terms allow programmatic use | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| MyGene | resolve / dedupe | <https://mygene.info/v3> | v3 | 2026-07-09 | Yes | Symbol → Ensembl / Entrez / UniProt (canonical dedupe key) |
| Open Targets Platform | ranking signal | <https://api.platform.opentargets.org/api/v4/graphql> | v4 (GraphQL) | 2026-07-09 | Yes | Max gene–disease association score (0–1) |
| Europe PMC | ranking signal | <https://www.ebi.ac.uk/europepmc/webservices/rest> | REST v6.9 | 2026-07-09 | Yes | Gene mention count (`hitCount`) + exemplar citations |
| ClinVar (NCBI E-utilities) | ranking signal | <https://eutils.ncbi.nlm.nih.gov> | E-utilities JSON (esearch) | 2026-07-09 | Yes | Count of pathogenic / likely-pathogenic variants per gene. Evidence only; not clinical classification |
| Ensembl VEP | variant mode (dormant) | <https://rest.ensembl.org> | REST (GRCh38) | 2026-07-09 | Yes | Functional consequence (by rsID); reserved for a future variant mode, not in the gene-list ranking |
| gnomAD | variant mode (dormant) | <https://gnomad.broadinstitute.org/api> | gnomad_r4 (GraphQL) | 2026-07-09 | Yes | Population allele frequency; reserved for a future variant mode |
| PubTator | ranking signal (planned) | <https://www.ncbi.nlm.nih.gov/research/pubtator3-api> | TBD | TBD | Yes | Gene-tagged literature count; precise successor to the Europe PMC symbol count |
| Reactome | ranking signal (planned) | <https://reactome.org/ContentService> | TBD | TBD | Yes | Pathway membership |
| PAGER | ranking signal (planned) | TBD | TBD | TBD | TBD | Pathway / gene-set enrichment |
| STRING | ranking signal (planned) | <https://string-db.org/api> | TBD | TBD | Yes | Within-list interaction connectivity |

## Reproducibility checklist

- [ ] Every integrated source has a real version/release and access date above.
- [ ] Each client sends a descriptive `User-Agent` and respects rate limits.
- [ ] Dependency versions are pinned (`renv.lock` / `DESCRIPTION`).
- [ ] A container recipe reproduces the environment.
- [ ] Example candidates in `data/examples/` are public or synthetic only.
