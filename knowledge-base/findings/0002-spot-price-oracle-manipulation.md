---
id: "0002"
title: Spot-reserve price oracle manipulation via flash loan
class: oracle-manipulation
severity: high
source: rekt
ref: https://rekt.news/
chains: [ethereum, bsc]
loss_usd: 100000000
---

## Invariant broken
The price used for collateral valuation / minting reflects fair market value, not a
momentarily skewed AMM pool.

## Mechanism
The protocol prices an asset from an AMM pool's spot reserves (e.g. `getReserves()` or
`balanceOf(pool)`) at call time. The attacker flash-borrows, swaps to skew the pool so
the target asset is mispriced, then in the same transaction calls the victim function
(borrow against inflated collateral, mint, or redeem) at the bad price, unwinds the
swap, and repays the flash loan — keeping the difference.

## Tell (how detection spots it)
Pricing path reads `getReserves()`, `token.balanceOf(pool)`, or a single-source
`latestAnswer` with no TWAP / no sanity bounds. Any function that both reads such a
price AND moves value in the same call is a candidate. Grep for `getReserves`,
`balanceOf` inside price/quote functions, `latestAnswer`.

## Fix
Use a manipulation-resistant oracle (Chainlink with staleness + deviation checks, or a
TWAP over enough blocks), and never price off same-block spot reserves.

## DeFiHackLabs
Many incidents of this class under src/test/ — fork the block before the exploit tx,
take a flash loan from Aave/Balancer/Uniswap, skew, act, unwind (needs_fork = true).
