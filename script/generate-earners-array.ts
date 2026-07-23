#!/usr/bin/env tsx

/**
 * Generate `script/EarnersAddresses.sol` from the per-network earner CSVs in
 * `earners/`.
 *
 * The CSVs are the single source of truth for the wM earner set: they are
 * produced by `earners/get-earners.ts` from zero-indexer's `wm_earner` table
 * (every row is already an `is_earning = true` earner). This script just turns
 * each `earners/<network>.csv` into a `get<Network>Earners()` Solidity function
 * holding the checksummed, sorted, de-duplicated address list the v1->v2
 * migration consumes.
 *
 * Every network with a CSV gets a `get<Network>Earners()` function, including
 * networks with no earners: get-earners.ts writes a header-only CSV for those,
 * and they yield a function returning an empty array (a valid no-op migration).
 *
 * It also emits a `getEarners(uint256 chainId_)` dispatcher mapping each network's
 * chain id to its function, so the deploy script resolves earners by chain id
 * without hand-maintained branches.
 *
 * Run: ./script/generate-earners-array.ts
 *      (or: npx tsx script/generate-earners-array.ts)
 */
import { readdirSync, readFileSync, writeFileSync } from "fs";
import { join } from "path";
import { getAddress } from "ethers";

const EARNERS_DIR = "earners";
const OUTPUT_PATH = join("script", "EarnersAddresses.sol");
const CSV_HEADER = "address,balance";

// Network name -> chain id, mirroring `earners/get-earners.ts`. Used to generate
// the `getEarners(chainId)` dispatcher so the deploy script resolves a chain's
// earner set without hand-maintained branches.
const CHAIN_IDS: Record<string, number> = {
  ethereum: 1,
  bsc: 56,
  monad: 143,
  hyperevm: 999,
  soneium: 1868,
  moca: 2288,
  nexus: 3946,
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

/** Networks present as `earners/<network>.csv`, sorted for deterministic output. */
function discoverNetworks(): string[] {
  return readdirSync(EARNERS_DIR)
    .filter((file) => file.endsWith(".csv"))
    .map((file) => file.slice(0, -".csv".length))
    .sort();
}

/**
 * Parse the `address` column out of an `earners/<network>.csv`. The header is
 * validated so a format change can't silently feed garbage into the migration.
 */
function readEarnerAddresses(network: string): string[] {
  const path = join(EARNERS_DIR, `${network}.csv`);
  const lines = readFileSync(path, "utf8")
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  const [header, ...rows] = lines;

  if (header !== CSV_HEADER) {
    throw new Error(`${path}: unexpected header "${header ?? ""}" (expected "${CSV_HEADER}")`);
  }

  return rows.map((row) => row.split(",")[0]);
}

function toSortedUniqueAddresses(addresses: string[], network: string): string[] {
  const sorted = addresses
    .map((address) => {
      const checksummed = getAddress(address);
      return { address: checksummed, value: BigInt(checksummed) };
    })
    .sort((a, b) => (a.value < b.value ? -1 : a.value > b.value ? 1 : 0));

  for (let i = 0; i < sorted.length; ++i) {
    if (sorted[i].value === 0n) {
      throw new Error(`Zero address present in ${network} earners`);
    }

    if (i > 0 && sorted[i].value === sorted[i - 1].value) {
      throw new Error(`Duplicate earner address ${sorted[i].address} on ${network}`);
    }
  }

  return sorted.map((e) => e.address);
}

function generateFunctionName(network: string): string {
  return `get${network.charAt(0).toUpperCase() + network.slice(1)}Earners`;
}

function generateSolidityFunction(network: string, addresses: string[]): string {
  const functionName = generateFunctionName(network);
  const arrayLength = addresses.length;

  // A network with no earners returns an empty array directly: a fixed-size
  // `address[0]` literal isn't valid Solidity, and the migration treats an empty
  // earner set as a valid (no-op) migration.
  if (arrayLength === 0) {
    return `    function ${functionName}() internal pure returns (address[] memory) {
        return new address[](0);
    }
`;
  }

  const addressesLines = addresses.map((addr) => `            ${addr}`).join(",\n");

  return `    function ${functionName}() internal pure returns (address[] memory) {
        address[${arrayLength}] memory earners = [
${addressesLines}
        ];
        address[] memory result = new address[](${arrayLength});
        for (uint256 i = 0; i < ${arrayLength}; ++i) {
            result[i] = earners[i];
        }
        return result;
    }
`;
}

/**
 * Generate the `getEarners(uint256 chainId_)` dispatcher: one `if` per network
 * mapping its chain id to its `get<Network>Earners()` function. An unmapped chain
 * reverts rather than silently migrating an empty set on the wrong network.
 */
function generateDispatcher(networks: string[]): string {
  const branches = networks
    .map((network) => {
      const chainId = CHAIN_IDS[network];
      if (chainId === undefined) {
        throw new Error(`no chain id mapped for network "${network}" — add it to CHAIN_IDS`);
      }
      return `        if (chainId_ == ${chainId}) return ${generateFunctionName(network)}();`;
    })
    .join("\n");

  return `    function getEarners(uint256 chainId_) internal pure returns (address[] memory) {
${branches}
        revert("Unsupported chain ID");
    }
`;
}

function buildSolidityFile(functions: string[]): string {
  return `// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

library EarnersAddresses {
${functions.join("")}}
`;
}

function main(): void {
  // NOTE: Build the whole file in memory and only write once every network succeeds. A failed or
  //       partial run must never leave a file mixing fresh and stale earner lists.
  const functions: string[] = [];
  const generatedNetworks: string[] = [];

  for (const network of discoverNetworks()) {
    const networkName = network.charAt(0).toUpperCase() + network.slice(1);

    const rawAddresses = readEarnerAddresses(network);
    console.log(`\n${networkName}: ${rawAddresses.length} earner(s) in ${network}.csv`);

    const addresses = toSortedUniqueAddresses(rawAddresses, network);
    functions.push(generateSolidityFunction(network, addresses));
    generatedNetworks.push(network);

    console.log(`Generated ${generateFunctionName(network)}() with ${addresses.length} checksummed addresses`);
  }

  functions.push(generateDispatcher(generatedNetworks));

  writeFileSync(OUTPUT_PATH, buildSolidityFile(functions));
  console.log(`\nWrote ${generatedNetworks.length} earner function(s) + dispatcher to ${OUTPUT_PATH}`);
}

main();
