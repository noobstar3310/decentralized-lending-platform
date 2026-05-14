# Decentralend — Architecture

> Companion to [../README.md](../README.md) and [../CLAUDE.md](../CLAUDE.md).
> This document describes the *internal* design of the protocol: contracts,
> state, flows, and math. Per-asset risk parameter values live in
> [parameters.md](parameters.md). v1 invariants live in [Invariant.md](Invariant.md).

---

## 1. Overview

_TODO: 2–3 paragraph high-level summary. What the protocol does, what the
key entities are, and what an end-to-end user interaction looks like (supply
→ collateralize → borrow → repay → withdraw, or supply → liquidated)._

## 2. Contract topology

_TODO: ASCII or mermaid diagram of contracts and who calls whom. Should
cover: user → LendingPool → (dToken, debtToken, PriceOracle,
InterestRateStrategy) → underlying ERC-20. Note who holds the underlying
balance (LendingPool? dToken?) and why._

## 3. Contracts

### 3.1 LendingPool

_TODO: Purpose, public interface (supply, withdraw, borrow, repay,
liquidate, plus admin), state it owns (`mapping(address => Reserve)`,
user collateral/debt bitmaps), reentrancy model, pausability._

### 3.2 Reserve (struct)

_TODO: Restate the field table from README, then explain slot packing —
which fields share a slot and why. Note ray vs bps vs wad conventions.
Document any invariants on field combinations (e.g. liqThreshold > ltv)._

### 3.3 dToken (ERC-4626)

_TODO: Why ERC-4626, what `convertToAssets` returns (scaled by
liquidityIndex), what happens on transfer (collateral accounting follows
the token), how `mint`/`burn` are restricted to LendingPool. Rounding
direction for shares ↔ assets._

### 3.4 debtToken (non-transferable)

_TODO: Why non-transferable, how the balance scales with borrowIndex,
how `mint`/`burn` are restricted to LendingPool, what `approve`/`transfer`
revert with._

### 3.5 PriceOracle

_TODO: Chainlink wrapper, per-asset feed registry, staleness check policy
(max age per asset), decimals normalization, behavior on stale or zero
price (revert, no fallback)._

### 3.6 InterestRateStrategy

_TODO: One contract per Reserve, or one shared contract parameterized per
asset? Document the choice. Inputs: utilization, totalDebt,
totalLiquidity. Outputs: borrow rate, supply rate. Math lives in §5._

## 4. Core flows

For each flow: pre-conditions, state changes (in order), post-conditions,
events emitted, and revert conditions.

### 4.1 Supply

_TODO_

### 4.2 Withdraw

_TODO — must include post-withdraw health-factor check if the asset was
enabled as collateral._

### 4.3 Borrow

_TODO — must include health-factor pre-check, available liquidity check,
and frozen/active checks._

### 4.4 Repay

_TODO — partial vs full repay; behavior when `amount > debt`._

### 4.5 Liquidate

_TODO — close factor (max fraction of debt repayable per call), liquidation
bonus, choice of which collateral to seize, partial vs full liquidation,
bad-debt handling (v1: not socialized — see §9)._

## 5. Interest accrual & indexes

### 5.1 Index math

_TODO: how `liquidityIndex` and `borrowIndex` evolve between updates.
Linear approximation vs compound. Why ray (1e27) precision. Where the
index update is triggered (every state-changing entry into LendingPool)._

### 5.2 Utilization-based rate curve

_TODO: kinked model. Below kink: borrow rate goes from `baseRate` to
`baseRate + slope1`. Above kink: from `baseRate + slope1` to
`baseRate + slope1 + slope2`. Supply rate = borrow rate × utilization ×
(1 − reserveFactor). Units (ray per second vs ray per year) — pick one and
state it._

### 5.3 Reserve factor

_TODO: how the treasury-bound interest is split off, where it accumulates,
and how it's claimed by the protocol owner._

## 6. Health factor & cross-asset accounting

_TODO: full formula.
`HF = Σ(collateral_i × liqThreshold_i × price_i) / Σ(debt_j × price_j)`.
Units, rounding direction (round HF down to be conservative), edge case
when debt = 0 (HF = ∞ / `type(uint256).max`)._

## 7. Oracle integration

_TODO: feed addresses (live on Sepolia, listed in
[parameters.md](parameters.md)), per-asset staleness window, behavior on
stale price (revert), behavior on negative price (revert)._

## 8. Access control

_TODO: Ownable. What's owner-gated (listing new reserves, updating
parameters, freezing/unfreezing, claiming reserve factor). Known
centralization caveat — production would need multisig + timelock._

## 9. Known limitations (v1)

_TODO: enumerate the out-of-scope list from [../CLAUDE.md](../CLAUDE.md)
plus any v1 shortcuts:_

- _No flash loans._
- _No eMode / isolation mode._
- _No bad-debt socialization — residual debt sits on the protocol's books._
- _Liquidations are simple (no Dutch auction, no aggregator-friendly
  paths)._
- _Admin via `Ownable` only._

## 10. Open design questions

_TODO: things still being decided. Strike through as resolved with the
decision recorded alongside._
