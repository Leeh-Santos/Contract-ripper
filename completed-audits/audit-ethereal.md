# Ethereal — Smart Contract Security Audit

**Prepared for:** Ethereal
**Contract reviewed:** `Ethereal` (NFTfi — ERC-721 "Gems" backed by ETH / wstETH)
**Date:** 27 November 2026
**Overall result:** **1 High**, **2 Medium**, **1 Low**. One issue causes **loss of user
funds** and was demonstrated with a working proof-of-concept. **We recommend fixing the
High and both Medium issues before any mainnet deployment.**

---

## 1. Overview

Ethereal lets users mint NFTs ("Gems"), each fully backed by either native ETH or
wrapped staked ETH (wstETH). Users pay a fixed price to mint and later redeem the Gem to
get their backing asset back, minus a small fee.

We reviewed the contract for issues that could lead to loss of funds, protocol
insolvency, or denial of service. The most serious finding is an **accounting flaw that
lets the protocol become insolvent** — honest users who backed their Gems with ETH can
be left unable to withdraw their money. We built a test that reproduces this end-to-end.

### Findings summary

| # | Issue | Severity | Can users lose funds? |
|---|-------|----------|-----------------------|
| **1** | ETH and wstETH fees are mixed in one counter and paid out as ETH → insolvency | **High** | **Yes — demonstrated** |
| 2 | wstETH fees can never be withdrawn / fee withdrawal can get stuck | Medium | Lost protocol revenue |
| 3 | Several owner controls can move or drain user funds | Medium | Yes, if owner key is misused/compromised |
| 4 | Approved managers cannot redeem on an owner's behalf | Low | No (feature broken) |

---

## 2. Findings

### Finding 1 — Fee accounting mixes ETH and wstETH, draining ETH backing — **HIGH**

**What's wrong.**
The contract keeps **one** running total of collected fees. But ETH redemptions add to
it in units of ETH, while wstETH redemptions add to it in units of wstETH — two
different assets counted as if they were the same number. When the owner withdraws fees,
the contract pays the **entire** total out in **native ETH**.

Because wstETH deposits are immediately converted away (the contract holds no ETH from
them), the only ETH in the contract is the money backing users' ETH Gems. So withdrawing
the "fees" actually pays out ETH that belongs to those users.

**Why it matters.**
In the protocol's intended setup (some Gems backed by ETH, some by wstETH), a normal fee
withdrawal silently takes money from ETH-Gem holders. Worse, **any user** can deliberately
inflate the fee total by minting and redeeming wstETH Gems — making the next fee
withdrawal drain even more ETH from other people's backing. The result is **insolvency**:
honest users who deposited ETH can no longer redeem.

**We proved it.**
In our test:
- A user deposits **1.0 ETH** to mint an ETH Gem (contract now holds 1.0 ETH for them).
- An attacker mints and redeems wstETH Gems, adding **0.1 ETH worth** of wstETH-unit fees
  to the shared counter — without adding any real ETH.
- The owner makes a routine fee withdrawal → the contract is left with **0.9 ETH**.
- The honest user tries to redeem their Gem → **the transaction fails; their funds are
  stuck.**

**Recommended fix.**
Track ETH fees and wstETH fees **separately**, and pay each out in its own asset (ETH
fees in ETH, wstETH fees in wstETH). Never pay one asset's fees out of another asset's
balance. More broadly, keep the ETH and wstETH funds accounted for independently so the
two pools can never be mixed.

---

### Finding 2 — wstETH fees are stranded / fee withdrawal can revert — **MEDIUM**

**What's wrong.**
The same single-counter design has a second consequence: there is **no way to pay fees
out in wstETH at all**. Fees earned on wstETH redemptions are added to the counter but
can only ever leave as ETH. In a wstETH-only deployment the contract holds almost no ETH,
so the fee-withdrawal call simply **fails**, and all that fee revenue is **permanently
locked** in the contract.

**Why it matters.**
Lost protocol revenue, and a withdrawal function that can be permanently bricked
depending on configuration.

**Recommended fix.**
The separate-per-asset accounting recommended for Finding 1 resolves this — add a path to
withdraw wstETH fees as wstETH.

---

### Finding 3 — Powerful owner controls over user funds — **MEDIUM**

**What's wrong.**
Several owner-only functions can move or endanger user funds:
- The owner can grant **any address unlimited permission to move the contract's wstETH**.
- The owner can **change which token is used as the backing asset** at any time.
- The owner can **flip a live collection between "ETH-backed" and "wstETH-backed"**,
  which would make existing Gems pay out from the wrong pool / in the wrong asset.

**Why it matters.**
These require the owner account, so they aren't exploitable by outsiders — but they are a
significant trust and key-compromise risk: a mistaken or malicious owner action (or a
stolen owner key) could drain or mis-pay user funds.

**Recommended fix.**
Lock down these controls: make the backing token fixed (or changeable only via a
timelock), restrict the wstETH-approval function to a known, trusted address, and prevent
changing a collection's asset type or price once Gems are already in circulation.
Consider a multisig / timelock for the owner role.

---

### Finding 4 — Approved managers cannot redeem — **LOW**

**What's wrong.**
The redeem function is supposed to allow a Gem owner's approved manager (operator) to
redeem on their behalf, but an internal step rejects anyone who isn't the Gem's direct
owner, so approved managers always fail.

**Why it matters.**
No funds at risk — it's a broken feature / usability issue.

**Recommended fix.**
Redeem the Gem from its actual owner rather than from the caller.

---

## 3. Recommendation

| Priority | Action |
|----------|--------|
| **Before mainnet** | Fix Finding 1 and Finding 2 (separate ETH vs wstETH fee accounting; keep the two asset pools fully independent). |
| **Strongly advised** | Address Finding 3 — constrain owner powers (immutable/timelocked backing token, scoped approvals, no asset-type changes on live collections, multisig owner). |
| **Recommended** | Fix Finding 4 so delegated redemption works. |
| **After fixes** | Re-audit the revised contract to confirm the fixes and check for regressions. |

The High-severity issue is a direct path to user fund loss and was reproduced with a
working test, so we consider remediation of Findings 1 and 2 a blocker for launch.

---

*This report covers the single contract reviewed and the issues identified during the
engagement. A security review reduces risk but cannot guarantee the absence of all
vulnerabilities. We recommend a re-review after fixes are applied.*
