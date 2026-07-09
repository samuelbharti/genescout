# Described plan (original project idea)

> This is the original project pitch, captured verbatim for provenance. The
> refined design lives in [`README.md`](../README.md), [`PLAN.md`](../PLAN.md),
> and [`CLAUDE.md`](../CLAUDE.md).

I want to build an agentic variant and gene evidence review workbench for
research genomics and rare diseases.

The specific problem is that computational biologists often end up with long
lists of variants or genes from sequencing, differential expression, or
perturbation analyses, but the next step is still very manual. A researcher has
to move between VCFs, annotation tables, pathway databases, PubMed, prior papers,
cohort metadata, and their own notes to decide which candidates are worth
following up. This is slow, hard to reproduce, and easy to bias toward familiar
genes.

At the hackathon, I would build a Claude-powered workflow that takes a small
annotated variant table or gene list, along with a biological context such as
NF1-associated cancer, and turns it into an evidence-ranked research review. The
system would have agents for parsing the input, checking functional consequence,
linking genes to pathways and disease biology, retrieving literature support,
identifying caveats, and generating a transparent report.

The goal is not clinical interpretation or diagnosis. The goal is to help a
researcher move faster from "I have a candidate list" to "I understand which
candidates are most biologically plausible, what evidence supports them, what is
uncertain, and what experiments or analyses should come next."

I would demonstrate the tool using cancer genomics examples from NF1-associated
tumor biology, but design it generally enough that it could support other
life-science researchers working with variant, gene, or perturbation results.
