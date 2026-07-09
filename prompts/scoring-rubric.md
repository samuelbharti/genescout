# Scoring & caveats rubric

How CANDID turns gated evidence + disease-context priors into a plausibility
grade, and when the caveats stage down-ranks or vetoes a candidate. This rubric
is explicit and reviewable on purpose - it is the spine of the eventual methods
evaluation.

## Plausibility grade

Combine, per candidate:

- **Functional evidence** - predicted consequence (VEP), rarity (gnomAD),
  ClinVar research evidence.
- **Disease/pathway fit** - association strength (Open Targets) and membership in
  a context pathway (Reactome/PAGER); membership in a known driver or context
  pathway raises the grade.
- **Literature support** - number, recency, and directness of grounded citations.

Grades: **High / Moderate / Low / Insufficient evidence**. "Insufficient
evidence" is a valid, first-class outcome - never inflate a grade to avoid it.

## Caveats and veto (anti-familiar-gene-bias)

Down-rank, or **veto** (force to the bottom with a stated reason), a candidate
that looks compelling but is:

- **Common in gnomAD** - population frequency too high to be a plausible driver.
- **Unrelated-tissue-only** - support comes only from tissues outside the
  context's tissues of interest.
- **Single weak source** - one low-quality citation or a single database hit.
- **Known artifact / FLAGS gene** - recurrent-artifact genes (e.g. TTN, MUC16).

Always record *why* a caveat or veto was applied, on the candidate itself.

## Output

For each candidate: grade, the evidence behind it (with source ids), any caveats
with reasons, and a suggested next experiment or analysis.
