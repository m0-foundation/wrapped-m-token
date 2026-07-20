#!/usr/bin/env tsx

/**
 * Export the WrappedM holder set per chain to `holders/<network>.csv`.
 *
 * A HOLDER is an address whose current on-chain wM `balanceOf` is > 0 — as
 * opposed to an EARNER (`earners/get-earners.ts`), which is an address with
 * `isEarning == true`. Earners are a subset of holders.
 *
 * Source: zero-indexer has no wM balance/holder reducer (`indexer.holder` is
 * only populated for `stablecoin`-type contracts, not wM), so the candidate set
 * is the DISTINCT participants of wM's `Transfer` dyn event table — the same
 * derivation zero-indexer's own `wm-earner-seed.ts` uses. Two tables cover the
 * fleet: `dyn_wrapped_m_token_transfer` (L2s) and
 * `dyn_stateful_wrapped_m_token_transfer` (Ethereum).
 *
 * Transfer participants include addresses that have since gone to zero, so the
 * candidates are enriched with on-chain `balanceOf` and filtered to > 0.
 * Alchemy-supported networks use `https://<slug>.g.alchemy.com/v2/<ALCHEMY_API_KEY>`
 * (env `ALCHEMY_API_KEY`); networks Alchemy doesn't support use a verified public
 * RPC, so they get balances even without an Alchemy key.
 *
 * When a balance can't be read at all — `ALCHEMY_API_KEY` unset, or the key's
 * Alchemy app doesn't have that network enabled (a per-address 403) — the
 * candidate is kept with an EMPTY balance instead of being filtered out. Such a
 * network's CSV is therefore a candidate list, not a verified holder list: it
 * still contains zero-balance addresses, and non-holders like the wM proxy and
 * swap facility. Check the run log for `balanceOf failed` before trusting a file.
 *
 * CAVEATS
 *   - Completeness tracks zero-indexer's backfill: the dyn transfer tables start
 *     at each chain's seeded wM deployment block, so backfill gaps mean missing
 *     holders. Cross-check the count against a block explorer before relying on it.
 *   - Balances are point-in-time RPC reads taken during the run, not indexer
 *     state, so a long multi-network run is not a consistent snapshot.
 *
 * Env (auto-loaded from `.env` if present; shell-exported values take precedence):
 *   ZERO_INDEXER_GRAPHQL_URL     Hasura endpoint (default http://localhost:8080/v1/graphql)
 *   ZERO_INDEXER_GRAPHQL_SECRET  optional x-hasura-admin-secret (public read needs none)
 *   ALCHEMY_API_KEY              optional — enables balanceOf on Alchemy networks (others use public RPCs)
 *
 * Run: npm run get-holders               export every network
 *      npm run get-holders -- ethereum   export a single network
 */
import { mkdirSync, writeFileSync } from "fs";
import { join } from "path";
import {
  byBalanceDesc,
  CHAIN_IDS,
  fetchBalances,
  graphql,
  PAGE_SIZE,
  Row,
  selectNetworks,
  toCsv,
  WM_ADDRESS,
  ZERO_ADDRESS,
} from "../script/wm-common";

/** The wM Transfer dyn tables, in Hasura's two possible naming conventions. */
const TRANSFER_TABLES = [
  "dyn_wrapped_m_token_transfer",
  "dyn_stateful_wrapped_m_token_transfer",
  "indexer_dyn_wrapped_m_token_transfer",
  "indexer_dyn_stateful_wrapped_m_token_transfer",
];

/**
 * The Transfer participant column pairs. Naming follows the registered ABI, so
 * the L2 and stateful types can disagree — zero-indexer's own seed resolves
 * these from the contract-type registry (`pickParticipantColumns`), which isn't
 * exposed over GraphQL, so we probe the known pairs instead.
 */
const PARTICIPANT_COLUMNS = [
  ["from", "to"],
  ["sender", "recipient"],
];

type TransferTable = { field: string; columns: string[] };

/**
 * Resolve which (table, participant columns) combinations actually exist in the
 * Hasura schema, by probing each with a zero-row selection. Both wM types are
 * kept when both resolve: a table with no rows for a given chain simply
 * contributes nothing to that chain's candidate set.
 */
