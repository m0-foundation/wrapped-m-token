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
import {
  byBalanceDesc,
  CHAIN_IDS,
  fetchBalances,
  graphql,
  PAGE_SIZE,
  selectNetworks,
  toCsv,
} from "../script/wm-common";

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
      const accounts = await fetchEarnerAddresses(chainId);
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
