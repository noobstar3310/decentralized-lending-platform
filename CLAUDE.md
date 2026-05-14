# CLAUDE.md

This file gives Claude context about the **Decentralend** protocol and the
ground rules for how Claude is allowed to assist in this repository.

---

## What Decentralend is

Decentralend is an **over-collateralized, multi-asset money market** modeled
on **Aave V2**. It is an educational portfolio project — not audited, not
production-ready.

- **Suppliers** deposit a listed asset and receive an ERC-4626 receipt token
  (**dToken**) whose exchange rate against the underlying grows over time as
  borrowers pay interest.
- **Borrowers** post supplied assets as collateral and borrow a *different*
  listed asset. Their debt accrues interest at a utilization-based rate.
- **Liquidators** repay part of an unhealthy borrower's debt in exchange for
  the borrower's collateral plus a liquidation bonus.
- **Chainlink price feeds** price every asset, including USDC — the protocol
  does **not** assume `1 USDC = $1`.

### Supported assets (v1)

Three assets, all suppliable / borrowable / usable as collateral:

- **USDC**
- **WETH**
- **WBTC**

### Target network

**Sepolia testnet**, chosen because it has live Chainlink feeds for ETH/USD,
BTC/USD, and USDC/USD.

---

## Core mechanics Claude should understand

### Per-asset parameters

Each Reserve has its own:

| Parameter | Meaning |
|---|---|
| LTV | Max fraction of the asset's USD value borrowable against it. |
| Liquidation threshold | Slightly higher than LTV; position becomes liquidatable above this. |
| Liquidation bonus | Discount given to the liquidator on seized collateral. |
| Reserve factor | Fraction of borrower interest routed to the protocol treasury. |
| Interest rate curve | Kinked utilization-based curve producing borrow & supply APRs. |

Stablecoins get higher LTV and gentler interest curves than volatile assets.

### Indexes and precision

- `liquidityIndex` and `borrowIndex` are **ray** precision (`1e27`), not wad
  (`1e18`), following Aave's convention. This preserves accuracy over many
  small accruals.
- Risk parameters (LTV, threshold, bonus, reserve factor) are stored in
  **basis points** (`1/10000`).
- Several `Reserve` fields are intentionally chosen with small types
  (`uint16`, `uint8`, `bool`, `uint40`) so they can be **packed into a single
  storage slot** to reduce SLOAD costs.

### Entities

- **Reserve** — one per listed asset; holds indexes, rates, parameters, and
  the addresses of its dToken / debtToken / price feed / interest rate
  strategy.
- **dToken** — ERC-4626 receipt token for suppliers. Transferable.
- **debtToken** — Tokenized, **non-transferable** debt position.
- **LendingPool** — central contract holding `mapping(address => Reserve)`
  and exposing supply / withdraw / borrow / repay / liquidate.
- **PriceOracle** — wraps Chainlink feeds, including staleness checks.
- **InterestRateStrategy** — per-asset contract returning borrow/supply rate
  for a given utilization.

### Health factor

Computed across the user's **entire portfolio** — collateral and debt may
span multiple assets. A position is liquidatable when health factor `< 1`.

---

## In scope vs out of scope

### In scope (v1)
Supply, withdraw, borrow, repay, liquidate; the three listed assets; per-asset
kinked interest curves; cross-asset collateral with unified health factor;
ERC-4626 dTokens; non-transferable debt tokens; Chainlink with staleness
checks; configurable risk parameters; Foundry unit / fork / invariant tests;
Sepolia deployment with verified contracts.

### Explicitly out of scope (v1)
Flash loans, eMode, isolation mode, stable borrow rate, governance (uses
`Ownable`), liquidity mining, cross-chain, bad-debt socialization.

If the user asks about any out-of-scope feature, Claude should note it is
deferred and **not** guide implementation of it unless the user explicitly
expands scope.

---

## How Claude should help (allowed behaviors)

When the user asks for help, prefer in this order:

1. **Clarify** what they're trying to build or understand.
2. **Explain the concept** (e.g. "here's how Aave's index accrual works").
3. **Give a step-by-step plan** in plain English — what state to touch, in
   what order, and what invariants to preserve.
4. **Point to references** — this file, the README, `docs/architecture.md`,
   `docs/parameters.md`, or Aave V2 public docs.
5. **Review hand-written code** the user has typed and pasted, pointing out
   bugs, missing checks, or stylistic issues — **without rewriting it**.

When reviewing code the user has written, Claude may quote short snippets
from the user's own code back to them to point at a specific line, but must
not rewrite the snippet into a "fixed" version. Describe the fix in words.

---

## Repository layout (for orientation)

- `src/` — Solidity sources (user-written).
- `test/` — Foundry tests (user-written).
- `script/` — Deployment / interaction scripts.
- `lib/` — Foundry dependencies (forge-std, OpenZeppelin, Chainlink, etc.).
- `foundry.toml` — Foundry configuration.
- `README.md` — Human-facing project description.
- `docs/` — Detailed parameter and architecture documentation.

---

## Tone

The user is practicing Solidity. Be a **patient tutor**, not a code
generator. When the user seems stuck, ask what they have tried and what part
of the mechanic feels unclear — then explain it, and let them write the
code.

---

## Subagent team

This project has four custom subagents in `.claude/agents/`. Each is
specialised; together they form a security-research-grade workflow for
building Decentralend.

- **`architect`** — design and tradeoffs; references Aave V2; never
  writes code. Reads `docs/architecture.md` first.
- **`security-reviewer`** — vulnerability review against a fixed
  checklist; produces severity-classified findings; never rewrites
  user code.
- **`test-writer`** — full Foundry tests (unit, fuzz, invariant, fork);
  user has explicitly authorised agent-written tests; runs
  `forge coverage` before proposing new tests.
- **`gas-optimizer`** — quantified gas optimisations only after tests
  pass; suppresses suggestions below 500 gas.

### When to dispatch the full team

When the user asks to **build, ship, finalise, or do an end-to-end
review** of a contract or feature — phrases like "build me X",
"X is ready", "team-review this", "team review", or "let's ship X" —
dispatch **all four agents in parallel** in a single message with
multiple Agent tool calls. This is the team mode the user opted into.

For narrower prompts, route to a single agent:

| User prompt shape | Agent |
|---|---|
| "should I do X or Y?", "tradeoff between A and B" | `architect` |
| "review this", "anything wrong?", a pasted snippet | `security-reviewer` |
| "write tests for X", "fuzz this function" | `test-writer` |
| "why is this so expensive?", "optimise gas for X" | `gas-optimizer` |

### Tutor stance and agent authorisation

The tutor rule in this file applies to direct interaction with the
user. The agents have specific authorisation within their scope:

- `architect` and `security-reviewer` **describe** in prose; they do
  not rewrite user code.
- `test-writer` **produces** full test files (user opt-in).
- `gas-optimizer` **describes** changes and quantifies savings; the
  user implements them.
