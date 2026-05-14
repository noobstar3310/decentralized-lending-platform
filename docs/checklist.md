# Decentralend — Build Checklist

> Sequenced from foundations → flows → deployment. Tick boxes as you go.
> Each phase has a **gate**: don't advance to the next phase until the
> gate passes. Items inside a phase may be reordered freely; items
> across phases generally cannot, because later phases depend on
> earlier state.
>
> **Cross-references:**
> - Architecture: [architecture.md](architecture.md)
> - Risk parameters: [parameters.md](parameters.md)
> - Invariants: [Invariant.md](Invariant.md)
> - Security review skill:
>   [../.claude/skills/solidity-security/SKILL.md](../.claude/skills/solidity-security/SKILL.md)

---

## Phase 0 — Repo hygiene (one-time)

- [x] Pin `solc` version in `foundry.toml` (no caret) — match the
      pragma in every contract.
- [x] Set `optimizer_runs` in `foundry.toml` (200 is the Aave default;
      tune later only with evidence).
- [x] Add `.env.example` listing required env vars (SEPOLIA_RPC_URL,
      ETHERSCAN_API_KEY, ACCOUNT, SENDER — keystore auth, no
      `PRIVATE_KEY`).
- [x] CI workflow: `forge build` + `forge test` on every PR.
- [x] Add **Slither** to CI (fail the job on high severity).
- [x] Choose error style: **custom errors** (`error
      InsufficientCollateral();`) over `require` strings — cheaper, easy
      to grep, easy to assert with `vm.expectRevert(Foo.selector)`.

**Gate:** CI is green on an empty test suite.

---

## Phase 1 — Math and errors libraries

Every subsequent phase depends on these. Get them right first.

- [ ] `src/libraries/WadRayMath.sol` — `rayMul`, `rayDiv`, `wadMul`,
      `wadDiv`, `wadToRay`, `rayToWad`. Half-up rounding inside the
      library.
- [ ] `src/libraries/PercentageMath.sol` — `percentMul`, `percentDiv`
      for basis-point arithmetic (10000 = 100%).
- [ ] `src/libraries/Errors.sol` — single file collecting every custom
      error the protocol throws. Group by contract.
- [ ] Unit tests:
  - Known-vector checks (compare against a calculator).
  - Round-trip checks: `rayDiv(rayMul(x, y), y) ≈ x` within rounding.
  - Overflow/underflow boundary cases.

**Gate:** Math libs have ≥ 95% line + branch coverage and **no
`unchecked` block lacks a one-line bound comment**.

---

## Phase 2 — PriceOracle

Read-only contract; can be built in parallel with Phase 3.

- [ ] `src/PriceOracle.sol` wrapping Chainlink's
      `AggregatorV3Interface`.
- [ ] Per-asset feed registry: `mapping(address => AggregatorV3Interface)`.
- [ ] Per-asset **staleness threshold**:
      `mapping(address => uint256)`, set by owner at listing time, must
      be ≥ that feed's heartbeat.
- [ ] `getAssetPrice(asset)` reverts on every failure mode:
  - `answer <= 0`
  - `updatedAt == 0` (round not initialised)
  - `block.timestamp - updatedAt > staleness`
  - `answeredInRound < roundId` (Chainlink-documented stale-round check)
- [ ] Owner-only `setFeed(asset, feed, staleness)`.
- [ ] Unit tests with a mock aggregator covering each revert path.
- [ ] **Fork test** on Sepolia: read each of the three real feeds
      (USDC/USD, ETH/USD, BTC/USD); sanity-check the price ranges.

**Gate:** Fork test passes against live Sepolia Chainlink feeds.

