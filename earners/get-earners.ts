#!/usr/bin/env tsx

/**
 * Export the WrappedM earner set per chain to `earners/<network>.csv`.
 *
 * Source: zero-indexer's `wm_earner` table (per-(chain, account) `isEarning`),
 * served over its Hasura GraphQL endpoint. This replaces the degraded
 * protocol-api `WMHolders` / `WMHoldersL2` resolvers.
 *
 * `wm_earner` stores `account` + `is_earning` only — NOT balance (zero-indexer
 * has no wM balance reducer). So the earner ADDRESS set comes from the indexer,
 * and the `balance` column is enriched on-chain via `balanceOf`. Alchemy-supported
 * networks use `https://<slug>.g.alchemy.com/v2/<ALCHEMY_API_KEY>` (env
 * `ALCHEMY_API_KEY`); networks Alchemy doesn't support use a verified public RPC,
 * so they get balances even without an Alchemy key. Only an Alchemy network with
 * `ALCHEMY_API_KEY` unset has no RPC and is written with an empty balance. The
 * address list — the thing the migration needs — is always produced.
 *
 * Sepolia is the exception: zero-indexer doesn't index it, so its earner set is
 * derived directly from the wM contract's StartedEarning / StoppedEarning logs
 * over RPC (see ONCHAIN_EARNER_NETWORKS), then enriched with `balanceOf` like the
 * rest. This needs an RPC for Sepolia — `ALCHEMY_API_KEY` (eth-sepolia) or a
 * public one — and errors out rather than emitting an empty set without it.
 *
 * Chain tables, RPC routing, the GraphQL client and CSV formatting are shared
 * with `holders/get-holders.ts` via `script/wm-common.ts`.
 *
 * Env (auto-loaded from `.env` if present; shell-exported values take precedence):
 *   ZERO_INDEXER_GRAPHQL_URL     Hasura endpoint (default http://localhost:8080/v1/graphql)
 *   ZERO_INDEXER_GRAPHQL_SECRET  optional x-hasura-admin-secret (public read needs none)
 *   ALCHEMY_API_KEY              optional — enables balanceOf on Alchemy networks (others use public RPCs)
 *
 * Run: npm run get-earners               export every network
 *      npm run get-earners -- ethereum   export a single network
 */
import { mkdirSync, writeFileSync } from "fs";
import { join } from "path";
import { id, JsonRpcProvider, Log } from "ethers";
import {
  byBalanceDesc,
  CHAIN_IDS,
  fetchBalances,
  graphql,
  PAGE_SIZE,
  rpcUrlFor,
  selectNetworks,
  toCsv,
  WM_ADDRESS,
} from "../script/wm-common";

// Chains zero-indexer doesn't cover, so their earner set can't come from
// `wm_earner`. Sepolia (the v2 upgrade testnet) is one: zero-indexer explicitly
// skips it, so its earners are derived on-chain from the wM contract's own
// StartedEarning / StoppedEarning events instead (see fetchEarnerAddressesOnChain).
const ONCHAIN_EARNER_NETWORKS = new Set(["sepolia"]);

// Topic0 of the wM earning events. `account` is the single indexed arg, so it
// lands in topics[1]; there is no non-indexed data to decode.
const STARTED_EARNING_TOPIC = id("StartedEarning(address)");
const STOPPED_EARNING_TOPIC = id("StoppedEarning(address)");

/**
 * A table tracked in the `indexer` schema may surface as `wm_earner` or
 * `indexer_wm_earner` depending on Hasura naming config — resolve it once by
 * probing both, so the script works regardless.
 */
let resolvedField: string | undefined;
async function earnerField(): Promise<string> {
  if (resolvedField) return resolvedField;
  for (const field of ["wm_earner", "indexer_wm_earner"]) {
    try {
      await graphql(`query Probe { ${field}(limit: 0) { account } }`, {});
      resolvedField = field;
      return field;
    } catch {
      // try the next candidate
    }
  }
  throw new Error(
    "could not resolve the wm_earner GraphQL field (tried wm_earner, indexer_wm_earner) — check the Hasura schema",
  );
}

