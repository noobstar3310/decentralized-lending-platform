# Decentralend — Invariants & Edge Cases

> Temporary planning doc. Not Solidity — a checklist to drive `test/invariant/`
> and unit tests. Delete or fold into `docs/` once tests are written.

---

## A. Accounting & solvency invariants

The "no money is created or destroyed" properties — strongest candidates for
Foundry `invariant_*` functions.

1. **Per-asset liquidity equation.** For every reserve:
   `underlying.balanceOf(LendingPool) + totalBorrows(asset) ≈ totalSupplied(asset) + accruedTreasury(asset)`.
   `≈` allows a few wei of rounding dust.
2. **Pool is never insolvent.** `totalSupplied(asset) ≥ totalBorrows(asset)`. Utilization may equal 100% but never exceed it.
3. **No phantom dTokens.** `sum(user dToken balances) == dToken.totalSupply()`.
4. **No phantom debt.** `sum(user debt balances) == debtToken.totalSupply()`.
5. **Underlying claim conservation.** `dToken.totalSupply() * liquidityIndex / RAY + treasuryShare ≈ totalSupplied(asset)`.
6. **Debt claim conservation.** `debtToken.totalSupply() * borrowIndex / RAY ≈ totalBorrows(asset)`.
7. **No free mint of dTokens.** dToken supply only grows via a `supply` backed by an underlying transfer in, and only shrinks via `withdraw` with underlying out.
8. **No free burn of debt.** debt token supply only shrinks via `repay` (underlying in) or `liquidate` (debt repaid by liquidator).

## B. Index invariants

9. **Initial values.** `liquidityIndex` and `borrowIndex` start at `1 RAY (1e27)`.
10. **Monotonic non-decreasing.** Neither index ever decreases.
11. **Borrow grows at least as fast as supply.** Per reserve, `borrowIndex / liquidityIndex` is non-decreasing (reserve factor + utilization ≤ 1).
12. **Time-bounded updates.** `lastUpdateTimestamp ≤ block.timestamp`. After any state-changing call, `lastUpdateTimestamp == block.timestamp`.
13. **Idempotency within a block.** Two consecutive accruals in the same block yield the same indexes as one.

## C. Rate invariants

14. **Supply rate is bounded by borrow rate net of reserve factor.**
    `liquidityRate ≈ borrowRate × utilization × (1 − reserveFactor)`.
15. **Both rates are non-negative.**
16. **Rate at zero utilization.** When `totalBorrows == 0`, borrow rate equals the curve's base rate; supply rate is zero.
17. **Continuity at the kink.** Just below and just above `U_optimal` the curve produces the same rate.
18. **Monotone in utilization.** Strictly increasing on each segment of the kinked curve.

## D. Per-user position invariants

19. **No-op safety.** `supply` immediately followed by `withdraw` of the same shares returns the same underlying ±1 wei.
20. **HF after action.** After any `borrow`, `withdraw`, or `disableCollateral`, the user's health factor is `≥ 1` or the call reverts.
21. **HF = ∞ when debt = 0.** Users with no debt are never liquidatable.
22. **HF stable in a block.** Reading HF twice without state change returns the same value.
23. **dToken transferability respects collateral.** Transferring collateral-enabled dTokens must leave the sender's HF `≥ 1`, or revert.
24. **DebtToken is non-transferable.** `transfer`, `transferFrom`, and `approve` revert.

## E. Liquidation invariants

25. **Precondition.** Reverts unless borrower's pre-call HF is strictly `< 1`.
26. **Close-factor cap.** A single liquidation repays at most `CLOSE_FACTOR` (e.g. 50%) of the borrower's outstanding debt **in the chosen debt asset**.
27. **Seizure formula.** Collateral seized (underlying units) = `debtRepaid × debtPrice × (1 + liquidationBonus) / collateralPrice`, decimal-normalized.
28. **Seizure ≤ available collateral.** If the formula exceeds the borrower's collateral balance, seizure clamps to balance and repaid debt clamps proportionally.
29. **Net protocol loss = bonus only.** The protocol doesn't lose value beyond the bonus paid to the liquidator.
30. **HF improves or position closes.** Post-liquidation, the borrower has no debt left or HF after is `≥` HF before.
31. **No self-liquidation profit.** Even if allowed, self-liquidation must not be profitable for a healthy user.

## F. Risk-parameter invariants

32. `0 ≤ LTV ≤ liquidationThreshold ≤ 10000` bps.
33. `liquidationThreshold + liquidationBonus ≤ 10000` (avoid immediate bad debt at the boundary).
34. `0 ≤ reserveFactor ≤ 10000`.
35. **Frozen reserve.** `supply` and `borrow` revert; `withdraw`, `repay`, `liquidate` still work.
36. **Inactive reserve.** All five flows revert.
37. **Parameter changes accrue first.** Any admin mutation of `reserveFactor`, rate strategy, LTV, or threshold accrues interest immediately before the change.

## G. Oracle invariants

38. **All prices positive.** Operation reverts if any consumed oracle returns `≤ 0`.
39. **Staleness check.** If `updatedAt` is older than the heartbeat, every operation that consumes that price reverts.
40. **USDC is not pinned.** Always read the feed, never assume `1 USDC = $1`.
41. **Single price per tx per asset.** A given asset's price is read once per user-facing transaction.

## H. Math / precision invariants

