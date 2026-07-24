#!/usr/bin/env tsx

/**
 * Verify the wM earner set and their balances around the v2 upgrade, on the
 * chains that actually get upgraded: Base, Arbitrum, Ethereum.
 *
 * The upgrade is a proxy implementation swap that must PRESERVE per-account
 * state. This tool captures a snapshot of that state at a block and diffs two
 * snapshots (before vs after the upgrade), asserting the invariants held.
 *
 * Snapshot content, per earner, read on-chain at one pinned block:
 *   - isEarning        — the contract's own earning flag
 *   - balance          — `balanceOf`, the STORED balance. Yield accrues into
 *                        `accruedYieldOf`, NOT into this, so it does not drift
 *                        block-to-block and is a true invariant. (By contrast
 *                        `balanceWithYieldOf` grows every block with the index,
 *                        so it is deliberately not compared.)
 *   - earningPrincipal — `earningPrincipalOf`, the yield basis. v2-ONLY: it
 *                        reverts on the pre-upgrade contract and is recorded as
 *                        `null` there, so it cannot be diffed across the
 *                        upgrade — it is instead ASSERTED on the after side.
 *   - expectedPrincipal — v1-ONLY: the principal the migration will derive for
 *                        this account, read from v1's own `lastIndex` slot, so
 *                        the post-upgrade value can be checked exactly.
 *
 * `isEarning` and `balance` are the cross-version invariants: readable on both
 * v1 (pre) and v2 (post), and both must survive the migration unchanged.
 * `earningPrincipal` is checked differently, since a preserved balance alone
 * does not prove the account will actually accrue. After the upgrade it must be
 * readable — a null means the function still reverts, so the proxy was likely
 * never upgraded. Its VALUE is then checked exactly: the migration derives each
 * principal as `getPrincipalAmountRoundedDown(balance, lastIndex)` from v1
 * state, which the before snapshot captured, so the post-upgrade number is
 * predictable and any deviation is a mis-migrated yield basis.
 *
 * Where no such prediction exists (comparing two v2 snapshots), it falls back to
 * a plausibility check: a zero principal is flagged only where the balance
 * implies a non-zero one. Zero is CORRECT for an earner holding nothing — the
 * principal is rounded down from the balance, and 5 of the 25 Ethereum earners
 * sit at zero — so that case is not reported.
 *
 * The earner SET itself comes from `fetchOnChainEarners` (StartedEarning /
 * StoppedEarning replay), pinned to the same block.
 *
 * A snapshot also cross-checks the on-chain earner set against the committed
 * `earners/<network>.csv` — the exact list the upgrade will migrate — so a
 * missing or stale entry surfaces before the upgrade, not after.
 *
 * Usage:
 *   npm run verify-earners -- <network> before [block]   snapshot pre-upgrade
 *   npm run verify-earners -- <network> after  [block]   snapshot post-upgrade
 *   npm run verify-earners -- <network> compare          diff before vs after
 *
 * `block` defaults to latest; pass the exact pre/post-upgrade block for an
 * atomic, reproducible snapshot (historical reads need an archive RPC, which
 * Alchemy provides for these chains). Snapshots live in `earners/snapshots/`.
 *
 * Env: ALCHEMY_API_KEY (eth-mainnet / arb-mainnet / base-mainnet). See
 * `script/wm-common.ts` for RPC routing.
 */
import { mkdirSync, readFileSync, writeFileSync } from "fs";
import { join } from "path";
import {
  AbiCoder,
  Contract,
  JsonRpcProvider,
  keccak256,
  toBeHex,
} from "ethers";
import {
  BALANCE_CONCURRENCY,
  CHAIN_IDS,
  fetchOnChainEarners,
  rpcUrlFor,
  WM_ADDRESS,
} from "../script/wm-common";

// The chains the v2 upgrade touches: sepolia (the testnet rehearsal, run first)
// then the mainnets base, arbitrum, plasma, ethereum. Every other wM chain is
// being deprecated, so there is nothing to verify there. (Plasma has no earners,
// so its earner-migration checks are trivial — its substantive post-upgrade
// checks are the implementation-slot spot-check and the sizeable claimable
// excess, both covered in the runbook.)
const UPGRADE_NETWORKS = ["sepolia", "base", "arbitrum", "plasma", "ethereum"];

const SNAPSHOT_DIR = join("earners", "snapshots");

// `IndexingMath.EXP_SCALED_ONE`. The contract derives an earner's principal as
// `getPrincipalAmountRoundedDown(balance, index)` = `(balance * 1e12) / index`,
// which this mirrors to tell a legitimately-zero principal from a broken one.
const EXP_SCALED_ONE = 1_000_000_000_000n;

