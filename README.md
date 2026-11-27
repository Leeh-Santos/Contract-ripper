# Contract Ripper — agentic smart-contract audit workbench

**A few agents reason; the data they read from is what scales.**

Two version-controlled reasoning agents sit on top of a large, ever-growing body of
data. Adding the 300th hack or audit report changes zero `.md` files.

```
AGENTS (reasoning — a few .md files in git)        DATA (grows forever)
┌───────────────┐   ┌──────────────────┐           ┌───────────────────────────┐
│ detection     │──▶│ exploitation     │           │ Knowledge base (RAG)      │
│ -agent.md     │   │ -agent.md        │   reads    │  Sherlock·Cantina·Solodit │
└──────┬────────┘   └────────┬─────────┘   ───────▶ │  ·SWC  (text findings)    │
       │ retrieve (RAG)      │ run on fork · verify  ├───────────────────────────┤
       └─────────────────────┴──────────────────────│ DeFiHackLabs (submodule)  │
                                                     │  runnable ground truth —  │
                                                     │  eval + few-shot examples │
                                                     └───────────────────────────┘
```

## The two agents

- **`.claude/agents/detection-agent.md`** — reads a target contract, runs Slither,
  retrieves similar historical findings via RAG, reasons over the call graph and
  invariants, and emits a **ranked JSON list of exploitable candidates**.
- **`.claude/agents/exploitation-agent.md`** — takes **one** candidate and proves it:
  writes a Foundry PoC, runs it on an Anvil **fork** from a fresh unprivileged wallet,
  and **iterates until an invariant breaks** or it gives up with a reason. A passing
  test is the proof — this is the self-grading layer.

Triage and report agents come later; the design is "few agents, organized by function,
never by data source."

## Layout

| Path | What it is |
|---|---|
| `.claude/agents/*.md` | the reasoning agents (the brains) |
| `knowledge-base/taxonomy/vuln-classes.md` | the detection checklist |
| `knowledge-base/findings/*.md` | RAG corpus (Sherlock/Cantina/Solodit/SWC) |
| `scripts/ingest.py`, `scripts/search_kb.py` | RAG ingest + retrieval (stdlib only) |
| `templates/Exploit.t.sol` | PoC template the exploitation-agent copies |
| `foundry.toml` | fork config, reads `$ETH_RPC_URL` |
| `lib/DeFiHackLabs` | **submodule** — runnable ground truth (don't copy it in) |
| `targets/<name>/` | per-engagement workspace (contracts, candidates, PoCs, results) |

The data never lives in the agents. DeFiHackLabs stays a submodule; the knowledge base
is a build artifact you re-ingest. You update the agents without re-shipping gigabytes,
and grow the knowledge base without touching the agents.

## Setup

```bash
bash scripts/setup.sh                 # forge-std + DeFiHackLabs submodule + build index
export ETH_RPC_URL=<archive-rpc-url>  # required for fork / exploitation runs
```

## Run an audit

```
# 1. Put the target under targets/mytarget/src/
# 2. Detection — ranked candidates -> targets/mytarget/candidates.json
@detection-agent audit targets/mytarget

# 3. Exploitation — prove the top candidate on a fork
@exploitation-agent prove candidate C1 from targets/mytarget/candidates.json
```

## Eval the exploitation agent (self-grading)

Point it at a DeFiHackLabs incident with the known solution hidden; a passing PoC that
rediscovers the drain is the grade. No human labeling.

```
@exploitation-agent reproduce <incident-name> from DeFiHackLabs (solution hidden)
```

## RAG smoke test

```bash
python3 scripts/ingest.py
python3 scripts/search_kb.py "price from spot reserves flash loan" -k 3
```
