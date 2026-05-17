# Prediction Market Frontend

React + Wagmi dashboard for the Foundry prediction market contracts.

## Setup

1. Copy `.env.example` to `.env`.
2. Fill in the deployed contract addresses.
3. Set `VITE_SUBGRAPH_URL` to the local Graph Node endpoint, or leave it on the default `http://localhost:8000/subgraphs/name/prediction-protocol`.
4. Install dependencies and run the app:

```bash
npm install
npm run dev
```

The UI is designed to work against a local Anvil chain first, with Sepolia support available through env configuration.
