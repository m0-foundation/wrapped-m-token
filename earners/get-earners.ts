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
import { Contract, JsonRpcProvider } from "ethers";

// Load `.env` so ALCHEMY_API_KEY / ZERO_INDEXER_* don't have to be exported by
// hand. Shell-provided values win over the file; a missing `.env` is fine.
try {
  process.loadEnvFile();
} catch {
  // no .env file — rely on the ambient environment
}

const GRAPHQL_URL =
  process.env.ZERO_INDEXER_GRAPHQL_URL ?? "http://localhost:8080/v1/graphql";
const GRAPHQL_SECRET = process.env.ZERO_INDEXER_GRAPHQL_SECRET;
const ALCHEMY_API_KEY = process.env.ALCHEMY_API_KEY;

// wM is the same proxy address on every chain.
const WM_ADDRESS = "0x437cc33344a0b27a429f795ff6b469c72698b291";
const PAGE_SIZE = 1000;
const BALANCE_CONCURRENCY = 10;

// Network name -> zero-indexer chain_id. A chain may be indexed at the chain level
// while its wM earner set stays empty until the wM earning reducer + backfill land
// in zero-indexer (the missing piece these tools depend on).
const CHAIN_IDS: Record<string, number> = {
  ethereum: 1,
  bsc: 56,
  monad: 143,
  hyperevm: 999,
  soneium: 1868,
  moca: 2288,
  citrea: 4114,
  rise: 4153,
  mantra: 5888,
  base: 8453,
  plasma: 9745,
  "0g": 16661,
  fluent: 25363,
  arbitrum: 42161,
  linea: 59144,
  plume: 98866,
};

// All 16 EVM chains where WrappedM is deployed (per the M0 platform addresses).
const NETWORKS = [
  "0g",
  "arbitrum",
  "base",
  "bsc",
  "citrea",
  "ethereum",
  "fluent",
  "hyperevm",
  "linea",
  "mantra",
  "moca",
  "monad",
  "plasma",
  "plume",
  "rise",
  "soneium",
];

// Alchemy network slug per network, used to build the balanceOf RPC URL at
// runtime from ALCHEMY_API_KEY. Networks without a verified Alchemy mainnet
// endpoint (mantra, plume, citrea, 0g, fluent, moca) are omitted here and use a
// public RPC from PUBLIC_RPCS instead.
const ALCHEMY_NETWORKS: Record<string, string> = {
  ethereum: "eth-mainnet",
  bsc: "bnb-mainnet",
  hyperevm: "hyperliquid-mainnet",
  soneium: "soneium-mainnet",
  base: "base-mainnet",
  plasma: "plasma-mainnet",
  arbitrum: "arb-mainnet",
  linea: "linea-mainnet",
  rise: "rise-mainnet",
  monad: "monad-mainnet",
};

// Public RPC per network Alchemy doesn't support, so these get balanceOf reads
// too — no Alchemy key needed. URLs verified against the ethereum-lists/chains
// registry, each confirmed live and returning the expected chain_id.
const PUBLIC_RPCS: Record<string, string> = {
  citrea: "https://rpc.mainnet.citrea.xyz",
  mantra: "https://evm.mantrachain.io",
  "0g": "https://evmrpc.0g.ai",
  fluent: "https://rpc.fluent.xyz",
  moca: "https://rpc.mocachain.org",
  plume: "https://rpc.plume.org",
};

function rpcUrlFor(network: string): string | undefined {
  const slug = ALCHEMY_NETWORKS[network];
  if (slug && ALCHEMY_API_KEY) {
    return `https://${slug}.g.alchemy.com/v2/${ALCHEMY_API_KEY}`;
  }
  // Networks Alchemy doesn't support fall back to a public RPC.
  return PUBLIC_RPCS[network];
}

const ERC20_ABI = [
  "function balanceOf(address account) view returns (uint256)",
];

type GraphQLResponse<T> = {
  data?: T;
  errors?: Array<{ message: string }>;
};

async function graphql<T>(
  query: string,
  variables: Record<string, unknown>,
): Promise<T> {
  const res = await fetch(GRAPHQL_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(GRAPHQL_SECRET ? { "x-hasura-admin-secret": GRAPHQL_SECRET } : {}),
    },
    body: JSON.stringify({ query, variables }),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status} from ${GRAPHQL_URL}`);
  const body = (await res.json()) as GraphQLResponse<T>;
  if (body.errors?.length) {
    throw new Error(`GraphQL: ${body.errors.map((e) => e.message).join(", ")}`);
  }
  if (!body.data) throw new Error("GraphQL: empty response");
  return body.data;
}

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

/** On-chain balanceOf per earner, bounded concurrency. Empty map when no RPC. */
async function fetchBalances(
  network: string,
  accounts: string[],
): Promise<Map<string, string>> {
  const rpcUrl = rpcUrlFor(network);
  const balances = new Map<string, string>();
  if (!rpcUrl) {
    console.warn(`  no RPC for ${network} — balances left empty`);
    return balances;
  }
  const wm = new Contract(WM_ADDRESS, ERC20_ABI, new JsonRpcProvider(rpcUrl));
  for (let i = 0; i < accounts.length; i += BALANCE_CONCURRENCY) {
    const slice = accounts.slice(i, i + BALANCE_CONCURRENCY);
    const results = await Promise.all(
      slice.map(async (account) => {
        try {
          const bal = (await wm.balanceOf(account)) as bigint;
          return [account, bal.toString()] as const;
        } catch (err) {
          console.warn(
            `  balanceOf failed for ${account}: ${(err as Error).message}`,
          );
          return [account, ""] as const;
        }
      }),
    );
    for (const [account, bal] of results) balances.set(account, bal);
  }
  return balances;
}

type Row = { address: string; balance: string };

/**
 * Highest balance first, ties broken by address ascending. Earners with no
 * balance (empty string — no RPC, or a failed `balanceOf`) sort last. Ordering
 * is cosmetic: every consumer (generate-earners-array, DeployBase._sortAddresses,
 * ListOfEarnersToMigrate) re-sorts by address, so this only aids human reading.
 */
function byBalanceDesc(a: Row, b: Row): number {
  const aBal = a.balance === "" ? -1n : BigInt(a.balance);
  const bBal = b.balance === "" ? -1n : BigInt(b.balance);
  if (aBal !== bBal) return aBal < bBal ? 1 : -1;
  return a.address < b.address ? -1 : a.address > b.address ? 1 : 0;
}

function toCsv(rows: Array<Row>): string {
  return [
    "address,balance",
    ...rows.map((r) => `${r.address},${r.balance}`),
  ].join("\n");
}

/**
 * Resolve which networks to export. With no argument, every network in
 * `NETWORKS` is exported; with `<network>` only that one is. An unknown name is
 * a hard error rather than a silent empty run.
 */
function selectNetworks(arg: string | undefined): string[] {
  if (arg === undefined) return NETWORKS;
  if (!NETWORKS.includes(arg)) {
    throw new Error(`unknown network "${arg}" — known: ${NETWORKS.join(", ")}`);
  }
  return [arg];
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
