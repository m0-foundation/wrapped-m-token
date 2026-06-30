# zero-indexer: `wm_earner` is incomplete — backfill wM `Transfer` history, then re-run the seed

## TL;DR

`indexer.wm_earner` is live but **drastically under-populated** on at least Ethereum (chain 1): it
holds **7** earners when the real set is much larger. A known on-chain earner is entirely absent.

Root cause is **not** the reducer or the `get-earners.ts` consumer — it's that the chain has only
~29h of wM `Transfer` history indexed (live at head, never backfilled to deployment). Both mechanisms
that populate `wm_earner` depend on that history, so historical earners are invisible.

**Ask:** backfill wM `Transfer` (and `StartedEarning`/`StoppedEarning`) from the wM **deployment
block** per chain, then re-run `seed-wm-earners.ts --chain=<id>`, then verify completeness against
on-chain truth. **This blocks the wM V2 migration** — the migrator earner array is generated from
`wm_earner`, and a short list means under-migrating earners.

## Evidence (Ethereum, chain 1, observed 2026-06-26)

Known earner, confirmed earning on-chain:

```
account     0xff95c5f35f4ffb9d5f596f898ac1ae38d62749c2
isEarning() true        (read at mainnet head via WrappedMToken proxy)
balanceOf   14752080061631   (~14.75 wM)
wM proxy    0x437cc33344a0b27a429f795ff6b469c72698b291
```

In zero-indexer it is **completely invisible**:

| Probe | Result |
|---|---|
| `indexer_wm_earner` row for the account (chain 1) | **none** |
| `indexer_wm_earner` `is_earning=true` count (chain 1) | **7** (expected: far more) |
| `..._stateful_wrapped_m_token_started_earning` for the account | **none** |
| `..._stateful_wrapped_m_token_stopped_earning` for the account | **none** |
| account as `sender`/`recipient` in `..._stateful_wrapped_m_token_transfer` | **none** |

Indexed Transfer window for chain 1:

```
floor    25,396,068
ceiling  25,404,720      (chain head 25,404,908 → only 188 blocks behind: live, but…)
span     8,652 blocks  ≈ 28.8h of history only
```

The wM proxy has existed on mainnet since ~block **20,527,882**, so ~4.9M blocks of Transfer history
are not indexed.

## Why this empties `wm_earner`

`wm_earner` is populated two ways (`registry/reducer-specs/wrapped-m-earner.ts` +
`registry/wm-earner-seed.ts`), and **both are bounded by the indexed Transfer range**:

1. **Live reducer** — applies `StartedEarning`/`StoppedEarning` only for events *inside* the indexed
   window. Earners who enabled earning before the window (the vast majority) have no in-range event.
2. **Anchor seed** — its candidate set is `DISTINCT participants of the indexed Transfer dyn table`.
   With ~29h of Transfers indexed, almost no historical holder is a candidate, so `isEarning()` is
   never read for them.

Net: only accounts that moved wM or toggled earning in the last ~29h land in `wm_earner`. Everyone
else — including `0xff95…` — is silently dropped.

## Requested fix

Per wM chain (Ethereum first; the same check should be applied to every chain in
`earners/get-earners.ts`'s `CHAIN_IDS`):

1. **Backfill to the wM deployment block**, not current head. The backfill must cover
   `Transfer` (defines the seed candidate set — every earner received wM via a Transfer at some point)
   and `StartedEarning`/`StoppedEarning`. For Ethereum the floor is the wM proxy deployment
   (~`20,527,882`); confirm the exact block per chain via the deployment-block resolver.
2. **Re-run the seed once backfill reaches deployment:** `bun apps/indexer/scripts/seed-wm-earners.ts --chain=<id>`.
   Running it *before* backfill is a no-op for completeness — the candidate set is unchanged. (Archive
   RPC required; the seed reads `isEarning()` at an old anchor.)
3. Repeat per chain.

## Acceptance criteria

For each chain:

- [ ] `..._wrapped_m_token_transfer` **min `block_number` reaches the wM deployment block** (proves
      history was backfilled, not just recent blocks).
- [ ] The known earner is present and correct:
      `indexer_wm_earner(where: {chain_id: {_eq: 1}, account: {_ilike: "0xff95c5f35f4ffb9d5f596f898ac1ae38d62749c2"}}) { is_earning }`
      → `is_earning = true`.
- [ ] `wm_earner` `is_earning=true` count for the chain is within tolerance of the on-chain earner set
      (spot-check a sample of accounts against `WrappedMToken.isEarning(account)`).

## Repro (read-only)

```graphql
# 1) the earner is missing from wm_earner
query { indexer_wm_earner(where: {chain_id: {_eq: 1},
  account: {_ilike: "0xff95c5f35f4ffb9d5f596f898ac1ae38d62749c2"}}) { is_earning last_block } }

# 2) it never appears as a Transfer participant in-range
query { indexer_dyn_stateful_wrapped_m_token_transfer(where: {chain_id: {_eq: 1},
  _or: [{sender: {_ilike: "0xff95...c2"}}, {recipient: {_ilike: "0xff95...c2"}}]}, limit: 1) { block_number } }

# 3) the indexed Transfer window is only ~29h
query {
  lo: indexer_dyn_stateful_wrapped_m_token_transfer(where: {chain_id: {_eq: 1}}, order_by: {block_number: asc},  limit: 1) { block_number }
  hi: indexer_dyn_stateful_wrapped_m_token_transfer(where: {chain_id: {_eq: 1}}, order_by: {block_number: desc}, limit: 1) { block_number }
}
```

On-chain cross-check: `WrappedMToken(0x437cc33344a0b27a429f795ff6b469c72698b291).isEarning(0xff95c5f35f4ffb9d5f596f898ac1ae38d62749c2)` → `true`.

## Note for the consumer side (wrapped-m-token)

`earners/get-earners.ts` reports `wm_earner` faithfully and needs no change. Until backfill + reseed
land, the generated `earners/*.csv` are **incomplete and must not be used to build the V2 migrator
earner array**. A completeness gate (assert known earners present per chain; fail if the indexed
Transfer floor is far above deployment) can be added on our side as a guard.
