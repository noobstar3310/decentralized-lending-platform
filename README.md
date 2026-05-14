# Decentralend

A decentralized, over-collateralized money market protocol modeled on Aave V2's
core mechanics. Users supply listed assets to earn interest from borrowers, and
borrowers post supplied assets as collateral to borrow other listed assets
against them.

> **Status:** Educational portfolio project. Not audited. Not production-ready.
> See [Scope and Limitations](#scope-and-limitations) for what is and isn't built.

## Overview

Decentralend is a multi-asset lending market where each supported asset has its
own pool, its own interest rate curve, and its own risk parameters. A single
user can simultaneously supply multiple assets, mark some or all of them as
collateral, and borrow any combination of other supported assets — with
position health computed across their entire portfolio.

At launch, three assets are supported: **USDC**, **WETH**, and **WBTC**. All
three can be supplied, used as collateral, and borrowed.

### How it works at a glance

- **Suppliers** deposit a supported asset and receive a **dToken** (an
  ERC-4626-compliant receipt token). The dToken's exchange rate against the
  underlying asset increases over time as borrowers pay interest, so suppliers
  earn yield passively.
- **Borrowers** deposit a supported asset, optionally enable it as collateral,
  and borrow a different supported asset against it. Debt accrues interest at
  a rate determined by the borrowed asset's utilization curve.
- **Liquidators** monitor positions off-chain and call `liquidate` when a
  borrower's health factor drops below 1, repaying part of the borrower's debt
  in exchange for the borrower's collateral plus a liquidation bonus.
- **Price oracles** (Chainlink) provide USD prices for each supported asset.
  All collateral and debt valuations route through these feeds, including
  USDC — the protocol does not assume `1 USDC = $1`.

### Per-asset parameters

Each listed asset has its own:

- **Loan-to-Value (LTV)** — the maximum fraction of an asset's USD value a user
  can borrow against, when that asset is used as collateral.
- **Liquidation threshold** — the fraction at which the position becomes
  eligible for liquidation. Always slightly above the LTV.
- **Liquidation bonus** — the discount a liquidator receives on seized
  collateral.
- **Reserve factor** — the fraction of borrower interest that accrues to the
  protocol treasury rather than to suppliers.
- **Interest rate curve** — a kinked, utilization-based model returning borrow
  and supply rates as a function of how much of the pool is currently lent out.

Stablecoins receive higher LTVs and gentler interest curves than volatile
assets, reflecting their lower price risk. The full parameter table is in
[docs/parameters.md](docs/parameters.md).

## Deployment

Decentralend is deployed on the **Sepolia testnet**. Sepolia is used because it
has live Chainlink price feeds for all three supported assets (ETH/USD,
BTC/USD, and USDC/USD), making the deployment fully functional end-to-end
rather than mocked.

Deployed contract addresses and verified Etherscan links will be listed here
once deployed.

## Scope and Limitations

### In scope

- Supply, withdraw, borrow, repay, and liquidate flows
- Three listed assets: USDC, WETH, WBTC — all suppliable, all borrowable, all
  usable as collateral
- Per-asset utilization-based interest rate model with a kink
- Cross-asset collateral and debt with unified health factor
- ERC-4626-compliant dTokens for suppliers
- Tokenized non-transferable debt positions
- Chainlink price feeds with staleness checks
- Configurable per-asset risk parameters
- Foundry test suite including unit, fork, and invariant tests
- Sepolia testnet deployment with verified contracts

### Out of scope

These are real features of production lending protocols, omitted from v1 to
keep the scope focused and the codebase reviewable:

- **Flash loans** — straightforward to add as v2; intentionally deferred.
- **eMode / efficiency mode** for correlated assets (Aave V3 feature).
- **Isolation mode** for risky listed assets (Aave V3 feature).
- **Stable borrow rate mode** — deprecated in Aave itself; not worth implementing.
- **Governance** — admin functions are gated by `Ownable` in v1. Production
  would require a multisig with a timelock; this is documented as a known
  centralization risk.
- **Liquidity mining or reward tokens.**
- **Cross-chain support.**
- **Bad debt socialization** — if a position is liquidated and residual debt
  remains, that debt sits on the protocol's books. Documented as a known v1
  limitation.

## Conventions

Project-wide standards. Reviewers reading the code can rely on these:

- **Compiler:** Solidity `0.8.24`, pinned (no caret). Every contract
  declares `pragma solidity 0.8.24;`.
- **Errors:** custom errors (`error InsufficientCollateral();`) over
  `require` strings. Tests assert reverts by selector
  (`vm.expectRevert(IErrors.X.selector)`), not by string match.
- **Risk parameters:** basis points (`10000 = 100%`).
- **Interest indexes and rates:** ray precision (`1e27`).
- **Slot packing:** the `Reserve` struct uses small types (`uint16`,
  `uint8`, `uint40`, `bool`) deliberately to share a single storage
  slot — do not widen types for "cleanliness".
- **Deployment auth:** Foundry keystore (`cast wallet import`), not
  raw private keys. See [.env.example](.env.example) for the
  expected workflow.
- **Formatting:** `forge fmt` is enforced in CI. Run `forge fmt`
  locally before pushing.
- **Static analysis:** Slither runs in CI and fails on high-severity
  findings. Run `slither .` locally before opening a PR.

## Architecture

_To be expanded — see [docs/architecture.md](docs/architecture.md)._

[...rest of README to follow: Contracts, Setup, Testing, Deployment Guide, License...]

### Entity: Reserve

A Reserve represents one supported asset and all the protocol-level state
associated with that asset. There is one Reserve per listed token. v1 has
three Reserves: USDC, WETH, WBTC.

**Identity:** A Reserve is uniquely identified by the address of its
underlying ERC-20 token.

**Attributes:**

| Field | Type (intended) | Purpose |
|---|---|---|
| `underlying` | address | The ERC-20 token this Reserve represents. |
| `vToken` | address | Address of the ERC-4626 receipt token for suppliers of this asset. |
| `debtToken` | address | Address of the non-transferable debt token for borrowers of this asset. |
| `priceFeed` | address | Chainlink USD price feed for this asset. |
| `interestRateStrategy` | address | Contract implementing the kinked rate curve for this asset. |
| `liquidityIndex` | uint128 (ray, 1e27) | Cumulative interest factor for suppliers. Starts at 1e27, grows monotonically. |
| `borrowIndex` | uint128 (ray, 1e27) | Cumulative interest factor for borrowers. Starts at 1e27, grows monotonically. |
| `currentLiquidityRate` | uint128 (ray) | Latest computed supply APR. Updated on every state change. |
| `currentBorrowRate` | uint128 (ray) | Latest computed borrow APR. Updated on every state change. |
| `lastUpdateTimestamp` | uint40 | Block timestamp of the last index update. |
| `ltv` | uint16 (basis points) | Max borrow ratio when used as collateral. e.g. 7500 = 75%. |
| `liquidationThreshold` | uint16 (bps) | Ratio at which position becomes liquidatable. |
| `liquidationBonus` | uint16 (bps) | Discount given to liquidators. e.g. 500 = 5%. |
| `reserveFactor` | uint16 (bps) | Fraction of borrower interest accruing to protocol. |
| `decimals` | uint8 | Decimals of the underlying token. Cached to save SLOADs. |
| `isActive` | bool | Whether this Reserve is enabled. |
| `isFrozen` | bool | If frozen, no new supplies/borrows; existing positions can still repay/withdraw. |

**Storage location:** `mapping(address asset => Reserve reserveData)` on the
LendingPool contract.

**Notable design decisions:**

- `liquidityIndex` and `borrowIndex` are stored in *ray* (1e27) precision, not
  wad (1e18), to retain accuracy across many small interest accruals. This
  follows Aave's convention.
- Risk parameters (LTV, threshold, bonus, reserve factor) are stored in basis
  points (1/10000) rather than as fractions, because basis points are the
  industry standard for these values and avoid floating-point ambiguity.
- Several fields are packed into a single storage slot where possible
  (`uint16` risk parameters, `uint8` decimals, `bool` flags) to reduce SLOAD
  costs. Detailed slot packing is documented in the contract source.