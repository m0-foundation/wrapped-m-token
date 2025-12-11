#!/usr/bin/env tsx

import { readFileSync, writeFileSync } from "fs";
import { join } from "path";
import { getAddress } from "ethers";

interface WMHolder {
  address: string;
  balance: string;
  isEarning: boolean;
}

interface GraphQLResponse {
  data?: {
    WMHolders?: WMHolder[];
    WMHoldersArbitrum?: WMHolder[];
  };
  errors?: Array<{ message: string }>;
}

const PROTOCOL_API_URL = "https://protocol-api.m0.org/graphql";

async function fetchWMHolders(network: string): Promise<WMHolder[]> {
  const fieldName = network === "ethereum" ? "WMHolders" : "WMHoldersL2";
  const chainArg =
    network === "ethereum" ? "" : `chain: ${network.toUpperCase()}`;

  const query = `
    query GetWMHolders {
      ${fieldName}(first: 1000, ${chainArg}) {
        address
        balance
        isEarning
      }
    }
  `;

  const response = await fetch(PROTOCOL_API_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ query }),
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

  return result.data?.[fieldName as keyof GraphQLResponse["data"]] || [];
}

function generateFunctionName(network: string): string {
  return `get${network.charAt(0).toUpperCase() + network.slice(1)}Earners`;
}

function generateSolidityFunction(
  network: string,
  earners: WMHolder[],
): string {
  const functionName = generateFunctionName(network);
  const earnerAddresses = earners.map((e) => getAddress(e.address));
  const arrayLength = earnerAddresses.length;

  const addressesLines = earnerAddresses
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

function getOrCreateSolidityFile(): string {
  const outputPath = join("script", "EarnersAddresses.sol");

  try {
    return readFileSync(outputPath, "utf-8");
  } catch (error) {
    return `// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

library EarnersAddresses {
}
`;
  }
}

function updateSolidityFile(network: string, earners: WMHolder[]): void {
  const outputPath = join("script", "EarnersAddresses.sol");
  let content = getOrCreateSolidityFile();
  const functionName = generateFunctionName(network);

  const newFunction = generateSolidityFunction(network, earners);

  if (content.includes(functionName)) {
    const functionStart = content.indexOf(`function ${functionName}`);
    if (functionStart === -1) {
      throw new Error(`Could not find function ${functionName}`);
    }

    const openBrace = content.indexOf("{", functionStart);
    if (openBrace === -1) {
      throw new Error(`Could not find opening brace for ${functionName}`);
    }

    let braceCount = 0;
    let functionEnd = -1;
    for (let i = openBrace; i < content.length; i++) {
      if (content[i] === "{") braceCount++;
      else if (content[i] === "}") {
        braceCount--;
        if (braceCount === 0) {
          functionEnd = i;
          break;
        }
      }
    }

    if (functionEnd === -1) {
      throw new Error(`Could not find closing brace for ${functionName}`);
    }

    content =
      content.slice(0, functionStart) +
      newFunction +
      content.slice(functionEnd + 1);
    console.log(`Updated existing ${functionName}() function`);
  } else {
    const libraryEndIndex = content.lastIndexOf("}");
    if (libraryEndIndex === -1) {
      throw new Error("Invalid Solidity file format");
    }
    content =
      content.slice(0, libraryEndIndex) +
      newFunction +
      content.slice(libraryEndIndex);
    console.log(`Added new ${functionName}() function`);
  }

  writeFileSync(outputPath, content);
}

async function main() {
  const networks = [
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

  for (const network of networks) {
    const networkName = network.charAt(0).toUpperCase() + network.slice(1);

    try {
      console.log(`\nFetching WrappedM holders from ${networkName}...`);

      const holders = await fetchWMHolders(network);
      console.log(`Found ${holders.length} WrappedM holders on ${networkName}`);

      if (holders.length === 0) {
        console.log("No holders found");
        continue;
      }

      const earners = holders.filter((holder) => holder.isEarning);
      console.log(
        `Found ${earners.length} WrappedM earners (isEarning = true)`,
      );

      if (earners.length === 0) {
        console.log("No earners found");
        continue;
      }

      updateSolidityFile(network, earners);

      const functionName = generateFunctionName(network);
      console.log(
        `Added ${functionName}() with ${earners.length} checksummed addresses to EarnersAddresses.sol`,
      );
    } catch (error) {
      console.error(
        `Error processing ${networkName}:`,
        error instanceof Error ? error.message : error,
      );
    }
  }
}

main();
