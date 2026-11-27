# Finding file schema

One markdown file per historical finding, ingested into the RAG index by
`scripts/ingest.py` and retrieved by `scripts/search_kb.py`. Keep them small and
mechanistic — the retriever matches on the *shape* of the bug, so spell out the
mechanism, not marketing.

Filename: `NNNN-short-slug.md` (zero-padded id).

```markdown
---
id: "0001"
title: Short name of the bug
class: erc4626-inflation        # must match a class in taxonomy/vuln-classes.md
severity: high
source: Sherlock | Cantina | Solodit | Immunefi | rekt | SWC | DeFiHackLabs
ref: https://...                # original report / PoC
chains: [ethereum]
loss_usd: 200000000             # 0 if unknown / not exploited in the wild
---

## Invariant broken
One sentence.

## Mechanism
2-6 sentences. The exact sequence that breaks it, from a fresh wallet.

## Tell (how detection spots it)
The code smell / Slither detector / call-graph pattern that flags it.

## Fix
What the patch was.

## DeFiHackLabs
Path to the runnable PoC if one exists, e.g. src/test/2023-07/EulerFinance_exp.sol
```

Audit reports (Sherlock/Cantina/Solodit) are text — pure RAG fuel. DeFiHackLabs entries
additionally point at a runnable PoC, which is how the exploitation-agent gets few-shot
examples and eval ground truth.