// v1 keeps `_accounts` at storage slot 6 (see `WrappedMTokenMigratorV1._getAccounts`),
// laid out as `{bool isEarning; uint240 balance;}` in the account's first slot and
// `uint128 lastIndex` in its second. v2 reuses that second slot for
// `uint112 earningPrincipal`, so it only means `lastIndex` while still on v1.
const V1_ACCOUNTS_SLOT = 6n;

const WM_ABI = [
  "function isEarning(address account) view returns (bool)",
  "function balanceOf(address account) view returns (uint256)",
  "function earningPrincipalOf(address account) view returns (uint112)",
  "function currentIndex() view returns (uint128)",
];

type EarnerState = {
  address: string;
  isEarning: boolean;
  balance: string;
  /** `null` when the contract has no `earningPrincipalOf` — i.e. still v1. */
  earningPrincipal: string | null;
  /**
   * On v1 only: the principal the migrator will compute for this account, so the
   * after-upgrade value can be checked against it. `null` on v2, where
   * `earningPrincipal` is already the real thing.
   */
  expectedPrincipal: string | null;
};

type Snapshot = {
  network: string;
  chainId: number;
  phase: string;
  block: number;
  currentIndex: string;
  wm: string;
  capturedAt: string;
  earners: EarnerState[];
};

function snapshotPath(network: string, phase: string): string {
  return join(SNAPSHOT_DIR, `${network}.${phase}.json`);
}

/** Addresses (lowercased) in the committed `earners/<network>.csv`. */
function committedEarners(network: string): Set<string> {
  const csv = readFileSync(join("earners", `${network}.csv`), "utf8");
  const rows = csv.trim().split("\n").slice(1); // drop the `address,balance` header
  return new Set(
    rows.filter(Boolean).map((line) => line.split(",")[0].toLowerCase()),
  );
}

/**
 * `earningPrincipalOf` exists only on v2, so on the pre-upgrade contract the
 * call hits no function and reverts with no data. That is expected and maps to
 * `null`. A transport failure must NOT be silently swallowed the same way — it
 * would masquerade as "not upgraded yet" — so only the ABI-level errors
 * (CALL_EXCEPTION / BAD_DATA) are treated as absence; anything else rethrows.
 */
async function readEarningPrincipal(
  wm: Contract,
  address: string,
  blockTag: number,
): Promise<string | null> {
  try {
    const principal = (await wm.earningPrincipalOf(address, {
      blockTag,
    })) as bigint;
    return principal.toString();
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code === "CALL_EXCEPTION" || code === "BAD_DATA") return null;
    throw error;
  }
}

/**
 * The principal the migration will write for this account, computed exactly as
 * `WrappedMTokenMigratorV1._migrateEarners` does:
 * `getPrincipalAmountRoundedDown(balance, lastIndex)`.
 *
 * Only meaningful on v1, where the account's second slot still holds `lastIndex`
 * — on v2 that slot is `earningPrincipal` and reading it this way would be
 * nonsense. Validated against live v1 state on ethereum, arbitrum and sepolia:
 * the principal derived here reproduces the contract's own `accruedYieldOf` to
 * the digit.
 */
async function computeExpectedPrincipal(
  provider: JsonRpcProvider,
  address: string,
  balance: bigint,
  blockTag: number,
): Promise<string | null> {
  const accountSlot = BigInt(
    keccak256(
      AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256"],
        [address, V1_ACCOUNTS_SLOT],
      ),
    ),
  );
  const raw = await provider.getStorage(
    WM_ADDRESS,
    toBeHex(accountSlot + 1n, 32),
    blockTag,
  );
  const lastIndex = BigInt(raw) & ((1n << 128n) - 1n);
  // No basis to predict from (and dividing by it would throw).
  if (lastIndex === 0n) return null;
  return ((balance * EXP_SCALED_ONE) / lastIndex).toString();
}

/** Per-account on-chain state at a pinned block, bounded concurrency. */
async function readEarnerState(
  provider: JsonRpcProvider,
  accounts: string[],
  blockTag: number,
): Promise<EarnerState[]> {
  const wm = new Contract(WM_ADDRESS, WM_ABI, provider);
  const states: EarnerState[] = [];
  for (let i = 0; i < accounts.length; i += BALANCE_CONCURRENCY) {
    const slice = accounts.slice(i, i + BALANCE_CONCURRENCY);
    const results = await Promise.all(
      slice.map(async (address) => {
        const [isEarning, balance, earningPrincipal] = await Promise.all([
          wm.isEarning(address, { blockTag }) as Promise<boolean>,
          wm.balanceOf(address, { blockTag }) as Promise<bigint>,
          readEarningPrincipal(wm, address, blockTag),
        ]);
        // Predict the migrated principal only while still on v1; on v2 the real
        // value is already in hand.
        const expectedPrincipal =
          earningPrincipal === null
            ? await computeExpectedPrincipal(
                provider,
                address,
                balance,
                blockTag,
              )
            : null;
        return {
          address,
          isEarning,
          balance: balance.toString(),
          earningPrincipal,
          expectedPrincipal,
        };
      }),
    );
    states.push(...results);
  }
  return states;
}

