---
id: "0001"
title: ERC-4626 first-depositor share inflation via donation
class: erc4626-inflation
severity: high
source: Solodit
ref: https://github.com/transmissions11/solmate/issues/178
chains: [ethereum]
loss_usd: 0
---

## Invariant broken
Shares minted are proportional to assets deposited; pricePerShare cannot be moved by
an unaccounted token transfer.

## Mechanism
Against an empty vault, the attacker deposits 1 wei and mints 1 share. They then
transfer a large amount of the underlying directly to the vault (a "donation"), which
inflates `totalAssets()` while `totalSupply` stays 1. A victim who now deposits gets
`assets * totalSupply / totalAssets` shares, which rounds down to 0 (or far too few).
The attacker redeems their 1 share for the victim's deposited assets.

## Tell (how detection spots it)
`totalAssets()` implemented as `asset.balanceOf(address(this))` (donatable), first
deposit into an empty vault with no virtual shares / decimals offset, mint path rounds
down. Slither won't flag it directly — it's a call-graph + accounting read.

## Fix
Seed the vault, use virtual shares + a decimals offset (OpenZeppelin ERC4626), or
require a minimum initial deposit. Internal accounting instead of raw balanceOf.

## DeFiHackLabs
Class appears in several vault incidents; reproduce with a local empty-vault deploy
(needs_fork = false).
