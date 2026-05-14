---
name: solidity-security
description: Use when reviewing user-written Solidity for vulnerabilities, threat-modeling a feature before implementation, or explaining how known attack vectors apply to this protocol. Covers generic Solidity bugs plus over-collateralized lending risks (oracle manipulation, vault inflation, health-factor math, liquidation MEV). Describes fixes in prose; does not rewrite the user's code.
---

# solidity-security

Security review and threat-modeling skill scoped to **Decentralend**, an
Aave V2-style multi-asset money market on Sepolia. Activates on code
review, threat-modeling, and audit-prep tasks. Does **not** generate
contract code on the user's behalf.

---

## 1. When to use this skill

Trigger this skill when the user asks for any of the following:

- Reviewing a Solidity snippet they have written or pasted.
- Threat-modeling a flow before implementation
  (e.g. *"what could go wrong with `liquidate`?"*).
- Explaining how a named attack vector applies to this protocol.
- Preparing the codebase for an external audit.
- Naming the invariant a new test should defend.

Do **not** trigger this skill for:

- Writing a contract from scratch on the user's behalf.
- Generic refactors with no security motivation.
- Solidity tutorials unrelated to the current code.

## 2. How to use this skill (tone rules)

This skill operates inside the constraints set in
[`CLAUDE.md`](../../../CLAUDE.md):

- The user is practicing Solidity. Behave as a **patient tutor**, not a
  code generator.
- Short snippets from the user's own code may be quoted to point at a
  specific line. **Never rewrite that snippet into a "fixed" version.**
- Describe each fix in prose. Where a canonical name exists, use it —
  CEI, pull-over-push, `ReentrancyGuard`, virtual shares, commit-reveal,
  pinned pragma — and let the user implement.
- If the user asks for code, redirect: name the state to touch, the
  order to touch it in, and the invariants to preserve. They write it.
- When pointing at a bug, also point at the test that would have caught
  it. Bug + test together is the researcher-grade answer.

## 3. Generic Solidity vulnerabilities

For each entry below: *what the bug is — why it happens — how to spot it
in review — the named pattern that fixes it.*

### 3.1 Reentrancy

A function makes an external call (typically a raw `.call{value: …}("")`,
or a call into untrusted ERC-20 / ERC-777 logic) before its own state has
settled. The callee re-enters the original function and observes stale
state — often draining a balance the original call has not yet zeroed.

- **Why it happens:** developers mentally model "send → bookkeeping"
  instead of "bookkeeping → send", because the transfer feels like the
  important step.
- **How to spot:** any external call inside a function that also mutates
  storage. Check that *every* storage write gating the call happens
  *before* the call returns.
- **Fix:** Checks–Effects–Interactions (CEI). Validate inputs, mutate
  storage to the post-call state, then make the external call. As a
  second layer, OpenZeppelin's `ReentrancyGuard` provides a
  `nonReentrant` modifier.
- **Variants to remember:** *cross-function reentrancy* (re-enter a
  different function that reads the not-yet-updated state) and
  *read-only reentrancy* (re-enter a `view` function whose return value
  another protocol trusts). `nonReentrant` alone does not stop
  read-only reentrancy.

### 3.2 Integer over- and underflow

Solidity ≥ 0.8.0 inserts arithmetic safety checks and reverts on wrap.
The risk reappears inside `unchecked { … }` blocks, which the user may
add for gas reasons.

- **How to spot:** every `unchecked` block. Confirm the arithmetic
  inside is provably bounded by prior `require`s or by the type's range.
- **Fix:** narrow the `unchecked` to the smallest expression that is
  provably safe and write a comment that names the bound. If the bound
  cannot be named in one sentence, the `unchecked` is wrong.

### 3.3 Access control

Two failure modes: missing modifiers, and authenticating with
`tx.origin` instead of `msg.sender`.

- **`tx.origin` pitfall:** `tx.origin` is the EOA at the start of the
  call stack, not the immediate caller. A user signing a transaction
  with a malicious contract in the middle of the stack will see
  `tx.origin == userEOA` even though the contract is the actor.