async function snapshot(
  network: string,
  phase: string,
  blockArg: string | undefined,
): Promise<void> {
  const chainId = CHAIN_IDS[network];
  const rpcUrl = rpcUrlFor(network);
  if (!rpcUrl) {
    throw new Error(`no RPC for ${network} — set ALCHEMY_API_KEY`);
  }

  const provider = new JsonRpcProvider(rpcUrl);
  try {
    // Resolve one concrete block up front so the earner-set scan and every state
    // read see the same height — the snapshot is atomic, not smeared across
    // blocks as the calls execute.
    const block = blockArg ? Number(blockArg) : await provider.getBlockNumber();

    console.log(`\n${network} (chain ${chainId}) @ block ${block} [${phase}]`);

    const accounts = await fetchOnChainEarners(network, block);
    console.log(`  on-chain earners: ${accounts.length}`);

    // Cross-check the migration input list against reality.
    const committed = committedEarners(network);
    const onChainSet = new Set(accounts);
    const missing = [...onChainSet].filter((a) => !committed.has(a));
    const extra = [...committed].filter((a) => !onChainSet.has(a));
    if (missing.length === 0 && extra.length === 0) {
      console.log(`  committed earners/${network}.csv: matches on-chain set ✓`);
    } else {
      console.log(`  committed earners/${network}.csv: MISMATCH`);
      if (missing.length)
        console.log(
          `    on-chain but not in CSV (${missing.length}): ${missing.join(", ")}`,
        );
      if (extra.length)
        console.log(
          `    in CSV but not on-chain (${extra.length}): ${extra.join(", ")}`,
        );
    }

    const wm = new Contract(WM_ADDRESS, WM_ABI, provider);
    const currentIndex = (await wm.currentIndex({ blockTag: block })) as bigint;
    const earners = (await readEarnerState(provider, accounts, block)).sort(
      (a, b) => (a.address < b.address ? -1 : a.address > b.address ? 1 : 0),
    );

    const snap: Snapshot = {
      network,
      chainId,
      phase,
      block,
      currentIndex: currentIndex.toString(),
      wm: WM_ADDRESS,
      capturedAt: new Date().toISOString(),
      earners,
    };

    mkdirSync(SNAPSHOT_DIR, { recursive: true });
    const path = snapshotPath(network, phase);
    writeFileSync(path, JSON.stringify(snap, null, 2) + "\n");
    console.log(`  wrote ${earners.length} earner states to ${path}`);
  } finally {
    provider.destroy();
  }
}

function loadSnapshot(network: string, phase: string): Snapshot {
  const path = snapshotPath(network, phase);
  return JSON.parse(readFileSync(path, "utf8")) as Snapshot;
}

/**
 * Diff the before/after snapshots and assert the upgrade preserved state.
 * Returns true when every invariant held.
 */
