/**
 * Shared plumbing for the wM data-export scripts (`earners/get-earners.ts`,
 * `holders/get-holders.ts`).
 *
 * Both scripts follow the same shape — resolve a per-chain account set from
 * zero-indexer's Hasura endpoint, enrich it with on-chain `balanceOf`, write
 * `<dir>/<network>.csv` — so the chain tables, RPC routing, GraphQL client and
 * CSV formatting live here rather than being duplicated (and drifting) per
 * script. The network list in particular is load-bearing: when a chain is added
 * or swapped (e.g. optimism -> monad), it must change in exactly one place.
 *
 * Env (auto-loaded from `.env` if present; shell-exported values take precedence):
 *   ZERO_INDEXER_GRAPHQL_URL     Hasura endpoint (default http://localhost:8080/v1/graphql)
 *   ZERO_INDEXER_GRAPHQL_SECRET  optional x-hasura-admin-secret (public read needs none)
 *   ALCHEMY_API_KEY              optional — enables balanceOf on Alchemy networks (others use public RPCs)
 */
import { Contract, id, JsonRpcProvider, Log } from "ethers";

// Load `.env` so ALCHEMY_API_KEY / ZERO_INDEXER_* don't have to be exported by
// hand. Shell-provided values win over the file; a missing `.env` is fine.
try {
  process.loadEnvFile();
} catch {
  // no .env file — rely on the ambient environment
}

export const GRAPHQL_URL =
  process.env.ZERO_INDEXER_GRAPHQL_URL ?? "http://localhost:8080/v1/graphql";
const GRAPHQL_SECRET = process.env.ZERO_INDEXER_GRAPHQL_SECRET;
const ALCHEMY_API_KEY = process.env.ALCHEMY_API_KEY;

// wM is the same proxy address on every chain.
export const WM_ADDRESS = "0x437cc33344a0b27a429f795ff6b469c72698b291";
export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
export const PAGE_SIZE = 1000;
export const BALANCE_CONCURRENCY = 10;

// Network name -> chain_id. Most chains are sourced from zero-indexer's
// `wm_earner`; a chain may be indexed at the chain level while its wM earner set
// stays empty until the wM earning reducer + backfill land in zero-indexer.
// Sepolia is NOT indexed by zero-indexer at all, so `get-earners` derives its
// earner set directly from on-chain events (see ONCHAIN_EARNER_NETWORKS).
export const CHAIN_IDS: Record<string, number> = {
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
  sepolia: 11155111,
};

// The 16 mainnet EVM chains where WrappedM is deployed (per the M0 platform
// addresses), plus Sepolia — the testnet used to rehearse the v2 upgrade.
export const NETWORKS = [
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
  "sepolia",
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
  sepolia: "eth-sepolia",
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

export function rpcUrlFor(network: string): string | undefined {
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

export async function graphql<T>(
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

/** On-chain balanceOf per account, bounded concurrency. Empty map when no RPC. */
export async function fetchBalances(
  network: string,
  accounts: string[],
): Promise<Map<string, string>> {
  const rpcUrl = rpcUrlFor(network);
  const balances = new Map<string, string>();
  if (!rpcUrl) {
    console.warn(`  no RPC for ${network} — balances left empty`);
    return balances;
  }
  // Destroyed in `finally`: an unreachable RPC leaves ethers retrying network
  // detection on a timer forever, which keeps the event loop alive and stops the
  // script from ever exiting — even once every CSV has been written.
  const provider = new JsonRpcProvider(rpcUrl);
  try {
    const wm = new Contract(WM_ADDRESS, ERC20_ABI, provider);
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
  } finally {
    provider.destroy();
  }
}

// Topic0 of the wM earning events. `account` is the single indexed arg, so it
// lands in topics[1]; there is no non-indexed data to decode.
const STARTED_EARNING_TOPIC = id("StartedEarning(address)");
const STOPPED_EARNING_TOPIC = id("StoppedEarning(address)");

/** Lowercased account address from an earning event's indexed topics[1]. */
function earningAccountOf(log: Log): string {
  return `0x${log.topics[1].slice(-40)}`.toLowerCase();
}

/**
 * The wM earner set for a chain, derived straight from the contract's
 * StartedEarning / StoppedEarning logs — the same events zero-indexer's reducer
 * consumes, replayed here in (block, logIndex) order; the accounts left in the
 * earning state are the earners. Verified to reproduce the indexer's set exactly
 * on ethereum and arbitrum.
 *
 * `toBlock` pins the scan to a block so a snapshot is reproducible and lines up
 * with state reads at the same height (default "latest"). One full-range
 * getLogs, no chunking: fine for the Alchemy-backed chains this is used on
 * (base, arbitrum, ethereum, and the sepolia testnet); a rate-limited public RPC
 * could reject the range, which is acceptable given none of those use one.
 *
 * A missing RPC is a hard error: unlike balances (which degrade to empty), the
 * earner address set is the whole point, so an empty result must never be
 * mistaken for "no earners".
 */
export async function fetchOnChainEarners(
  network: string,
  toBlock: number | "latest" = "latest",
): Promise<string[]> {
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
      toBlock,
    });
    logs.sort((a, b) =>
      a.blockNumber !== b.blockNumber
        ? a.blockNumber - b.blockNumber
        : a.index - b.index,
    );
    const earning = new Map<string, boolean>();
    for (const log of logs) {
      earning.set(
        earningAccountOf(log),
        log.topics[0] === STARTED_EARNING_TOPIC,
      );
    }
    return [...earning].filter(([, isEarning]) => isEarning).map(([a]) => a);
  } finally {
    provider.destroy();
  }
}

export type Row = { address: string; balance: string };

/**
 * Highest balance first, ties broken by address ascending. Accounts with no
 * balance (empty string — no RPC, or a failed `balanceOf`) sort last. Ordering
 * is cosmetic: every consumer (generate-earners-array, DeployBase._sortAddresses,
 * ListOfEarnersToMigrate) re-sorts by address, so this only aids human reading.
 */
export function byBalanceDesc(a: Row, b: Row): number {
  const aBal = a.balance === "" ? -1n : BigInt(a.balance);
  const bBal = b.balance === "" ? -1n : BigInt(b.balance);
  if (aBal !== bBal) return aBal < bBal ? 1 : -1;
  return a.address < b.address ? -1 : a.address > b.address ? 1 : 0;
}

export function toCsv(rows: Array<Row>): string {
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
export function selectNetworks(arg: string | undefined): string[] {
  if (arg === undefined) return NETWORKS;
  if (!NETWORKS.includes(arg)) {
    throw new Error(`unknown network "${arg}" — known: ${NETWORKS.join(", ")}`);
  }
  return [arg];
}