async function fetchEarnerAddresses(chainId: number): Promise<string[]> {
  const field = await earnerField();
  const query = `
    query Earners($chainId: Int!, $limit: Int!, $offset: Int!) {
      ${field}(
        where: { chain_id: { _eq: $chainId }, is_earning: { _eq: true } }
        order_by: { account: asc }
        limit: $limit
        offset: $offset
      ) {
        account
      }
    }`;

  // `wm_earner` is a reducer/anchor-seed table, so a single account can surface in
  // more than one row — de-duplicate by account here. A repeated address would
  // otherwise break the downstream strictly-ascending invariant in
  // generate-earners-array and ListOfEarnersToMigrate.
  const seen = new Set<string>();
  for (let offset = 0; ; offset += PAGE_SIZE) {
    const data = await graphql<Record<string, Array<{ account: string }>>>(
      query,
      {
        chainId,
        limit: PAGE_SIZE,
        offset,
      },
    );
    const page = data[field] ?? [];
    for (const { account } of page) seen.add(account.toLowerCase());
    if (page.length < PAGE_SIZE) break;
  }
  return [...seen];
}

/** Lowercased account address from an earning event's indexed topics[1]. */
function accountOf(log: Log): string {
  return `0x${log.topics[1].slice(-40)}`.toLowerCase();
}

/**
 * Derive the earner set for a chain zero-indexer doesn't cover, straight from
 * the wM contract's StartedEarning / StoppedEarning logs — the same events
 * zero-indexer's reducer consumes, replayed here in order.
 *
 * Unlike balances (which degrade to empty when a network has no RPC), the earner
 * ADDRESS set is the whole point of this export, so a missing RPC is a hard error
 * rather than a silent empty result.
 */
async function fetchEarnerAddressesOnChain(network: string): Promise<string[]> {
  const rpcUrl = rpcUrlFor(network);
  if (!rpcUrl) {
    throw new Error(
      `no RPC for ${network} — cannot derive its earner set on-chain (set ALCHEMY_API_KEY or add a public RPC)`,
    );
  }

  const provider = new JsonRpcProvider(rpcUrl);
  try {
    const logs = await provider.getLogs({
      address: WM_ADDRESS,
      topics: [[STARTED_EARNING_TOPIC, STOPPED_EARNING_TOPIC]],
      fromBlock: 0,
      toBlock: "latest",
    });

    // Replay in event order: a later Started/Stopped for an account supersedes an
    // earlier one, so sort by (blockNumber, logIndex) before folding. The final
    // set is the accounts left in the earning state.
    logs.sort((a, b) =>
      a.blockNumber !== b.blockNumber
        ? a.blockNumber - b.blockNumber
        : a.index - b.index,
    );
    const earning = new Map<string, boolean>();
    for (const log of logs) {
      earning.set(accountOf(log), log.topics[0] === STARTED_EARNING_TOPIC);
    }
    return [...earning].filter(([, isEarning]) => isEarning).map(([a]) => a);
  } finally {
    provider.destroy();
  }
}

async function main() {
  mkdirSync("earners", { recursive: true });

  const networks = selectNetworks(process.argv[2]);

  for (const network of networks) {
    const chainId = CHAIN_IDS[network];
    if (chainId === undefined) {
      console.warn(`\nSkipping ${network} — not indexed by zero-indexer.`);
      continue;
    }

    try {
      console.log(`\nFetching wM earners for ${network} (chain ${chainId})...`);
      const accounts = ONCHAIN_EARNER_NETWORKS.has(network)
        ? await fetchEarnerAddressesOnChain(network)
        : await fetchEarnerAddresses(chainId);
      console.log(`Found ${accounts.length} earner(s)`);

      const csvPath = join("earners", `${network}.csv`);

      // Always write the CSV, even with zero earners: an empty (header-only) file
      // is the source of truth that tells generate-earners-array.ts to emit an
      // empty-array migration function for this network, rather than omitting it.
      if (accounts.length === 0) {
        writeFileSync(csvPath, toCsv([]));
        console.log(`Exported 0 earners to ${csvPath} (header only)`);
        continue;
      }

      const balances = await fetchBalances(network, accounts);
      const rows = accounts
        .map((address) => ({ address, balance: balances.get(address) ?? "" }))
        .sort(byBalanceDesc);

      writeFileSync(csvPath, toCsv(rows));
      console.log(`Exported ${rows.length} earners to ${csvPath}`);
    } catch (error) {
      console.error(
        `Error processing ${network}:`,
        error instanceof Error ? error.message : error,
      );
    }
  }
}

main();
