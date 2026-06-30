# Adding the missing WrappedM networks to zero-indexer

The earner tooling (`earners/get-earners.ts`) sources the wM earner address set per chain from
zero-indexer. WrappedM is deployed on **17 EVM chains** (the M0 platform addresses), all at the same
deterministic proxy:

```
wM proxy: 0x437cc33344a0B27A429f795ff6B469C72698B291
```

This doc lists exactly what zero-indexer is missing to cover all 17, and how to add it.

> **Prerequisite, not covered here:** registering a contract makes zero-indexer ingest its events into
> `dyn_*` tables, but the `wm_earner` rollup the tooling reads is produced by a **wM earning reducer**
> that does not exist yet. Registration is necessary but not sufficient — see
> "Dependency: the earning reducer" at the bottom. Tracking issue: the wM `isEarning` reducer +
> backfill/seed.

## Current coverage gap

| Chain | chainId | Chain in zero-indexer? | wM contract registered? | Action |
|---|---|---|---|---|
| Ethereum | 1 | ✅ | ✅ `stateful_wrapped_m_token` | — |
| Optimism | 10 | ✅ | ✅ `wrapped_m_token` | — |
| BNB (BSC) | 56 | ✅ | ✅ `wrapped_m_token` | — |
| HyperEVM | 999 | ✅ | ✅ `wrapped_m_token` | — |
| Soneium | 1868 | ✅ | ✅ `wrapped_m_token` | — |
| Mantra | 5888 | ✅ | ✅ `wrapped_m_token` | — |
| Base | 8453 | ✅ | ✅ `wrapped_m_token` | — |
| Plasma | 9745 | ✅ | ✅ `wrapped_m_token` | — |
| Arbitrum | 42161 | ✅ | ✅ `wrapped_m_token` | — |
| Linea | 59144 | ✅ | ✅ `wrapped_m_token` | — |
| Rise | 4153 | ✅ | ✅ `stateful_wrapped_m_token` | — |
| Plume | 98866 | ✅ | ✅ `stateful_wrapped_m_token` | — |
| **Moca** | 2288 | ✅ | ❌ | **Register wM contract** |
| **Citrea** | 4114 | ✅ | ❌ | **Register wM contract** |
| **0G** | 16661 | ✅ | ❌ | **Register wM contract** |
| **Fluent** | 25363 | ✅ | ❌ | **Register wM contract** |
| **Monad** | 143 | ❌ | ❌ | **Register chain + wM contract** |

So: **4 chains need only the wM contract** (Moca, Citrea, 0G, Fluent), and **Monad needs the chain
registered first**.

## Step 1 — Register Monad (chain)

Monad is not yet in zero-indexer. Register it before its contract.

| Param | Value |
|---|---|
| chainId | `143` (hex `0x8f`) |
| name | `monad` |
| kind | `evm` |
| RPC | `https://rpc.monad.xyz` |
| HyperSync | check availability; fall back to RPC if unsupported (like HyperEVM/Mantra) |
| Explorer | `https://monvision.io` |

Via the MCP `register-chain` tool (or the admin API `POST /chains`):

```json
{ "name": "register-chain", "arguments": {
  "chainId": 143, "name": "monad", "kind": "evm",
  "rpcUrl": "https://rpc.monad.xyz"
} }
```

Confirm with `list-chains` that `143 / monad` appears before continuing.

## Step 2 — Register the wM contract on the 5 missing chains

For **Moca (2288), Citrea (4114), 0G (16661), Fluent (25363), Monad (143)**, register the wM proxy.

Use **`stateful_wrapped_m_token`** to match the other recent deployments (Ethereum, Rise, Plume) —
these are the same stateful implementation that tracks claim/excess and emits the earning events.
Confirm the deployed wM exposes the stateful ABI (`Claimed` / `ExcessClaimed` /
`StartedEarning` / `StoppedEarning`) before committing the type.

Per chain, via MCP `register-contract` (or admin API `POST /contracts`):

```json
{ "name": "register-contract", "arguments": {
  "chainId": 2288,
  "address": "0x437cc33344a0B27A429f795ff6B469C72698B291",
  "contractType": "stateful_wrapped_m_token",
  "abiName": "stateful-wrapped-m-token_WrappedMToken",
  "label": "wM",
  "startBlock": <WM_DEPLOYMENT_BLOCK_ON_THIS_CHAIN>
} }
```

Repeat for chainIds `4114`, `16661`, `25363`, `143`.

**`startBlock` matters:** set it to the wM **deployment block** on each chain, not current head — the
earner-defining `StartedEarning` / `StoppedEarning` events are historical, and a late start block
silently misses them (this is exactly why mainnet wM showed 0 earning events: its data only began at
the stateful-upgrade block, ~4.5M blocks after deployment). zero-indexer's deployment-block resolver
can fill this in if you omit it, but verify the result reaches deployment.

## Step 3 — Verify

For each newly-registered contract:

1. `get-contract <id>` → confirm `handler.events` includes `StartedEarning`, `StoppedEarning`,
   `Transfer`.
2. Confirm `dyn_*` rows are flowing, e.g.:

```graphql
{
  t: indexer_dyn_stateful_wrapped_m_token_transfer_aggregate(where: {chain_id: {_eq: 2288}}) {
    aggregate { count min { block_number } }
  }
}
```

3. Confirm the transfer `min.block_number` reaches the wM deployment block (proves the backfill
   covered history, not just recent blocks).

## Dependency: the earning reducer (the actual blocker)

Registering these contracts only gets events into `dyn_*` tables. The tooling reads a per-`(chain,
account)` `wm_earner` rollup with an `is_earning` flag, which **does not exist yet**. Two known
wrinkles a reducer must handle (verified during investigation):

- **Storage-seeded earners emit no event.** `WrappedMTokenMigratorV1._migrateEarners` writes earning
  status directly to storage (slot 6) without emitting `StartedEarning`. So on chains where the earner
  set was seeded at launch (observed on L2s), event history alone is incomplete — the reducer must
  **seed `isEarning` from an on-chain `WrappedMToken.isEarning(account)` snapshot at an anchor block**,
  then apply `StartedEarning` / `StoppedEarning` deltas after it.
- **Coverage floor.** Where earners did enable via events (mainnet v1), backfill must reach the wM
  deployment block (Step 2).

Until that reducer + seed lands, `get-earners.ts` will run against these chains but return empty
earner sets — the address list is correct (empty), just not yet populated.