**Security check:** see
[security skill §4.1](../.claude/skills/solidity-security/SKILL.md#41-oracle-manipulation-and-staleness) — no fallback path, every failure
must revert.

---

## Phase 3 — InterestRateStrategy

Read-only contract; can be built in parallel with Phase 2.

- [ ] `src/interfaces/IInterestRateStrategy.sol` — one function:
      `calculateRates(uint256 totalLiquidity, uint256 totalBorrow,
      uint256 reserveFactor)` returning `(borrowRate, supplyRate)` in
      ray per year.
- [ ] `src/DefaultReserveInterestRateStrategy.sol` — constructor takes
      `baseRate`, `slope1`, `slope2`, `optimalUtilization`. All
      **immutable**.
- [ ] Implement the kinked curve described in
      [architecture.md §5.2](architecture.md#52-utilization-based-rate-curve).
- [ ] Supply-rate formula: `borrowRate × utilization × (1 −
      reserveFactor)`.
- [ ] Edge cases:
  - `totalLiquidity == 0 && totalBorrow == 0` → return
    `(baseRate, 0)`.
  - Cap `utilization` at 100% (Aave convention).
- [ ] Unit tests at boundary points: zero utilization, the kink, 100%,
      and one point above the kink. Each compared against hand-computed
      values.

**Gate:** Hand-computed rates match for all four boundary points.

---

## Phase 4 — Token contracts

### 4a. dToken (ERC-4626 receipt token)

- [ ] `src/dToken.sol` inheriting OpenZeppelin's `ERC4626`.
- [ ] Constructor: underlying address, LendingPool address (immutable),
      name, symbol.
- [ ] `onlyLendingPool` modifier. **Only LendingPool** may call
      `mint` and `burn`.
- [ ] Override `totalAssets()` to return what LendingPool reports for
      this reserve — not just the contract's underlying balance
      (otherwise donated tokens look like yield).
- [ ] Override `_decimalsOffset()` (OZ 5.x) to add **virtual shares**
      — mitigates the inflation attack.
- [ ] Tests:
  - Standard ERC-4626 conformance.
  - **Donation attack test**: attacker deposits 1 wei, donates a large
    amount of underlying directly to the contract, second depositor
    still receives non-zero shares.
  - Only LendingPool can mint/burn.

**Security check:** see
[security skill §4.2](../.claude/skills/solidity-security/SKILL.md#42-erc-4626-inflation--donation-attack)
— donation attack test must pass.

### 4b. debtToken (non-transferable, scaled)

- [ ] `src/debtToken.sol` inheriting OZ `ERC20`.
- [ ] Override `transfer`, `transferFrom`, `approve`, `allowance` to
      revert with a `NotTransferrable` custom error.
- [ ] Store **scaled** balances internally; `balanceOf(user)` returns
      `scaled × currentBorrowIndex / RAY` (debt grows naturally with
      the index).
- [ ] `mint` and `burn` restricted to LendingPool.
- [ ] Tests:
  - All four ERC-20 movement functions revert.
  - Balance grows over time as borrow index advances
    (use `vm.warp`).

**Security check:** see
[security skill §4.8](../.claude/skills/solidity-security/SKILL.md#48-debttoken-non-transferability)
— non-transferability asserted explicitly in tests.

---

## Phase 5 — LendingPool: state + accrual chassis

Build the data structures and the index-update routine **before** any
flow. No external write functions yet.

- [ ] `src/LendingPool.sol` — define the `Reserve` struct exactly as
      documented in
      [README.md "Entity: Reserve"](../README.md#entity-reserve). Mind
      the slot-packing order (small types adjacent).
- [ ] `mapping(address => Reserve)` keyed by underlying.
- [ ] User config: `mapping(address => UserConfig)` where `UserConfig`
      is a bitmap (one bit per reserve for "is collateral", one for
      "has debt"). 256 reserves max — fine for v1's 3.
- [ ] `_updateState(asset)` — advances `liquidityIndex` and
      `borrowIndex` to the current block from the previously stored
      rates × elapsed time. Linear approximation is acceptable;
      document the choice in
      [architecture.md §5.1](architecture.md#51-index-math).
- [ ] `_updateInterestRates(asset)` — call the strategy with the new
      totals; store new rates and `lastUpdateTimestamp`.
- [ ] `initReserve(asset, dToken, debtToken, irStrategy, params)` —
      owner-only listing function. Validate:
  - `liqThreshold > ltv`
  - `ltv > 0`, `liqBonus > 0`, `reserveFactor <= 10000`
  - All four addresses non-zero
  - Asset not already listed
- [ ] Setters for risk parameters (owner-only, each validates the
      relevant invariant).
- [ ] Unit tests:
  - Index advances correctly over time with a fixed rate.
  - Listing the same asset twice reverts.
  - `liqThreshold ≤ ltv` reverts at listing.

**Gate:** Time-travel tests show indexes growing as expected against a
hand-computed rate.

---

## Phase 6 — Lending flows

Every external entry point's **first** action is `_updateState` +
`_updateInterestRates` for every reserve the call touches. This is the
single most common source of subtle accounting bugs.

**Security check:** see
[security skill §4.7](../.claude/skills/solidity-security/SKILL.md#47-index-accrual-order).

### 6a. `supply(asset, amount, onBehalfOf)`

- [ ] Validate: amount > 0, reserve active, reserve not frozen.
- [ ] Pull underlying via `SafeERC20.safeTransferFrom`.
- [ ] Mint dToken at the current `liquidityIndex` ratio.
- [ ] Set the user's "is collateral" bit for this reserve (initially
      on; user can disable later if you add that toggle).
- [ ] Emit `Supply(user, asset, amount, onBehalfOf)`.
- [ ] Tests: balance accounting, multiple users, second supply after
      time has passed (index advanced).

### 6b. `withdraw(asset, amount, to)`

- [ ] Compute scaled shares from `amount`.
- [ ] Burn dToken.
- [ ] Transfer underlying out via `SafeERC20.safeTransfer`.
- [ ] **If** the user has the "is collateral" bit set for this asset:
      recompute HF after the withdrawal, revert if < 1. Round HF
      **down**.
- [ ] Clear the "is collateral" bit if balance now zero.
- [ ] Emit `Withdraw`.

**Security check:** HF rounding direction — see
[security skill §4.3](../.claude/skills/solidity-security/SKILL.md#43-health-factor-rounding-direction).

### 6c. `borrow(asset, amount, onBehalfOf)`

- [ ] Validate: reserve active, not frozen, amount > 0.
- [ ] Check the pool has enough underlying available
      (`totalLiquidity − totalBorrow ≥ amount`).
- [ ] Compute prospective HF *after* the borrow, round **down**.
      Revert if < 1.
- [ ] **Self-collateralization guard:** if the borrowed asset is also
      enabled as collateral for the borrower, decide the policy and
      document it.
      See [security skill §4.6](../.claude/skills/solidity-security/SKILL.md#46-borrow-of-collateral--self-collateralization-loop).
- [ ] Mint debt token (scaled by current `borrowIndex`).
- [ ] Set the user's "has debt" bit for this reserve.
- [ ] Transfer underlying out.
- [ ] Emit `Borrow`.

### 6d. `repay(asset, amount, onBehalfOf)`

- [ ] Cap `amount` at the current debt balance (no overpay; refund the
      excess implicitly by reducing the pulled amount).
- [ ] Pull underlying via `SafeERC20`.
- [ ] Burn the scaled portion of debt token.
- [ ] Clear "has debt" bit if debt now zero.
- [ ] Emit `Repay`.

**Gate (Phase 6 as a whole):** A 4-step integration test passes —
Alice supplies WETH and USDC; Bob supplies USDC; Bob borrows WETH
against his USDC; Bob repays. After the sequence: Bob's debt-token
balance is zero, every index has moved coherently, every user
config bitmap is in the expected state.

---

## Phase 7 — Liquidation

- [ ] `liquidate(borrower, collateralAsset, debtAsset, repayAmount)`.
- [ ] Recompute HF for the borrower; revert if HF ≥ 1.
- [ ] Cap `repayAmount` by the **close factor** — 50% of the
      borrower's debt in `debtAsset`. Aave V2 convention.
- [ ] Compute seized collateral:
      `repayAmount × debtPrice / collPrice × (1 + liqBonus)`.
      Be careful with decimal normalization — see
      [security skill §4.9](../.claude/skills/solidity-security/SKILL.md#49-cross-asset-hf-unit-consistency).
- [ ] Pull `repayAmount` of `debtAsset` from the liquidator.
- [ ] Burn the borrower's debt by `repayAmount` (scaled).
- [ ] Transfer the seized dToken from borrower to liquidator (decide
      and document whether liquidator receives dTokens or underlying).
- [ ] Emit `Liquidation`.
- [ ] Tests:
  - Healthy position cannot be liquidated.
  - One call cannot exceed the close factor.
  - Bonus math at boundary decimals (e.g. USDC repay vs WBTC seize).

**Security check:**
[security skill §4.4](../.claude/skills/solidity-security/SKILL.md#44-liquidation-mev-and-sandwichability)
— add a NatSpec comment on `liquidate` noting MEV exposure.

---

## Phase 8 — Admin and lifecycle

These do not block lending flows; build incrementally.

- [ ] `freezeReserve(asset)` — blocks **new** supply and borrow only.
      Repay and withdraw must still work.
      See [security skill §4.10](../.claude/skills/solidity-security/SKILL.md#410-pausability-vs-freeze-semantics).
- [ ] `unfreezeReserve(asset)`.
- [ ] `setReserveFactor(asset, bps)`.
- [ ] `setLtv(asset, bps)`, `setLiquidationThreshold(asset, bps)`,
      `setLiquidationBonus(asset, bps)` — each validates the relevant
      invariant.
- [ ] `claimReserveFactor(asset, to)` — sweeps protocol-bound interest
      to a treasury address.
- [ ] All admin gated by `Ownable.onlyOwner`. Add a NatSpec note about
      the v1 centralisation caveat.
- [ ] **Global pause** using OZ `Pausable` — emergency only; halts
      everything including repay/withdraw. Document that this is for
      incident response, not routine use.

---

## Phase 9 — Deployment to Sepolia

- [ ] `script/HelperConfig.s.sol` returning Sepolia feed addresses for
      USDC/USD, ETH/USD, BTC/USD.
- [ ] `script/Deploy.s.sol` deploying in order:
      math libs → oracle → three IR strategies → three dTokens → three
      debtTokens → LendingPool. Then call `initReserve` once per asset.
- [ ] Verify every contract on Sepolia Etherscan.
- [ ] **Seed-deposit** each dToken at deployment — belt-and-braces
      alongside virtual shares against the inflation attack.
- [ ] Record deployed addresses in
      [README.md "Deployment"](../README.md#deployment).
- [ ] Smoke test on Sepolia: supply 10 USDC, borrow some WETH, repay,
      withdraw. Link the tx hashes from the README.

**Gate:** Smoke-test transactions succeed on Sepolia and are linked in
the README.

---

## Phase 10 — Test tiers and audit prep

Most of these grow incrementally from Phase 1 onward. By the time you
reach this section, the bulk should already exist.

- [ ] **Unit tests** per contract — already gated above.
- [ ] **Integration tests** — multi-contract flows. The 4-step
      Alice/Bob test from Phase 6 is the start; add more covering
      liquidation paths.
- [ ] **Fork tests** against live Sepolia for oracle integration and
      end-to-end smoke tests.
- [ ] **Invariant tests** with a handler contract. At minimum, one
      invariant per item in [Invariant.md](Invariant.md).
- [ ] **Fuzz tests** on `supply`/`withdraw`/`borrow`/`repay` with
      `bound(...)` on amount ranges.
- [ ] Run **Slither** locally; resolve every high and medium finding.
- [ ] Run **Aderyn** for a different lens; resolve high findings.
- [ ] Fill in every TODO in [architecture.md](architecture.md).
- [ ] Fill in every cell + rationale in [parameters.md](parameters.md).
- [ ] NatSpec on every `external` and `public` function: `@notice`,
      `@param`, `@return`, `@dev` for non-obvious math.
- [ ] Known-issues section in the README enumerating v1 limitations
      (no flash loans, no bad-debt socialization, `Ownable` admin).
- [ ] Final pass before tagging v1:
  - Pin the compiler version (no caret).
  - Remove every `console.log` and `forge-std/Test.sol` import from
    non-test files.
  - Re-run the full test suite from a clean clone.

**Gate:** Slither passes with no high or medium severity. Invariants
hold over 10 000 runs.

---

## Build-on-the-go items (not blocked by any phase)

Progress these alongside any phase, whenever you have a spare hour:

- [ ] Add custom errors to `Errors.sol` *as you write* the contracts
      that throw them — never batch this work at the end.
- [ ] Write NatSpec **as** each function is written, not retrofitted.
- [ ] Fill in [architecture.md](architecture.md) section-by-section as
      the matching contract gets built.
- [ ] Keep a short devlog (`docs/CHANGELOG.md` or similar) with one
      entry per session: what you decided, and *why*. This is the
      narrative the Binance Accelerator application will draw on.
- [ ] Rough blog-post drafts per phase. Writing about a phase reveals
      gaps in your understanding before an auditor would.

---

## How to use this checklist with Claude

- **Starting a phase:** tell me which one. I'll explain the concept
  and the order of operations before you write code.
- **Reviewing your code:** paste the contract or function and ask
  *"review this"*. The `solidity-security` skill activates and I'll
  point at issues in prose, without rewriting your code (per
  [CLAUDE.md](../CLAUDE.md)).
- **Stuck on a pattern:** ask *"what's the canonical pattern for X?"*
  I'll name it and describe how it applies here.
- **Each gate is a commit point.** Tag a small commit, push, and take
  a break before the next phase. Easier to bisect later if something
  regresses.