- **Spot:** any branch that gates on `tx.origin`, any external function
  whose state mutation depends on identity but carries no modifier, any
  admin function reachable without `onlyOwner` or a role check.
- **Fix:** use `msg.sender`. For role-based access, use OpenZeppelin's
  `AccessControl`. For single-owner admin, `Ownable` is acceptable in
  v1; production would replace with a multisig + timelock — a known v1
  limitation in Decentralend.

### 3.4 Front-running and MEV

The mempool is public. Any transaction whose outcome depends on
parameters visible to a watcher (slippage limits, oracle prices the
caller has not pinned, auction bids) can be front-run, back-run, or
sandwiched.

- **Spot:** any function that performs a price-sensitive swap, mint, or
  redeem without an explicit slippage parameter signed by the caller.
- **Fix:** require a `minOut` / `maxIn` slippage bound from the caller
  and revert if the realized number violates it. For ordering-sensitive
  protocols, commit-reveal moves the secret to a second transaction. In
  Decentralend specifically, **liquidations are MEV-exposed by design**
  — see §4.4.

### 3.5 Unchecked external call return values

A low-level `.call(...)` returns `(bool success, bytes memory data)`.
Ignoring `success` silently swallows failed transfers. Many production
ERC-20s return `false` instead of reverting (USDT is the canonical
example) — ignoring the boolean creates phantom-success bugs.

- **Spot:** any `.call`, `.transfer`, or `.send` whose return is not
  captured and checked. Any ERC-20 `transfer` / `transferFrom` not
  wrapped by `SafeERC20`.
- **Fix:** `require(success, "…")` on raw calls; OpenZeppelin's
  `SafeERC20` for token transfers.

### 3.6 `delegatecall` risks

`delegatecall` runs the callee's code in the caller's storage context. A
`delegatecall` into untrusted or unpinned code can rewrite arbitrary
storage slots, including ownership.

- **Spot:** any `delegatecall` whose target is not a hardcoded constant
  or a governance-immutable address. Any proxy whose implementation slot
  can be written without admin gating.
- **Fix:** never `delegatecall` into a user-controlled target. Use
  battle-tested proxy patterns (EIP-1967 transparent proxy, UUPS) and
  store the implementation address at an EIP-1967-defined slot.

### 3.7 Floating pragma

A floating pragma (`pragma solidity ^0.8.20;`) lets the contract be
deployed under any future minor version, which may change opcode
semantics in ways the developer never tested.

- **Spot:** the caret.
- **Fix:** pin the version once feature-complete (`pragma solidity
  0.8.24;`). Production contracts pin a single compiler version.

### 3.8 Missing events on state change

Off-chain indexers, dashboards, and liquidator bots rely on events. A
state mutation that emits nothing is invisible to them. Audit reports
flag this as low severity but reviewers will still call it.

- **Spot:** every `external` / `public` state-mutating function. Count
  the events. There should be at least one.

---

## 4. Lending-protocol-specific risks (Decentralend addendum)

This section is what distinguishes a generic Solidity reviewer from
someone who can audit a lending market. Every item names the attack and
the mitigation.

### 4.1 Oracle manipulation and staleness

Decentralend uses **Chainlink** feeds, including for USDC — the protocol
does **not** assume `1 USDC = $1`. Three risk classes:

- **Staleness.** If a feed has not updated within its heartbeat, the
  on-chain price may be hours behind reality during a market crash —
  allowing borrowers to be liquidated at the wrong price, or
  liquidations to fail when they should succeed.
- **Non-positive answer.** Chainlink can return zero or negative values
  during incidents; trusting these crashes the math.
- **Single-feed dependence.** If the feed is paused or de-listed, the
  protocol has no fallback. v1 accepts this; document it.

**Mitigation in `PriceOracle`:** validate
`updatedAt > block.timestamp - staleness`, validate `answer > 0`, and
**revert** on failure rather than falling back to a cached price. See
[`docs/architecture.md`](../../../docs/architecture.md) §7 and the
staleness thresholds in
[`docs/parameters.md`](../../../docs/parameters.md). Each asset's
staleness threshold must be ≥ that feed's heartbeat.

