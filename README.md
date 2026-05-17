# Prediction Protocol — Local Dev & Verification

This repository contains a prediction market smart-contract system (Foundry), a Vite React frontend, and a Graph subgraph for local indexing.

## Quick status
- Contracts: solidity sources in `src/` with Foundry scripts in `script/`.
- Frontend: `frontend/` (Vite + React + Wagmi).
- Subgraph: `subgraph/` (Graph CLI + AssemblyScript mappings).

## Prerequisites
- Foundry (`forge`, `anvil`) — https://book.getfoundry.sh/
- Node.js 18+ and `npm`
- Docker (for local Graph Node stack)
- `@graphprotocol/graph-cli` (for codegen/build/deploy)

## Local development (summary)

1. Start Anvil (local chain):

```powershell
anvil
```

2. Deploy contracts locally (uses Foundry script):

```powershell
forge script script/LocalDeploy.s.sol:LocalDeployScript --rpc-url http://127.0.0.1:8545 --broadcast
```

3. Start Graph Node stack and deploy subgraph:

```powershell
cd subgraph
docker compose up -d
npm ci
npm run codegen
npm run build
graph create --node http://localhost:8020/ prediction-protocol
graph deploy --node http://localhost:8020/ --ipfs http://localhost:5001/ prediction-protocol
```

4. Run frontend:

```powershell
cd frontend
npm ci
npm run dev
```

## Verifying contracts (Etherscan)

To verify contracts on Etherscan (or Etherscan-compatible explorers) after deploying to a public network, you can use Foundry's `forge verify-contract` command.

1. Export your API key:

```bash
export ETHERSCAN_API_KEY=your_api_key_here
# on Windows PowerShell use:
$env:ETHERSCAN_API_KEY = 'your_api_key_here'
```

2. Run `forge verify-contract` for each implementation address. Example:

```bash
forge verify-contract --chain sepolia 0xYourContractAddress 'src/core/PredictionMarket.sol:PredictionMarket'
```

Notes:
- You must supply the correct fully-qualified contract name `path:ContractName`.
- If your contract uses constructor args or proxies, you may need to pass constructor parameters or verify the implementation contract instead of a proxy. See Foundry docs.

## Tests & checks

- Format: `forge fmt`
- Tests: `forge test`
- Frontend typecheck + build:
  - `cd frontend && npm ci && npm run check && npm run build`
- Subgraph codegen + build:
  - `cd subgraph && npm ci && npm run codegen && npm run build`

CI: see `.github/workflows/ci.yml` — it runs `forge test`, frontend build/typecheck, and subgraph codegen/build.

## Notes & troubleshooting
- If you change contracts and redeploy locally, update `subgraph/subgraph.yaml` with the new deployed addresses and re-run `graph codegen` and `graph build` before `graph deploy`.
- Local Graph Node requires Postgres with C locale. If you change the PostgreSQL service config, re-create the Docker volumes.

---
If you'd like, I can:
- add `forge verify` helper scripts that wrap `forge verify-contract` for common networks, or
- attempt automatic verification for a specific network now (you'd need to provide the appropriate API key and deployed addresses).