42. **No division before multiplication** in audited index / rate / HF paths.
43. **Rounding direction favors the protocol.** Mint shares → round down; burn shares → round up; charge debt → round up; pay withdrawals → round down.
44. **Decimal normalization.** USD valuation uses the asset's actual `decimals` (WBTC = 8, USDC = 6, WETH = 18). Equally-valued positions in different assets compare equal to within the smallest representable unit.

---

## Edge cases

### 1. Empty / first-time states
- First depositor in a brand-new reserve (`liquidityIndex == 1 RAY`, `dToken.totalSupply == 0`). Defend against ERC-4626 first-depositor inflation attack (virtual shares / dead shares / seed deposit).
- Last withdrawer drains reserve to zero. Next `supply` must not divide by zero.
- First borrower: utilization jumps from 0 to non-zero in one tx — rates must flip correctly.

### 2. Zero and dust amounts
- `supply(0)`, `withdraw(0)`, `borrow(0)`, `repay(0)`, `liquidate(0)` revert (no silent no-op).
- Withdraw that, after rounding, burns 0 shares for non-zero underlying — revert.
- Repaying 1 wei of debt updates indexes correctly without underflow.

### 3. Over-actions
- Repaying more than owed: cap and refund, or revert. Decide and test the chosen behavior in both directions.
- Withdraw more than owned: revert.
- Withdraw more underlying than pool holds (borrowers have it out): revert with clear "not enough liquidity".
- Borrow entire available liquidity to U = 100%: succeeds; next borrow attempt fails.

### 4. HF boundary
- Borrow that lands exactly on `HF = 1.0`. Choose `≥ 1` or `> 1` semantics and test the chosen side.
- Withdraw collateral exactly to boundary.
- Toggle `useAsCollateral = false` on an asset that would push HF below 1 — revert.
- HF computed when user has any asset with stale oracle — revert before HF is used.

### 5. Decimals
- **WBTC = 8 decimals.** Every USD-valuation path must normalize. Common bug: forgetting normalization → 10¹⁰× wrong position.
- **USDC = 6 decimals.** Same risk.
- **Chainlink feeds typically 8 decimals**, not 18. Mixing feed decimals with token decimals is the most common Aave-clone bug.

### 6. Liquidation corner cases
- Borrower has collateral in multiple assets and debt in multiple assets — liquidator specifies which. Test all combinations.
- Seize an asset the borrower hasn't enabled as collateral — revert.
- Single liquidation that clears entire debt (sub-dust remainder) — close factor permits full repay below dust.
- Bad debt: collateral exhausted, debt remains. Liquidation does **not** revert; residual is recorded (documented v1 limitation).
- Two liquidators racing on the same position in the same block — second sees healthy position and reverts.
- Self-liquidation: explicitly allow or block, then test the chosen path.

### 7. Oracle scenarios
- Returns `0`.
- Returns a negative `int256`.
- Stale (`updatedAt` past heartbeat).
- Incomplete round (`answeredInRound < roundId`).
- Aggregator paused / returns max-uint sentinel.
- All five → specific revert.

### 8. Interest accrual
- Very long idle period (months) followed by a tiny interaction — no ray overflow, index growth bounded sensibly.
- Two state-changing calls in same block — second accrues zero additional interest.
- Reserve factor changed between accruals — first interval uses old factor, second uses new (change forces accrual).

### 9. Cross-asset & looping
- Supply WETH, enable as collateral, borrow WETH. Decide whether same-asset borrow is allowed; document.
- Supply A → borrow B → supply B → enable B as collateral → borrow more A (leverage loop). Must still respect HF.
- Same asset as both collateral and debt — HF math must not double-count or mis-net.

### 10. Token quirks
- **USDC** non-standard EIP-2612 permit — if `supplyWithPermit` is exposed, test it.
- **USDC** issuer-level blacklisting — blacklisted user's `withdraw` reverts on the underlying transfer; protocol must propagate without corrupting state.
- **WETH** has no transfer hooks; protocol should not accept raw ETH unless intentional (`receive()` guarded).
- **WBTC** standard ERC-20, but low decimals exaggerate any rounding bug.
- Fee-on-transfer / rebasing tokens are out of scope — document in source comments.

### 11. Admin / lifecycle
- Listing a reserve with `address(0)` dToken or debtToken — revert.
- Freezing a reserve with open positions — repay/withdraw still work.
- Delisting / deactivating while non-zero debt or supply exists — revert (or documented wind-down state).
- `Ownable` owner transfer / renounce — confirm behavior matches intent.

### 12. Reentrancy & ordering
- `nonReentrant` on every external state-mutating function.
- CEI in every flow: update indexes → update user state → external token transfer last.
- Malicious ERC-20 re-entering via `transferFrom` — invariants still hold across the reentry.

### 13. Bad-debt & failure modes
- Residual bad debt is recorded, not socialized.
- Reserve oracle permanently dead — all flows on that reserve revert; other reserves unaffected unless the user's HF read touches that asset.
- Asset price collapses 50% in one update — liquidation pipeline still processes the wave.

---

## Test split in Foundry

- **Invariants A–H** → `test/invariant/` with `targetContract` pointing at `LendingPool` and handlers for suppliers / borrowers / liquidators.
- **Edge cases 1–7** → unit tests with deterministic setups.
- **Edge cases 8–13** → mix of unit and fork tests (oracle scenarios especially benefit from fork).

Suggested scaffolding approach: write one `function test_…` name per edge case above, all reverting `vm.skip(true)` until the underlying contract behavior is implemented. Gives a burn-down checklist.
