# Decentralend — Risk Parameters

> Companion to [architecture.md](architecture.md). This file lists the
> per-asset risk parameters and interest-rate curve constants for v1.
> Rationale for each value sits under the relevant table.

---

## Conventions

- **Basis points (bps):** `10000 = 100%`. Used for LTV, liquidation
  threshold, liquidation bonus, and reserve factor.
- **Ray (`1e27`):** used for interest indexes and rate constants.
- **Wad (`1e18`):** not used for risk parameters; reserved for some math
  intermediates.
- **Liquidation threshold > LTV** is enforced at listing time.

## Per-asset risk parameters

| Asset | LTV (bps) | Liq. threshold (bps) | Liq. bonus (bps) | Reserve factor (bps) |
|---|---|---|---|---|
| USDC | _TODO_ | _TODO_ | _TODO_ | _TODO_ |
| WETH | _TODO_ | _TODO_ | _TODO_ | _TODO_ |
| WBTC | _TODO_ | _TODO_ | _TODO_ | _TODO_ |

**Rationale:**

- _TODO USDC — why this LTV / threshold / bonus / reserve factor._
- _TODO WETH — same._
- _TODO WBTC — same._

Stablecoins should receive higher LTV and tighter
(liqThreshold − LTV) gap than volatile assets, because their price risk is
lower. Volatile assets should carry a larger liquidation bonus to reward
liquidators for taking on price risk.

## Interest rate curves

The kinked model is parameterized per asset by:

- `baseRate` — borrow rate at zero utilization.
- `slope1` — slope of the curve below the kink.
- `slope2` — slope of the curve above the kink.
- `optimalUtilization` — the kink point, in bps.

| Asset | baseRate | slope1 | slope2 | optimalUtilization (bps) |
|---|---|---|---|---|
| USDC | _TODO_ | _TODO_ | _TODO_ | _TODO_ |
| WETH | _TODO_ | _TODO_ | _TODO_ | _TODO_ |
| WBTC | _TODO_ | _TODO_ | _TODO_ | _TODO_ |

_Note: pin the units (ray per second vs ray per year) in
[architecture.md §5.2](architecture.md#52-utilization-based-rate-curve)
and refer back here._

**Rationale:**

- _TODO — stablecoins get a flatter curve and higher kink; volatile assets
  get a steeper post-kink slope to defend liquidity._

## Oracle configuration (Sepolia)

| Asset | Chainlink feed (Sepolia) | Heartbeat | Staleness threshold |
|---|---|---|---|
| USDC | _TODO 0x… (USDC/USD)_ | _TODO_ | _TODO_ |
| WETH | _TODO 0x… (ETH/USD)_ | _TODO_ | _TODO_ |
| WBTC | _TODO 0x… (BTC/USD)_ | _TODO_ | _TODO_ |

The staleness threshold should be ≥ the feed's heartbeat. Anything older
causes the oracle to revert; the protocol does not fall back to a cached
price.

## Change log

_Record each parameter change with date and rationale._

- _TODO 2026-MM-DD — initial v1 values set._
