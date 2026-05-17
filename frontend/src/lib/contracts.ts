const zeroAddress = "0x0000000000000000000000000000000000000000" as const;

function readAddress(value: string | undefined): `0x${string}` | undefined {
  if (!value || value === zeroAddress) {
    return undefined;
  }

  return value as `0x${string}`;
}

function readNumber(value: string | undefined, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

export const appConfig = {
  chainId: readNumber(import.meta.env.VITE_CHAIN_ID, 31337),
  rpcUrl: import.meta.env.VITE_RPC_URL ?? "http://127.0.0.1:8545",
  subgraphUrl: import.meta.env.VITE_SUBGRAPH_URL ?? "http://localhost:8000/subgraphs/name/prediction-protocol",
  predictionMarketAddress: readAddress(import.meta.env.VITE_PREDICTION_MARKET_ADDRESS),
  outcomeTokenAddress: readAddress(import.meta.env.VITE_OUTCOME_TOKEN_ADDRESS),
  usdcAddress: readAddress(import.meta.env.VITE_USDC_ADDRESS),
  feeVaultAddress: readAddress(import.meta.env.VITE_FEE_VAULT_ADDRESS),
  oracleFeedAddress: readAddress(import.meta.env.VITE_ORACLE_FEED_ADDRESS),
  defaultMarketId: readNumber(import.meta.env.VITE_DEFAULT_MARKET_ID, 1),
};

export const hasCoreContracts = Boolean(appConfig.predictionMarketAddress && appConfig.outcomeTokenAddress && appConfig.usdcAddress);