let resolvedTables: TransferTable[] | undefined;
async function transferTables(): Promise<TransferTable[]> {
  if (resolvedTables) return resolvedTables;

  const resolved: TransferTable[] = [];
  for (const field of TRANSFER_TABLES) {
    for (const columns of PARTICIPANT_COLUMNS) {
      try {
        await graphql(
          `query Probe { ${field}(limit: 0) { ${columns.join(" ")} } }`,
          {},
        );
        resolved.push({ field, columns });
        break; // this table's columns are settled — don't try the other pair
      } catch {
        // try the next column pair, then the next table
      }
    }
  }

  if (resolved.length === 0) {
    throw new Error(
      `could not resolve any wM Transfer table (tried ${TRANSFER_TABLES.join(", ")} ` +
        `with columns ${PARTICIPANT_COLUMNS.map((c) => c.join("/")).join(", ")}) — check the Hasura schema`,
    );
  }

  resolvedTables = resolved;
  return resolved;
}

/**
 * Every address that has ever sent or received wM on this chain — the holder
 * candidates, before the balance filter.
 *
 * Queried per participant column with `distinct_on` so Hasura collapses the
 * duplicates server-side rather than shipping one row per transfer. Addresses
 * are lowercased into a shared Set because the two columns (and the two tables)
 * overlap heavily, and dyn-table casing isn't guaranteed. The zero address is
 * dropped: it is the mint/burn counterparty, not a holder.
 */
async function fetchHolderCandidates(chainId: number): Promise<string[]> {
  const tables = await transferTables();
  const seen = new Set<string>();

  for (const { field, columns } of tables) {
    for (const column of columns) {
      const query = `
        query Participants($chainId: Int!, $limit: Int!, $offset: Int!) {
          ${field}(
            where: {
              chain_id: { _eq: $chainId }
              contract_address: { _ilike: "${WM_ADDRESS}" }
            }
            distinct_on: [${column}]
            order_by: { ${column}: asc }
            limit: $limit
            offset: $offset
          ) {
            ${column}
          }
        }`;

      for (let offset = 0; ; offset += PAGE_SIZE) {
        const data = await graphql<
          Record<string, Array<Record<string, string | null>>>
        >(query, { chainId, limit: PAGE_SIZE, offset });
        const page = data[field] ?? [];
        for (const row of page) {
          const address = row[column];
          if (address) seen.add(address.toLowerCase());
        }
        if (page.length < PAGE_SIZE) break;
      }
    }
  }

  seen.delete(ZERO_ADDRESS);
  return [...seen];
}

/**
 * Keep the addresses that actually hold wM today. An empty balance means the
 * balance is UNKNOWN (no RPC for the network, or the read failed) — those rows
 * are kept rather than dropped, so an unreadable network degrades to "candidate
 * list without balances" instead of silently emitting an empty holder set, which
 * would be indistinguishable from a chain that genuinely has no holders.
 */
function isHolder({ balance }: Row): boolean {
  return balance === "" || BigInt(balance) > 0n;
}

async function main() {
  mkdirSync("holders", { recursive: true });

  const networks = selectNetworks(process.argv[2]);

  for (const network of networks) {
    const chainId = CHAIN_IDS[network];
    if (chainId === undefined) {
      console.warn(`\nSkipping ${network} — not indexed by zero-indexer.`);
      continue;
    }

    try {
      console.log(`\nFetching wM holders for ${network} (chain ${chainId})...`);
      const candidates = await fetchHolderCandidates(chainId);
      console.log(`Found ${candidates.length} transfer participant(s)`);

      const csvPath = join("holders", `${network}.csv`);

      // Always write the CSV, even with zero holders: a header-only file records
      // that the network was checked and genuinely has none, rather than leaving
      // a stale file (or no file) that reads as "not yet exported".
      if (candidates.length === 0) {
        writeFileSync(csvPath, toCsv([]));
        console.log(`Exported 0 holders to ${csvPath} (header only)`);
        continue;
      }

      const balances = await fetchBalances(network, candidates);
      const rows = candidates
        .map((address) => ({ address, balance: balances.get(address) ?? "" }))
        .filter(isHolder)
        .sort(byBalanceDesc);

      writeFileSync(csvPath, toCsv(rows));
      console.log(
        `Exported ${rows.length} holders to ${csvPath} ` +
          `(${candidates.length - rows.length} zero-balance participant(s) dropped)`,
      );
    } catch (error) {
      console.error(
        `Error processing ${network}:`,
        error instanceof Error ? error.message : error,
      );
    }
  }
}

main();
