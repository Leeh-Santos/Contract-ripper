# How to use the audit agents

A practical guide: how the agents get loaded, how to run an audit end to end, and how
to reuse the agents in other repos (via git / as a plugin).

---

## 1. Do I need a `.claude` section?

Yes — but it's already here. Claude Code auto-discovers agents from `.claude/agents/`
in the repo you open. This repo ships:

```
.claude/agents/detection-agent.md
.claude/agents/exploitation-agent.md
```

So **as long as you run Claude Code from inside this repo (or add it with `--add-dir`),
the agents load automatically.** Nothing to install. Verify with:

```
/agents
```

You should see `detection-agent` and `exploitation-agent` listed. You can invoke them
by name with `@detection-agent` / `@exploitation-agent`, or just ask in plain English
("audit targets/foo") and Claude routes to them.

> There are two scopes Claude Code reads agents from:
> - **Project:** `.claude/agents/` (this repo — committed, shared with your team)
> - **Personal:** `~/.claude/agents/` (just you, across all projects)
> Keep these two as **project** agents so they travel with the workbench and its data.

---

## 2. One-time setup

```bash
bash scripts/setup.sh          # forge-std + DeFiHackLabs submodule + builds the RAG index
export ETH_RPC_URL=<archive-rpc-url>   # needed ONLY for fork / exploitation runs
```

`ETH_RPC_URL` must be an **archive** node (Alchemy, Infura, QuickNode, or your own) —
forking a historical block needs archive state. For other chains, also export
`ARBITRUM_RPC_URL`, `BSC_RPC_URL`, etc. (see `foundry.toml`).

Smoke-test the knowledge base (no RPC needed):

```bash
python3 scripts/search_kb.py "price from spot reserves flash loan" -k 3
```

---

## 3. Run an audit (the normal flow)

### Step 1 — put the target in place
```
targets/<name>/src/   <-- the contracts you're auditing
```
Copy the client's contracts (or a single `.sol`) under `targets/<name>/src/`.

### Step 2 — detection
In the Claude Code prompt:
```
@detection-agent audit targets/<name>
```
It runs Slither, retrieves similar historical bugs from the knowledge base, reasons
over the call graph, and writes a **ranked** list to:
```
targets/<name>/candidates.json
```
Read it. Each candidate has a `mechanism`, `attack_steps`, `severity`, `confidence`,
and `needs_fork`. The top candidate is what's most likely to actually break.

### Step 3 — exploitation (prove it)
```
@exploitation-agent prove candidate C1 from targets/<name>/candidates.json
```
It copies `templates/Exploit.t.sol`, forks a pinned block, and loops
`write PoC → forge test → read trace → fix` from a fresh unprivileged wallet until an
**invariant assertion breaks** (confirmed) or it gives up with a reason. Results land in:
```
targets/<name>/results/C1.json
targets/<name>/test/C1.t.sol     <-- the runnable PoC
```
Re-run the proof yourself any time:
```bash
forge test --match-path targets/<name>/test/C1.t.sol -vvvv
```

> Run exploitation on **one** candidate at a time. Each run forks state and iterates —
> it's the expensive step. Work down the ranked list; stop when you've proven the
> high-severity ones.

### Step 4 — repeat for the next candidate
```
@exploitation-agent prove candidate C2 from targets/<name>/candidates.json
```

---

## 4. Eval the exploitation agent (self-grading, no RPC target needed beyond a fork)

Point it at a real DeFiHackLabs incident with the solution hidden. A passing PoC that
rediscovers the drain **is** the grade — no human labeling.

```
@exploitation-agent reproduce <incident-name> from DeFiHackLabs (solution hidden)
```

Incidents live under `lib/DeFiHackLabs/src/test/` after `setup.sh`. This is how you
measure whether the agent is actually good before trusting it on a paid engagement.

---

## 5. Grow the knowledge base (makes detection smarter, touches no agent)

Add a markdown finding under `knowledge-base/findings/` following
`knowledge-base/findings/_SCHEMA.md`, then re-index:

```bash
python3 scripts/ingest.py
```

That's the whole point of the two-layer design: adding the 300th audit report changes
zero agent files. The agents only ever call `scripts/search_kb.py`.

---

## 6. Reuse the agents in OTHER repos (git / plugin)

You have two levels, matching the design.

### Level A — pull this workbench per engagement (simplest)
Clone it and work inside it, or point Claude Code at it from the client's repo:

```bash
git clone https://github.com/Leeh-Santos/Contract-ripper.git
cd Contract-ripper
bash scripts/setup.sh
# audit the client's code by copying it into targets/, OR:
claude --add-dir /path/to/client-repo
```
`--add-dir` makes the client's contracts visible to the agents while still loading the
agents + knowledge base from this workbench.

### Level B — package as a Claude Code plugin (reuse across many repos)
Ship the **brains** (agents + skills + scripts) as a plugin so any repo can install
them. The **data does not go in the plugin** — DeFiHackLabs stays a submodule and the
knowledge base stays here.

1. Add a `.claude-plugin/marketplace.json` to a repo (can be this one).
2. In any other repo:
   ```
   /plugin marketplace add Leeh-Santos/Contract-ripper
   /plugin install contract-ripper@contract-ripper
   ```
3. The agents are now available in that repo too; point them at its contracts.

Rule that keeps the layers clean: **the plugin ships the agents; the data is pulled
separately.** You update agents without re-shipping gigabytes, and grow the knowledge
base without re-releasing the plugin.

> Want Level B wired up? Ask and I'll add the `.claude-plugin/marketplace.json` +
> `plugin.json` so `/plugin install` works.

---

## 7. Quick reference

| I want to… | Do this |
|---|---|
| See the agents are loaded | `/agents` |
| Set up the workbench | `bash scripts/setup.sh` |
| Enable fork/exploit runs | `export ETH_RPC_URL=<archive-rpc>` |
| Audit a target | `@detection-agent audit targets/<name>` |
| Prove a candidate | `@exploitation-agent prove candidate C1 from targets/<name>/candidates.json` |
| Re-run a PoC | `forge test --match-path targets/<name>/test/C1.t.sol -vvvv` |
| Eval against ground truth | `@exploitation-agent reproduce <incident> from DeFiHackLabs` |
| Search the knowledge base | `python3 scripts/search_kb.py "<bug shape>" -k 5` |
| Add knowledge | new file in `knowledge-base/findings/`, then `python3 scripts/ingest.py` |
| Use in another repo | clone + `--add-dir`, or package as a plugin (§6) |