### 4.2 ERC-4626 inflation / donation attack

When the dToken vault is empty, the first depositor's share price is
undefined. An attacker can deposit 1 wei, **donate** a large amount of
underlying directly to the vault (bypassing `deposit`), and inflate the
share price so the next honest depositor receives **zero** shares due to
rounding. Their underlying is captured.

**Mitigation on `dToken`:** either use OpenZeppelin's ERC-4626
implementation, which adds *virtual shares* and *virtual assets* offsets
(constants added to both sides of the share-price ratio, making the
attack uneconomic), or seed the vault at deployment with a minimum
deposit owned by the deployer and irrecoverable.

### 4.3 Health-factor rounding direction

```
HF = Σ(collateral_i × liqThreshold_i × price_i)
   / Σ(debt_j × price_j)
```

Rounding in this division can favor either the borrower or the protocol
depending on direction.

- **Liquidation gate** (*"is `HF < 1`?"*): round HF **down**. Rounding
  error must err toward marking the position liquidatable, not
  protecting it.
- **Borrow gate** (*"would HF drop below 1 after this borrow?"*): round
  HF **down** for the same reason.

The shared invariant: rounding error always favors protocol solvency,
never the user. Anywhere this is reversed is a bug.

### 4.4 Liquidation MEV and sandwichability

Liquidations are intrinsically MEV-exposed: every liquidatable position
in the mempool is a public arbitrage. Beyond accepting that, two
protocol-level levers limit attack surface:

- **Close factor** (max fraction of a borrower's debt repayable in one
  liquidation call): if 100%, a whale liquidation flashloan-and-dumps
  the seized collateral in one block, moving the market against other
  positions. If too low, the position stays unhealthy and accrues bad
  debt. Aave V2 uses 50%.
- **Liquidation bonus sizing:** too small → no one liquidates dust
  positions. Too large → over-rewards liquidators and increases the
  capital lost by borrowers. Sized per asset by volatility — see
  [`docs/parameters.md`](../../../docs/parameters.md).

### 4.5 Bad-debt accumulation

If a position's collateral value falls below its debt before a
liquidator profits from acting, the position becomes structurally
unliquidatable: gas + slippage exceed the bonus. The debt sits on the
protocol's books.

Decentralend v1 **does not** socialize this loss across suppliers (out
of scope per [`CLAUDE.md`](../../../CLAUDE.md)). The threat-model
implication: rapid price drops on volatile collateral (WETH, WBTC) can
silently insolvent the protocol. Document as a known limitation in the
README; do not silently absorb.

### 4.6 Borrow-of-collateral / self-collateralization loop

A user supplies asset X, marks X as collateral, borrows X, re-supplies
the borrowed X, marks it as collateral, borrows again. Each loop
inflates their *apparent* collateral while the protocol's net underlying
is fixed — effectively borrowing against their own loan.

The protocol must either disallow using a borrowed asset as collateral
in the same tx, charge utilization rates high enough to make the loop
unprofitable, or both. Since Decentralend v1 supports any-to-any
borrowing across the three listed assets, the same-asset loop must be
explicitly guarded in `borrow`.

### 4.7 Index accrual order

`liquidityIndex` and `borrowIndex` must be advanced **before** any state
read that depends on utilization, and before any state write that would
change utilization. If accrual runs *after* the change, the rate
calculation uses the new totals against the old index, producing an
under- or over-accrual that compounds across blocks.

The pattern in `LendingPool`: every external entry point's first action
should be `_updateIndexes(asset)` for every reserve the call touches.

### 4.8 `debtToken` non-transferability

A debt token must not be transferable. If `transfer`, `transferFrom`, or
`approve` silently succeed, anyone can **dump debt** onto an unwilling
recipient who controls the corresponding collateral seat.

The contract must override these functions to revert. Tests must
explicitly assert that all three revert. Inheriting from ERC-20 and
*forgetting* to override is the canonical mistake — easy to ship, easy
to miss in review.

