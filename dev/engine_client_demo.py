#!/usr/bin/env python3
"""CANDID engine client demo - drive the UI-agnostic core from Python, zero R.

This proves the source connectors + selection API are usable outside R Shiny: a
non-R front end (this script, or a React app) discovers the source catalog, lets a
user choose a subset, and posts a candidate gene list + that selection to /review,
getting back the ranked, caveated, grounded result.

Standard library only (urllib + json) - no pip install. Requires a running engine:

    Rscript dev/serve.R 8000            # in another terminal (needs `plumber`)
    python dev/engine_client_demo.py    # or: python3 ...  [base_url]

Research use only. Not for clinical or diagnostic use.
"""

import json
import sys
import urllib.request

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"


def get(path):
    with urllib.request.urlopen(BASE + path, timeout=30) as r:
        return json.load(r)


def post(path, body):
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        BASE + path, data=data, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.load(r)


def main():
    # 1. Discover the catalog. Each entry carries the selection metadata a picker
    #    needs: key, domain, default_on, available, stub. A real UI groups by domain.
    catalog = get("/catalog")["sources"]
    print(f"Catalog: {len(catalog)} sources")
    by_domain = {}
    for s in catalog:
        by_domain.setdefault(s["domain"], []).append(s)
    for domain, entries in sorted(by_domain.items()):
        keys = ", ".join(
            e["key"] + ("*" if e["stub"] else "") + ("!" if not e["available"] else "")
            for e in entries
        )
        print(f"  [{domain}] {keys}")
    print("  (* = catalog-only stub, ! = needs an API key)")

    # 2. Choose a subset: the cancer axis plus two fast defaults. Skip stubs and
    #    key-gated-without-key sources (they are not runnable).
    chosen = [
        s["key"]
        for s in catalog
        if not s["stub"]
        and s["available"]
        and (s["domain"] == "cancer" or s["key"] in ("ot_assoc", "gnomad_loeuf"))
    ]
    print(f"\nSelected {len(chosen)} sources: {', '.join(chosen)}")

    # 3. Post a candidate set + the selection to /review - the exact same envelope
    #    the Shiny app and the CLI use, over plain JSON.
    body = {
        "sources": [
            {
                "genes": ["NF1", "SUZ12", "CDKN2A", "TP53", "EED", "TTN"],
                "label": "my candidates",
                "type": "pasted",
            }
        ],
        "options": {"sources": chosen, "caveats": True},
    }
    print("Running review (live pipeline, ~10-20s)...")
    result = post("/review", body)

    # 4. Render the ranked, caveated result.
    genes = sorted(result["genes"], key=lambda g: g["rank"])
    print(f"\n{'rank':>4}  {'symbol':<8} {'score':>6}  grade")
    print("  " + "-" * 34)
    for g in genes:
        flag = "  <- vetoed" if g.get("vetoed") else ""
        print(f"{g['rank']:>4}  {g['symbol']:<8} {g['composite']:>6.3f}  {g['grade']}{flag}")

    prov = ", ".join(s["source"] for s in result["provenance"])
    print(f"\nProvenance (sources queried): {prov}")
    print(f"Grounded evidence items: {len(result['evidence'])}")
    print("\nResearch use only. Not for clinical or diagnostic use.")


if __name__ == "__main__":
    main()
