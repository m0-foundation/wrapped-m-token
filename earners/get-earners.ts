#!/usr/bin/env tsx

import { writeFileSync, mkdirSync } from "fs";
import { join } from "path";

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

function convertToCSV(holders: WMHolder[]): string {
  const headers = ["address", "balance"];
  const rows = holders.map((holder) => [holder.address, holder.balance]);

  return [headers, ...rows].map((row) => row.join(",")).join("\n");
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

  mkdirSync("earners", { recursive: true });

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

      const csvPath = join("earners", `${network}.csv`);
      const csvContent = convertToCSV(earners);

      writeFileSync(csvPath, csvContent);
      console.log(`Exported ${earners.length} earners to ${csvPath}`);

      const totalBalance = earners.reduce(
        (sum, h) => sum + parseFloat(h.balance || "0"),
        0,
      );

      console.log(`Total balance: ${totalBalance}`);
      console.log(`Total earners: ${earners.length}`);
    } catch (error) {
      console.error(
        `Error processing ${networkName}:`,
        error instanceof Error ? error.message : error,
      );
    }
  }
}

main();
