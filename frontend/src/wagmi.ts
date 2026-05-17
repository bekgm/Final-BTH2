import { QueryClient } from "@tanstack/react-query";
import { createConfig, http } from "wagmi";
import { injected } from "wagmi/connectors";
import { sepolia } from "wagmi/chains";
import { defineChain } from "viem";
import { appConfig } from "./lib/contracts";

export const localChain = defineChain({
  id: appConfig.chainId,
  name: "Local Anvil",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: [appConfig.rpcUrl] },
    public: { http: [appConfig.rpcUrl] },
  },
});

export const wagmiConfig = createConfig({
  chains: [localChain, sepolia],
  connectors: [injected()],
  transports: {
    [localChain.id]: http(appConfig.rpcUrl),
    [sepolia.id]: http(import.meta.env.VITE_SEPOLIA_RPC_URL ?? sepolia.rpcUrls.default.http[0]),
  },
  ssr: false,
});

export const queryClient = new QueryClient();
