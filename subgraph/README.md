# Subgraph (minimal scaffold)

Steps to use this scaffold:

1. Replace the `source.address` in `subgraph.yaml` with your deployed `PredictionMarket` address.
2. Install Graph CLI and dependencies, then codegen:

```bash
npm install -g @graphprotocol/graph-cli
cd subgraph
npm init -y
npm install --save @graphprotocol/graph-ts
graph codegen
```

3. Deploy to hosted service or local graph-node following Graph docs.

## Local Graph node

This folder includes a Docker Compose stack that runs IPFS, Postgres, and Graph Node locally.
It is wired to the local Anvil RPC at `http://host.docker.internal:8545` and reuses the
`sepolia` provider name from `subgraph.yaml`, so you do not need to edit the manifest.

Run it from this folder:

```powershell
docker compose up -d
```

Then deploy the built subgraph:

```powershell
graph create --node http://localhost:8020/ <your-subgraph-name>
graph deploy --node http://localhost:8020/ --ipfs http://localhost:5001/ <your-subgraph-name>
```

Before deploying, make sure `subgraph/subgraph.yaml` points at your local `PredictionMarket`
proxy address and that Anvil is running on port `8545`.

Optional: use the Foundry deploy script to deploy contracts and automatically
populate `subgraph/subgraph.yaml` with the deployed `PredictionMarket` address:

```powershell
# set env vars: PRIVATE_KEY RPC_URL USDC ORACLE_ADAPTER
.
./scripts/deploy.ps1
```

