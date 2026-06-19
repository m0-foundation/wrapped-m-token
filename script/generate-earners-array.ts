#!/usr/bin/env tsx

import { writeFileSync } from "fs";
import { join } from "path";
import { getAddress } from "ethers";

interface WMHolder {
  address: string;
  isEarning: boolean;
}

interface GraphQLResponse {
  data?: Record<string, WMHolder[]>;
  errors?: Array<{ message: string }>;
}

const PROTOCOL_API_URL = "https://protocol-api.m0.org/graphql";
const OUTPUT_PATH = join("script", "EarnersAddresses.sol");
const PAGE_SIZE = 1000;
const MAX_PAGES = 100;
const REQUEST_TIMEOUT_MS = 30_000;

const NETWORKS = [
  "arbitrum",
  "base",
  "bsc",
  "ethereum",
  "hyperevm",
  "linea",
  "mantra",
  "optimism",
  "plasma",
  "plume",
  "soneium",
];

// NOTE: The `chain` argument must match the GraphQL `Chain` enum exactly. It defaults to the
//       uppercased network name; add an entry here if a network's enum value differs.
const CHAIN_ENUM_OVERRIDES: Record<string, string> = {};

function chainEnumFor(network: string): string {
  return CHAIN_ENUM_OVERRIDES[network] ?? network.toUpperCase();
}

function fieldNameFor(network: string): string {
  return network === "ethereum" ? "WMHolders" : "WMHoldersL2";
}

function generateFunctionName(network: string): string {
  return `get${network.charAt(0).toUpperCase() + network.slice(1)}Earners`;
}

async function graphqlRequest(query: string): Promise<GraphQLResponse> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    const response = await fetch(PROTOCOL_API_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query }),
      signal: controller.signal,
    });

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }

    const result: GraphQLResponse = await response.json();

    if (result.errors) {
      throw new Error(
        `GraphQL errors: ${result.errors.map((e) => e.message).join(", ")}`,
      );
    }

    return result;
  } finally {
    clearTimeout(timeout);
  }
}

async function fetchWMHolders(network: string): Promise<WMHolder[]> {
  const fieldName = fieldNameFor(network);
  const chainArg =
    network === "ethereum" ? "" : `, chain: ${chainEnumFor(network)}`;
  const holders: WMHolder[] = [];

  // NOTE: Paginate until a short page is returned so that earners are never silently truncated by
  //       the `first` cap. The `MAX_PAGES` guard prevents an infinite loop if `skip` is ignored.
  for (let page = 0; page < MAX_PAGES; ++page) {
    const query = `
      query GetWMHolders {
        ${fieldName}(first: ${PAGE_SIZE}, skip: ${page * PAGE_SIZE}${chainArg}) {
          address
          isEarning
        }
      }
    `;

    const result = await graphqlRequest(query);
    const pageHolders = result.data?.[fieldName] ?? [];

    holders.push(...pageHolders);

    if (pageHolders.length < PAGE_SIZE) return holders;
  }

  throw new Error(
    `Exceeded ${MAX_PAGES} pages (${MAX_PAGES * PAGE_SIZE} holders) fetching ${network}; pagination may be broken`,
  );
}

function toSortedUniqueAddresses(
  earners: WMHolder[],
  network: string,
): string[] {
  const sorted = earners
    .map((e) => {
      const address = getAddress(e.address);
      return { address, value: BigInt(address) };
    })
    .sort((a, b) => (a.value < b.value ? -1 : a.value > b.value ? 1 : 0));

  for (let i = 0; i < sorted.length; ++i) {
    if (sorted[i].value === 0n) {
      throw new Error(`Zero address present in ${network} earners`);
    }

    if (i > 0 && sorted[i].value === sorted[i - 1].value) {
      throw new Error(
        `Duplicate earner address ${sorted[i].address} on ${network}`,
      );
    }
  }

  return sorted.map((e) => e.address);
}

function generateSolidityFunction(
  network: string,
  addresses: string[],
): string {
  const functionName = generateFunctionName(network);
  const arrayLength = addresses.length;

  const addressesLines = addresses
    .map((addr) => `            ${addr}`)
    .join(",\n");

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

function buildSolidityFile(functions: string[]): string {
  return `// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

library EarnersAddresses {
${functions.join("")}}
`;
}

async function main(): Promise<void> {
  // NOTE: Build the whole file in memory and only write once every network succeeds. A failed or
  //       partial run must never leave a file mixing fresh and stale earner lists.
  const functions: string[] = [];

  for (const network of NETWORKS) {
    const networkName = network.charAt(0).toUpperCase() + network.slice(1);

    console.log(`\nFetching WrappedM holders from ${networkName}...`);

    const holders = await fetchWMHolders(network);
    console.log(`Found ${holders.length} WrappedM holders on ${networkName}`);

    const earners = holders.filter((holder) => holder.isEarning);
    console.log(`Found ${earners.length} WrappedM earners (isEarning = true)`);

    if (earners.length === 0) {
      console.log("No earners found, skipping");
      continue;
    }

    const addresses = toSortedUniqueAddresses(earners, network);
    functions.push(generateSolidityFunction(network, addresses));

    console.log(
      `Generated ${generateFunctionName(network)}() with ${addresses.length} checksummed addresses`,
    );
  }

  writeFileSync(OUTPUT_PATH, buildSolidityFile(functions));
  console.log(
    `\nWrote ${functions.length} earner function(s) to ${OUTPUT_PATH}`,
  );
}

main().catch((error) => {
  console.error(
    "Failed to generate earners list:",
    error instanceof Error ? error.message : error,
  );
  process.exitCode = 1;
});
