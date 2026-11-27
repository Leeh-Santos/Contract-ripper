# Attack-class checklist

The detection-agent reads this once per run and treats it as the menu of what to look
for. Each class names the invariant it breaks and the tell to grep for. Ordered by how
often it shows up in real DeFi losses, not alphabetically.

## 1. Oracle / price manipulation
- **Invariant broken:** reported price reflects fair market value.
- **Tell:** `getReserves()`, spot balance used as price, single-source oracle, no TWAP,
  `balanceOf(pool)` in a pricing path.
- **Exploit shape:** flash-loan skew the pool, act at the bad price, unwind.

## 2. Flash-loan-amplified logic
- **Invariant:** protocol assumptions hold regardless of a caller's transient capital.
- **Tell:** governance by token balance, collateral/debt math that trusts current
  balances, same-block deposit+action.

## 3. Reentrancy — classic, cross-contract, and read-only
- **Invariant:** state is consistent across an external call.
- **Tell:** external call (token transfer, ETH send, callback) BEFORE state update;
  a `view` used by *another* contract while this one is mid-update (read-only
  reentrancy); ERC777/ERC721 hooks, `call{value}`.

## 4. ERC-4626 / vault inflation & donation
- **Invariant:** shares minted are proportional to assets; pricePerShare monotonic.
- **Tell:** empty-vault first deposit, `totalAssets()` = `balanceOf(this)` (donatable),
  no virtual shares / decimals offset, rounding down on mint.

## 5. Rounding & precision
- **Invariant:** rounding never favors the user over the protocol.
- **Tell:** division before multiplication, `mulDiv` direction, truncation on
  share<->asset conversion, fee math.

## 6. Upgradeable proxy bugs
- **Invariant:** implementation is initialized and storage layout is stable.
- **Tell:** uninitialized implementation (`initialize` callable by anyone), missing
  `_disableInitializers`, storage-gap mismatch, `delegatecall` to attacker-influenced
  target, selfdestruct in impl.

## 7. Signature issues (EIP-712)
- **Invariant:** each authorization is unique, bound to chain+contract, non-replayable.
- **Tell:** missing nonce, missing/weak domain separator, `ecrecover` without
  malleability guard (s-value), permit replay across chains.

## 8. Accounting / invariant drift in complex protocols
- **Invariant:** sum(user balances) == protocol-held assets; debt == collateral math.
- **Tell:** cached totals that desync from reality, reward accounting, fee-on-transfer
  / rebasing tokens breaking `amount` assumptions.

## 9. Access control / privilege
- **Invariant:** state-changing power is gated to intended roles.
- **Tell:** missing modifier, `tx.origin` auth, public `init`, unprotected
  `setOwner`/`setAdmin`, default-open functions.

## 10. Cross-chain / bridge logic
- **Tell:** message replay, unverified source, mint-without-lock, nonce gaps.

## 11. Account abstraction (ERC-4337)
- **Tell:** paymaster griefing, validation/execution separation abuse, storage access
  rule violations.

## 12. MEV / ordering & transient-storage (EIP-1153) edge cases
- **Tell:** assumptions about tx ordering, slippage left at 0, transient storage not
  cleared across calls within a tx.

---

For any match, the detection-agent must still write the concrete `attack_steps` from a
fresh wallet. A class match is a lead, not a finding.