### 4.9 Cross-asset HF unit consistency

USDC has 6 decimals, WBTC has 8, WETH has 18. Chainlink USD feeds return
8-decimal prices for all three. The HF formula sums across assets, so
every term must be normalized to a common base (typically a fixed-point
USD unit such as 1e18, computed as
`amount × price × 10^(18 − assetDecimals − priceDecimals)` or
equivalent).

A single asset with the wrong normalization silently miscounts a user's
collateral or debt by 10⁶ or 10⁸ — exploitable for free borrows.

### 4.10 Pausability vs freeze semantics

Two distinct admin states. The bug is usually mixing them up.

- **Pause** (emergency stop, global): all flows halt, **including**
  repay and withdraw. Use only for incident response. Holding users in
  a paused state indefinitely is a custody risk.
- **Freeze** (per-asset): blocks **new** supply and **new** borrow on
  that asset. Existing positions can still **repay** and **withdraw**.
  Reversing this (freezing repay or withdraw) bricks user funds and is
  the bug.

Review every entry point: which admin state gates it? The matrix should
have no surprises.

---

## 5. Foundry-flavored detection and testing

Decentralend is Foundry-only. When suggesting test coverage:

- **Unit tests** — `import {Test} from "forge-std/Test.sol";`. Prefer
  `vm.expectRevert(IErrors.SomeError.selector)` over the string form;
  selectors are stable, error strings drift and silently make tests
  pass.
- **Fork tests** — `vm.createSelectFork(vm.rpcUrl("sepolia"))` to test
  against live Chainlink feeds. Required to validate oracle integration
  end-to-end; mocked oracles can hide staleness bugs.
- **Invariant tests** — Foundry's `StdInvariant` with handler
  contracts. The invariants for Decentralend live in
  [`docs/Invariant.md`](../../../docs/Invariant.md); this skill's job
  is to *name* the invariant each new feature must defend, not to write
  the test body.
- **Fuzz tests** — `bound(...)` to constrain inputs to economically
  meaningful ranges. Unbounded fuzzing on token amounts mostly hits
  OZ revert paths instead of business logic.
- **Static analysis** — Slither for control-flow and inheritance
  issues, Aderyn for high-level patterns, Mythril for symbolic
  execution. Recommend running Slither in CI before any audit hand-off.

---

## 6. Audit prep checklist

When the user signals *"ready for audit"* or *"audit-prep mode"*, verify
each of the following exists:

- Pinned `pragma solidity` (no caret).
- NatSpec on every `external` and `public` function: `@notice`,
  `@param`, `@return`, plus `@dev` for non-obvious math.
- Per-asset parameter values committed to
  [`docs/parameters.md`](../../../docs/parameters.md), each with a
  one-line rationale.
- Invariant list committed to
  [`docs/Invariant.md`](../../../docs/Invariant.md), each invariant
  cross-referenced to the test that defends it.
- Known-issues section enumerating v1 limitations (no flash loans, no
  bad-debt socialization, `Ownable`-gated admin) — see
  [`CLAUDE.md`](../../../CLAUDE.md).
- Deployment manifest: deployment script, verified Sepolia addresses,
  oracle feed addresses, deployer key custody.

---

## 7. Common pitfalls (review checklist)

- External call before state update.
- `unchecked` block whose bound is not stated in a comment.
- `tx.origin` instead of `msg.sender` for authentication.
- ERC-20 `transfer` without `SafeERC20`.
- `delegatecall` to a non-constant target.
- Floating `^` pragma in production code.
- State change with no event.
- ERC-4626 vault with no virtual shares and no seed deposit.
- HF rounding that favors the borrower.
- Index accrual after the state change instead of before.
- `debtToken` inheriting ERC-20 with `transfer` / `approve` unoverridden.
- Cross-asset math without per-asset decimal normalization.
- Admin state where freeze blocks repay or withdraw.
- Oracle staleness check that falls back to a cached price instead of
  reverting.
- Same-asset borrow → re-collateralize loop not guarded.