function compare(network: string): boolean {
  const before = loadSnapshot(network, "before");
  const after = loadSnapshot(network, "after");

  const beforeMap = new Map(before.earners.map((e) => [e.address, e]));
  const afterMap = new Map(after.earners.map((e) => [e.address, e]));

  const removed = [...beforeMap.keys()].filter((a) => !afterMap.has(a));
  const added = [...afterMap.keys()].filter((a) => !beforeMap.has(a));

  const earningChanged: string[] = [];
  const balanceChanged: string[] = [];
  const principalChanged: string[] = [];
  for (const [address, b] of beforeMap) {
    const a = afterMap.get(address);
    if (!a) continue;
    if (a.isEarning !== b.isEarning)
      earningChanged.push(`${address}: ${b.isEarning} -> ${a.isEarning}`);
    if (a.balance !== b.balance)
      balanceChanged.push(`${address}: ${b.balance} -> ${a.balance}`);
    // Only meaningful when both sides expose it (v2 -> v2). Across the upgrade
    // the "before" side is null because v1 has no such function, which is an
    // expected version difference rather than a violation.
    if (
      b.earningPrincipal !== null &&
      a.earningPrincipal !== null &&
      a.earningPrincipal !== b.earningPrincipal
    )
      principalChanged.push(
        `${address}: ${b.earningPrincipal} -> ${a.earningPrincipal}`,
      );
  }

  // Post-upgrade assertions on the v2-only earning principal. A null principal
  // means `earningPrincipalOf` still reverts — the proxy is very likely NOT
  // upgraded.
  //
  // A ZERO principal is only a bug when the balance implies a non-zero one. The
  // contract rounds DOWN (`(balance * 1e12) / index`), so zero is the correct
  // answer for a zero-balance earner — an account that started earning while
  // empty, or moved its balance out afterwards, which is common (5 of the 25
  // Ethereum earners sit at zero) — and likewise for a dust balance that floors
  // away. Recomputing the expected principal keeps those out of the report, so a
  // hit here means the migration really did drop an earner's yield basis.
  //
  // Stronger still: when the before snapshot was taken on v1, it carries the
  // principal the migrator is going to derive from that account's balance and
  // lastIndex. The post-upgrade value is then fully predictable, so it can be
  // checked EXACTLY rather than merely for plausibility. The zero heuristic
  // below defers to that check whenever it applies, to avoid reporting one
  // defect twice.
  const afterIndex = BigInt(after.currentIndex);
  const principalMissing: string[] = [];
  const principalZero: string[] = [];
  const principalMismatch: string[] = [];
  for (const state of afterMap.values()) {
    if (!state.isEarning) continue;
    if (state.earningPrincipal === null) {
      principalMissing.push(
        `${state.address}: earningPrincipalOf unavailable (contract still v1?)`,
      );
      continue;
    }
    const predicted = beforeMap.get(state.address)?.expectedPrincipal ?? null;
    if (predicted !== null) {
      if (state.earningPrincipal !== predicted) {
        principalMismatch.push(
          `${state.address}: expected ${predicted} (from v1 balance ${state.balance} / lastIndex), got ${state.earningPrincipal}`,
        );
      }
      continue;
    }
    const expected = (BigInt(state.balance) * EXP_SCALED_ONE) / afterIndex;
    if (BigInt(state.earningPrincipal) === 0n && expected > 0n) {
      principalZero.push(
        `${state.address}: earningPrincipal is 0 but balance ${state.balance} implies ~${expected} — no yield basis`,
      );
    }
  }

  console.log(
    `\n${network}: compare before (block ${before.block}) vs after (block ${after.block})`,
  );
  console.log(`  earners: ${before.earners.length} -> ${after.earners.length}`);
  console.log(
    `  currentIndex: ${before.currentIndex} -> ${after.currentIndex} (yield accrual; balanceWithYield drifts, balanceOf does not)`,
  );

  const report = (label: string, items: string[]) => {
    if (items.length === 0) {
      console.log(`  ${label}: none ✓`);
      return;
    }
    console.log(`  ${label}: ${items.length} ✗`);
    for (const item of items) console.log(`    ${item}`);
  };

  report("removed earners", removed);
  report("added earners", added);
  report("isEarning changed", earningChanged);
  report("balanceOf changed", balanceChanged);
  report("earningPrincipal changed", principalChanged);
  report("earningPrincipal unavailable (post-upgrade)", principalMissing);
  report(
    "earningPrincipal != migrator-derived (post-upgrade)",
    principalMismatch,
  );
  report("earningPrincipal zero (post-upgrade)", principalZero);

  const ok =
    removed.length === 0 &&
    added.length === 0 &&
    earningChanged.length === 0 &&
    balanceChanged.length === 0 &&
    principalChanged.length === 0 &&
    principalMissing.length === 0 &&
    principalMismatch.length === 0 &&
    principalZero.length === 0;
  console.log(
    ok ? "\n  ALL INVARIANTS PRESERVED ✓" : "\n  INVARIANT VIOLATIONS FOUND ✗",
  );
  return ok;
}

async function main(): Promise<void> {
  const [network, phase, blockArg] = process.argv.slice(2);

  if (!network || !UPGRADE_NETWORKS.includes(network)) {
    throw new Error(
      `network must be one of: ${UPGRADE_NETWORKS.join(", ")} (got "${network ?? ""}")`,
    );
  }
  if (phase !== "before" && phase !== "after" && phase !== "compare") {
    throw new Error(
      `phase must be before | after | compare (got "${phase ?? ""}")`,
    );
  }

  if (phase === "compare") {
    const ok = compare(network);
    process.exitCode = ok ? 0 : 1;
    return;
  }
  await snapshot(network, phase, blockArg);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
