param()

if (-not $env:PRIVATE_KEY) { Write-Error "Set env var PRIVATE_KEY (hex without 0x)"; exit 1 }
if (-not $env:RPC_URL) { Write-Error "Set env var RPC_URL"; exit 1 }
if (-not $env:USDC) { Write-Error "Set env var USDC (token address)"; exit 1 }
if (-not $env:ORACLE_ADAPTER) { Write-Error "Set env var ORACLE_ADAPTER (address)"; exit 1 }

$pk = $env:PRIVATE_KEY
$rpc = $env:RPC_URL

Write-Host "Running forge deploy script..."
forge script script/Deploy.s.sol:DeployScript --rpc-url $rpc --private-key $pk --broadcast -vvvv | Tee-Object -Variable out

# Try to extract proxy address from output
$addressLine = $out | Select-String -Pattern "PredictionMarket proxy:" | Select-Object -Last 1
if ($addressLine) {
    $addr = ($addressLine -split ":")[-1].Trim()
    Write-Host "Deployed PredictionMarket proxy at $addr"

    # Update subgraph manifest if placeholder present
    $manifest = "subgraph/subgraph.yaml"
    if (Test-Path $manifest) {
        (Get-Content $manifest) -replace "REPLACE_WITH_MARKET_ADDRESS", $addr | Set-Content $manifest
        Write-Host "Updated $manifest with deployed address."
    }
} else {
    Write-Warning "Could not find proxy address in forge output. Check logs above." 
}
