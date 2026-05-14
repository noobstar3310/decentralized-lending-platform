# Decentralend — Build Learnings

> A growing record of what was learned while building this project.
> Entries are organized by topic (not chronology), so future-me can
> refer back to a concept by name. When a topic grows too large, it
> gets pulled into its own file under `docs/learnings/`.
>
> **Voice convention:** entries are written in neutral exposition,
> not diary form ("the optimizer does X" rather than "I learned the
> optimizer does X"). Keeps the file readable to anyone, not just me.
>
> **What this file is for:** capturing the *why* behind decisions and
> the mental models I built. Not a tutorial; it assumes someone is
> already partway through the work.

---

## Table of contents

- [Foundry: `foundry.toml`](#foundry-foundrytoml)
  - [What `foundry.toml` is](#what-foundrytoml-is)
  - [The optimizer (`optimizer = true`)](#the-optimizer-optimizer--true)
  - [`optimizer_runs`](#optimizer_runs)
  - [`[profile.ci]` — why a CI-specific profile](#profileci--why-a-ci-specific-profile)
- _Topics to cover next: WadRayMath, PercentageMath, custom errors,
  ERC-4626 inflation attack, oracle staleness handling..._

---

## Foundry: `foundry.toml`

### What `foundry.toml` is

The configuration file Foundry reads on every command. Lives at the
repo root. Without it, Forge falls back to a built-in set of defaults
— which is fine for a quick hack but wrong for a project that needs
reproducible builds.

The file uses [TOML syntax](https://toml.io/). The structure is
**profiles**: named blocks of settings that get applied depending on
context.

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc_version = "0.8.24"
optimizer = true
optimizer_runs = 200
```

`[profile.default]` is what Forge uses when no profile is selected.
Other profiles (`[profile.ci]`, `[profile.release]`, etc.) override
specific keys; everything not overridden inherits from `default`.

You switch profiles by setting the `FOUNDRY_PROFILE` environment
variable: `FOUNDRY_PROFILE=ci forge test` runs with the CI profile.

A few other top-level blocks worth knowing about:

- **`[rpc_endpoints]`** — named aliases for network RPC URLs. Lets you
  write `forge script --rpc-url sepolia` instead of pasting the full
  URL on every command. Values can reference env vars with
  `"${SEPOLIA_RPC_URL}"`, so the URL itself stays out of git.
- **`[etherscan]`** — block-explorer API keys per chain. `forge verify`
  and `forge script --verify` look here automatically.
- **`[fmt]`** — `forge fmt` formatter rules (line length, brackets,
  etc.).
- **`[fuzz]`** and **`[invariant]`** — fuzz and invariant testing
  config (number of runs, seed, etc.).

### The optimizer (`optimizer = true`)

Solidity's compiler can rewrite the bytecode it generates to be
smaller or cheaper to execute, without changing behavior. The
optimizer is what does this rewriting. Common transformations:

- Removes dead code that no execution path reaches.
- Folds constants at compile time
  (`uint256 x = 2 + 3;` becomes `uint256 x = 5;`).
- Inlines small functions to avoid call overhead.
- Eliminates redundant `SLOAD` / `SSTORE` patterns within a single
  function.
- Replaces common opcode sequences with cheaper equivalents.

**Critical fact:** the optimizer is **off by default** in Foundry.
If `optimizer = true` is not in `foundry.toml`, every build produces
unoptimized bytecode. The consequences:

- Deploy cost is higher (more bytes to upload).
- Runtime gas per call is higher.
- Local bytecode does not match what would be produced for mainnet
  with a normal Hardhat / Foundry setup that has the optimizer on.
- Gas snapshots (`forge snapshot`) measure unoptimized numbers and
  give a misleading picture of production gas.

For any contract that will be deployed, `optimizer = true` is
mandatory.

### `optimizer_runs`

This is the *tradeoff knob*. The optimizer can spend its "effort"
budget on two competing objectives:

1. **Deployment-size optimizations** — make the bytecode smaller, so
   the contract is cheaper to deploy.
2. **Runtime optimizations** — inline more aggressively, unroll loops,
   reorder for cache friendliness, etc. These make calls cheaper but
   typically make the bytecode larger.

`optimizer_runs` tells the compiler how many times the contract is
expected to be called over its lifetime. The compiler uses this as a
heuristic to bias its decisions.

| Value | Bias | Typical use |
|---|---|---|
| `1` | Extreme size optimization | One-shot scripts, factory templates |
| `200` | Balanced (Foundry / Aave default) | General-purpose contracts |
| `1_000_000` | Extreme runtime optimization | Hot-path contracts called constantly |

A lending pool is called every time anyone supplies, withdraws,
borrows, repays, or liquidates — runtime cost dominates lifetime cost.
But going to `1_000_000` adds bytecode size with diminishing returns;
`200` matches Aave's choice and is the safer default.

What `200` literally means: "assume each function will be called
~200 times after deployment." It is a heuristic input, not a hard
limit. The compiler uses it to weight inlining and layout decisions.

There is no single "best" value. Higher = bigger bytecode + cheaper
calls; lower = smaller bytecode + more expensive calls. The right
choice depends on the deploy-vs-call ratio for the specific contract.

### `[profile.ci]` — why a CI-specific profile

A CI run is a different context from local development. Different
priorities, different time budgets, different audiences for the
output. A separate profile lets the same project tune for both.

For Decentralend, the CI profile differs from default in two
intentional ways:

```toml
[profile.ci]
fuzz = { runs = 1_000 }
verbosity = 3
```

**`fuzz = { runs = 1_000 }`** — bumps fuzz tests from the default
256 runs to 1000. Rationale: local dev needs *fast* feedback (a
test loop that takes 60s breaks flow), but CI runs on every push
and can afford to be thorough. 1000 runs catches edge cases that 256
runs miss, with no cost to the developer's iteration speed.

**`verbosity = 3`** — more detailed test output. The GitHub Actions
log is the only way to diagnose a CI failure without re-running
locally. Verbosity 3 includes stack traces and intermediate revert
data, which makes "why did this fail in CI but pass locally?" debugging
tractable.

**What the CI profile deliberately does NOT change:** `optimizer_runs`.

This is the subtle one. If dev and CI use different optimizer
settings, then `forge snapshot` produces different gas numbers in
each context, and CI's gas reports become unreliable signals. Gas
measurements must be reproducible across environments, which means
the optimizer settings must match. A common mistake is to think "CI
should run release-quality optimization" and bump `optimizer_runs`
in CI — that breaks gas regression detection.

Keep optimizer settings identical across profiles. Tune only what is
genuinely context-dependent: test rigour (fuzz runs, invariant depth),
logging verbosity, RPC endpoints, that kind of thing.

---

_End of current entries. Topics to add as we go: math libraries (wad
vs ray, half-up rounding, overflow domains); custom errors and their
gas vs require strings; ERC-4626 inflation attack and the virtual
shares defense; Chainlink staleness handling; health-factor rounding
direction; index accrual order; debt-token non-transferability._
