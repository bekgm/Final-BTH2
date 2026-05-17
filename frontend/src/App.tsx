import { useMemo, useState, type ReactNode } from "react";
import { formatUnits, parseUnits } from "viem";
import { useQuery } from "@tanstack/react-query";
import {
  useAccount,
  useConnect,
  useDisconnect,
  useReadContract,
  useSwitchChain,
  useWriteContract,
} from "wagmi";
import { injected } from "wagmi/connectors";
import { sepolia } from "wagmi/chains";
import { erc1155Abi, erc20Abi, predictionMarketAbi } from "./lib/abis";
import { appConfig, hasCoreContracts } from "./lib/contracts";

const thousand = Intl.NumberFormat("en-US", { maximumFractionDigits: 2 });

type MarketTuple = readonly [
  bigint,
  string,
  `0x${string}`,
  `0x${string}`,
  bigint,
  bigint,
  boolean,
  bigint,
  bigint,
  bigint,
  bigint,
  `0x${string}`,
];

type SubgraphMarket = {
  id: string;
  question: string | null;
  creator: string | null;
  oracleFeed: string | null;
  resolutionTime: string | null;
  resolved: boolean | null;
  winningOutcome: number | null;
  totalCollateral: string | null;
  yesReserve: string | null;
  noReserve: string | null;
  feesAccrued: string | null;
  createdAt: string | null;
};

type SubgraphPayload = {
  market: SubgraphMarket | null;
  markets: SubgraphMarket[];
};

async function fetchSubgraph<T>(query: string, variables?: Record<string, unknown>): Promise<T> {
  const response = await fetch(appConfig.subgraphUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ query, variables }),
  });

  const payload = (await response.json()) as { data?: T; errors?: Array<{ message: string }> };

  if (!response.ok) {
    throw new Error(`Subgraph request failed with ${response.status}`);
  }

  if (payload.errors?.length) {
    throw new Error(payload.errors[0]?.message ?? "Subgraph query failed");
  }

  if (!payload.data) {
    throw new Error("Subgraph returned no data");
  }

  return payload.data;
}

function shortAddress(address?: string) {
  if (!address) return "n/a";
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

function formatAmount(value?: bigint, decimals = 18) {
  if (value === undefined) return "—";
  return thousand.format(Number(formatUnits(value, decimals)));
}

function toUnixSeconds(input: string) {
  return BigInt(Math.floor(new Date(input).getTime() / 1000));
}

function StatCard({ label, value, hint }: { label: string; value: string; hint: string }) {
  return (
    <div className="stat-card">
      <div className="stat-label">{label}</div>
      <div className="stat-value">{value}</div>
      <div className="stat-hint">{hint}</div>
    </div>
  );
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="field">
      <span>{label}</span>
      {children}
    </label>
  );
}

export default function App() {
  const [marketId, setMarketId] = useState<number>(appConfig.defaultMarketId);
  const [question, setQuestion] = useState("Will BTC close above $100k?");
  const [oracleFeed, setOracleFeed] = useState<string>(appConfig.oracleFeedAddress ?? "0x0000000000000000000000000000000000000000");
  const [resolutionTimeInput, setResolutionTimeInput] = useState(() => {
    const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000);
    return tomorrow.toISOString().slice(0, 16);
  });
  const [createLiquidity, setCreateLiquidity] = useState("1000");
  const [tradeAmount, setTradeAmount] = useState("250");
  const [minOut, setMinOut] = useState("0");
  const [tradeOutcome, setTradeOutcome] = useState<1 | 2>(1);
  const [lpAmount, setLpAmount] = useState("500");
  const [mintAmount, setMintAmount] = useState("500");
  const [removeShares, setRemoveShares] = useState("100");
  const [redeemMarketId, setRedeemMarketId] = useState<number>(appConfig.defaultMarketId);

  const { address, isConnected, chainId } = useAccount();
  const { connect, connectors, isPending: isConnecting } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();
  const { writeContractAsync, isPending: isWriting } = useWriteContract();

  const isOnTargetChain = chainId === sepolia.id || chainId === appConfig.chainId || chainId === undefined;

  const marketRead = useReadContract({
    address: appConfig.predictionMarketAddress,
    abi: predictionMarketAbi,
    functionName: "getMarket",
    args: [BigInt(marketId)],
    query: { enabled: Boolean(appConfig.predictionMarketAddress) && marketId > 0 },
  });

  const marketCountRead = useReadContract({
    address: appConfig.predictionMarketAddress,
    abi: predictionMarketAbi,
    functionName: "marketCount",
    query: { enabled: Boolean(appConfig.predictionMarketAddress) },
  });

  const yesPriceRead = useReadContract({
    address: appConfig.predictionMarketAddress,
    abi: predictionMarketAbi,
    functionName: "getPrice",
    args: [BigInt(marketId), 1],
    query: { enabled: Boolean(appConfig.predictionMarketAddress) && marketId > 0 },
  });

  const noPriceRead = useReadContract({
    address: appConfig.predictionMarketAddress,
    abi: predictionMarketAbi,
    functionName: "getPrice",
    args: [BigInt(marketId), 2],
    query: { enabled: Boolean(appConfig.predictionMarketAddress) && marketId > 0 },
  });

  const market = marketRead.data as MarketTuple | undefined;
  const marketQuestion = market?.[1] ?? "No market loaded yet.";
  const yesPrice = yesPriceRead.data ? formatUnits(yesPriceRead.data as bigint, 18) : "—";
  const noPrice = noPriceRead.data ? formatUnits(noPriceRead.data as bigint, 18) : "—";

  const totalCollateral = market?.[7];
  const yesReserve = market?.[8];
  const noReserve = market?.[9];
  const feesAccrued = market?.[10];
  const resolved = market?.[6];
  const winningOutcome = market?.[5];
  const lpShares = useReadContract({
    address: appConfig.predictionMarketAddress,
    abi: predictionMarketAbi,
    functionName: "getLpShares",
    args: [BigInt(marketId), address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: Boolean(appConfig.predictionMarketAddress && address && marketId > 0) },
  }).data as bigint | undefined;

  const subgraphRead = useQuery({
    queryKey: ["subgraph-market", appConfig.subgraphUrl, marketId],
    enabled: marketId > 0,
    queryFn: () =>
      fetchSubgraph<SubgraphPayload>(
        `
          query MarketSnapshot($id: ID!) {
            market(id: $id) {
              id
              question
              creator
              oracleFeed
              resolutionTime
              resolved
              winningOutcome
              totalCollateral
              yesReserve
              noReserve
              feesAccrued
              createdAt
            }
            markets(first: 5, orderBy: createdAt, orderDirection: desc) {
              id
              question
              resolved
              winningOutcome
              createdAt
            }
          }
        `,
        { id: String(marketId) },
      ),
    staleTime: 10_000,
  });

  const subgraphMarket = subgraphRead.data?.market;
  const recentSubgraphMarkets = subgraphRead.data?.markets ?? [];
  const subgraphStatus = subgraphRead.isLoading
    ? "Loading subgraph snapshot..."
    : subgraphRead.isError
      ? `Subgraph error: ${(subgraphRead.error as Error).message}`
      : subgraphMarket
        ? `Indexed market ${subgraphMarket.id}`
        : "Market not indexed yet.";

  const totalLpShares = useReadContract({
    address: appConfig.predictionMarketAddress,
    abi: predictionMarketAbi,
    functionName: "getTotalLpShares",
    args: [BigInt(marketId)],
    query: { enabled: Boolean(appConfig.predictionMarketAddress) && marketId > 0 },
  }).data as bigint | undefined;

  const usdcApproval = useReadContract({
    address: appConfig.usdcAddress,
    abi: erc20Abi,
    functionName: "allowance",
    args: [address ?? "0x0000000000000000000000000000000000000000", appConfig.predictionMarketAddress ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: Boolean(appConfig.usdcAddress && appConfig.predictionMarketAddress && address) },
  }).data as bigint | undefined;

  const yesTokenId = useMemo(() => BigInt(marketId) * 2n, [marketId]);
  const noTokenId = useMemo(() => BigInt(marketId) * 2n + 1n, [marketId]);

  const yesBalance = useReadContract({
    address: appConfig.outcomeTokenAddress,
    abi: erc1155Abi,
    functionName: "balanceOf",
    args: [address ?? "0x0000000000000000000000000000000000000000", yesTokenId],
    query: { enabled: Boolean(appConfig.outcomeTokenAddress && address) },
  }).data as bigint | undefined;

  const noBalance = useReadContract({
    address: appConfig.outcomeTokenAddress,
    abi: erc1155Abi,
    functionName: "balanceOf",
    args: [address ?? "0x0000000000000000000000000000000000000000", noTokenId],
    query: { enabled: Boolean(appConfig.outcomeTokenAddress && address) },
  }).data as bigint | undefined;

  async function approveUsdc(amount: string) {
    if (!appConfig.usdcAddress || !appConfig.predictionMarketAddress) return;
    await writeContractAsync({
      address: appConfig.usdcAddress,
      abi: erc20Abi,
      functionName: "approve",
      args: [appConfig.predictionMarketAddress, parseUnits(amount || "0", 18)],
    });
  }

  async function approveOutcomes() {
    if (!appConfig.outcomeTokenAddress || !appConfig.predictionMarketAddress) return;
    await writeContractAsync({
      address: appConfig.outcomeTokenAddress,
      abi: erc1155Abi,
      functionName: "setApprovalForAll",
      args: [appConfig.predictionMarketAddress, true],
    });
  }

  async function createMarketTx() {
    if (!appConfig.predictionMarketAddress) return;
    await writeContractAsync({
      address: appConfig.predictionMarketAddress,
      abi: predictionMarketAbi,
      functionName: "createMarket",
      args: [question, oracleFeed as `0x${string}`, toUnixSeconds(resolutionTimeInput), parseUnits(createLiquidity || "0", 18)],
    });
  }

  async function tradeTx(kind: "buy" | "sell") {
    if (!appConfig.predictionMarketAddress) return;
    const args = [BigInt(marketId), tradeOutcome, parseUnits(tradeAmount || "0", 18), parseUnits(minOut || "0", 18)] as const;
    await writeContractAsync({
      address: appConfig.predictionMarketAddress,
      abi: predictionMarketAbi,
      functionName: kind,
      args: kind === "buy" ? args : [BigInt(marketId), tradeOutcome, parseUnits(tradeAmount || "0", 18), parseUnits(minOut || "0", 18)],
    });
  }

  async function mintTx() {
    if (!appConfig.predictionMarketAddress) return;
    await writeContractAsync({
      address: appConfig.predictionMarketAddress,
      abi: predictionMarketAbi,
      functionName: "mintOutcomeTokens",
      args: [BigInt(marketId), parseUnits(mintAmount || "0", 18)],
    });
  }

  async function liquidityTx(kind: "addLiquidity" | "removeLiquidity") {
    if (!appConfig.predictionMarketAddress) return;
    const amount = parseUnits(kind === "addLiquidity" ? lpAmount || "0" : removeShares || "0", 18);
    await writeContractAsync({
      address: appConfig.predictionMarketAddress,
      abi: predictionMarketAbi,
      functionName: kind,
      args: kind === "addLiquidity"
        ? [BigInt(marketId), amount, 0n]
        : [BigInt(marketId), amount, 0n],
    });
  }

  async function resolveTx() {
    if (!appConfig.predictionMarketAddress) return;
    await writeContractAsync({
      address: appConfig.predictionMarketAddress,
      abi: predictionMarketAbi,
      functionName: "resolveMarket",
      args: [BigInt(marketId)],
    });
  }

  async function redeemTx() {
    if (!appConfig.predictionMarketAddress) return;
    await writeContractAsync({
      address: appConfig.predictionMarketAddress,
      abi: predictionMarketAbi,
      functionName: "redeemWinningTokens",
      args: [BigInt(redeemMarketId)],
    });
  }

  const marketAge = market ? Number(market[4]) : undefined;
  const marketStatus = market
    ? resolved
      ? `Resolved ${winningOutcome === 1n ? "YES" : "NO"}`
      : `Live until ${new Date((marketAge ?? 0) * 1000).toLocaleString()}`
    : "Load a market to inspect it.";

  return (
    <div className="app-shell">
      <div className="ambient ambient-left" />
      <div className="ambient ambient-right" />

      <main className="layout">
        <section className="hero">
          <div>
            <div className="eyebrow">Prediction Market Desk</div>
            <h1>Trade yes/no markets with a dashboard that feels like a terminal for signal.</h1>
            <p>
              React + Wagmi frontend for the Foundry prediction market stack. Load a market, trade
              outcome tokens, provision liquidity, resolve, and redeem from one surface.
            </p>
          </div>

          <div className="connect-panel">
            <div className="connect-row">
              <span className={`status-pill ${isConnected ? "ready" : "idle"}`}>{isConnected ? "Wallet connected" : "Wallet disconnected"}</span>
              <span className={`status-pill ${isOnTargetChain ? "ready" : "warn"}`}>{isOnTargetChain ? `Chain ${chainId ?? appConfig.chainId}` : "Wrong chain"}</span>
            </div>

            {isConnected ? (
              <>
                <div className="wallet-address">{shortAddress(address)}</div>
                <div className="connect-actions">
                  {!isOnTargetChain && (
                    <button className="button secondary" onClick={() => switchChain?.({ chainId: appConfig.chainId })}>
                      Switch chain
                    </button>
                  )}
                  <button className="button secondary" onClick={() => disconnect()}>
                    Disconnect
                  </button>
                </div>
              </>
            ) : (
              <div className="connect-actions stack">
                {connectors.map((connector) => (
                  <button
                    key={connector.uid}
                    className="button secondary"
                    onClick={() => connect({ connector })}
                    disabled={isConnecting}
                  >
                    Connect {connector.name}
                  </button>
                ))}
              </div>
            )}
          </div>
        </section>

        <section className="stats-grid">
          <StatCard label="Markets" value={marketCountRead.data ? formatAmount(marketCountRead.data as bigint, 0) : "—"} hint="Current on-chain market count" />
          <StatCard label="YES price" value={yesPrice === "—" ? "—" : `${Number(yesPrice).toFixed(4)}`} hint="1e18 fixed-point quote" />
          <StatCard label="NO price" value={noPrice === "—" ? "—" : `${Number(noPrice).toFixed(4)}`} hint="1e18 fixed-point quote" />
          <StatCard label="LP shares" value={formatAmount(lpShares, 18)} hint="Your position in the selected market" />
        </section>

        <section className="content-grid">
          <div className="stacked">
            <article className="panel">
              <div className="panel-head">
                <div>
                  <div className="panel-kicker">Market explorer</div>
                  <h2>Load a market</h2>
                </div>
                <div className="inline-fields">
                  <Field label="Market ID">
                    <input type="number" min="1" value={marketId} onChange={(event) => setMarketId(Number(event.target.value))} />
                  </Field>
                </div>
              </div>

              {!hasCoreContracts ? (
                <div className="notice">Set `VITE_PREDICTION_MARKET_ADDRESS`, `VITE_OUTCOME_TOKEN_ADDRESS`, and `VITE_USDC_ADDRESS` in `.env` to enable live transactions.</div>
              ) : null}

              <div className="market-card">
                <div className="market-title">{marketQuestion}</div>
                <div className="market-meta">{marketStatus}</div>
                <div className="market-grid">
                  <div>
                    <span>Collateral</span>
                    <strong>{formatAmount(totalCollateral)}</strong>
                  </div>
                  <div>
                    <span>YES reserve</span>
                    <strong>{formatAmount(yesReserve)}</strong>
                  </div>
                  <div>
                    <span>NO reserve</span>
                    <strong>{formatAmount(noReserve)}</strong>
                  </div>
                  <div>
                    <span>Fees accrued</span>
                    <strong>{formatAmount(feesAccrued)}</strong>
                  </div>
                </div>
                <div className="token-strip">
                  <span>YES token #{yesTokenId.toString()}</span>
                  <span>Balance {formatAmount(yesBalance)}</span>
                  <span>NO token #{noTokenId.toString()}</span>
                  <span>Balance {formatAmount(noBalance)}</span>
                </div>
              </div>
            </article>

            <article className="panel">
              <div className="panel-head">
                <div>
                  <div className="panel-kicker">Create market</div>
                  <h2>Deploy a new market</h2>
                </div>
                <button className="button" onClick={createMarketTx} disabled={isWriting || !appConfig.predictionMarketAddress}>
                  Create
                </button>
              </div>

              <div className="form-grid two-up">
                <Field label="Question">
                  <input value={question} onChange={(event) => setQuestion(event.target.value)} placeholder="Will ETH finish above $4k?" />
                </Field>
                <Field label="Oracle feed">
                  <input value={oracleFeed} onChange={(event) => setOracleFeed(event.target.value)} placeholder="0x..." />
                </Field>
                <Field label="Resolution time">
                  <input type="datetime-local" value={resolutionTimeInput} onChange={(event) => setResolutionTimeInput(event.target.value)} />
                </Field>
                <Field label="Initial liquidity">
                  <input value={createLiquidity} onChange={(event) => setCreateLiquidity(event.target.value)} inputMode="decimal" />
                </Field>
              </div>
            </article>
          </div>

          <div className="stacked">
            <article className="panel">
              <div className="panel-head">
                <div>
                  <div className="panel-kicker">Trade desk</div>
                  <h2>Buy or sell</h2>
                </div>
                <div className="button-row">
                  <button className="button secondary" onClick={() => approveUsdc(tradeAmount)} disabled={isWriting || !appConfig.usdcAddress || !appConfig.predictionMarketAddress}>
                    Approve USDC
                  </button>
                  <button className="button" onClick={() => tradeTx("buy")} disabled={isWriting || !appConfig.predictionMarketAddress}>
                    Buy
                  </button>
                </div>
              </div>

              <div className="form-grid two-up">
                <Field label="Outcome">
                  <select value={tradeOutcome} onChange={(event) => setTradeOutcome(Number(event.target.value) as 1 | 2)}>
                    <option value={1}>YES</option>
                    <option value={2}>NO</option>
                  </select>
                </Field>
                <Field label="Amount">
                  <input value={tradeAmount} onChange={(event) => setTradeAmount(event.target.value)} inputMode="decimal" />
                </Field>
                <Field label="Min out">
                  <input value={minOut} onChange={(event) => setMinOut(event.target.value)} inputMode="decimal" />
                </Field>
                <Field label="Selected market">
                  <input value={marketId} readOnly />
                </Field>
              </div>

              <div className="button-row spaced">
                <button className="button secondary" onClick={() => approveOutcomes()} disabled={isWriting || !appConfig.outcomeTokenAddress || !appConfig.predictionMarketAddress}>
                  Approve outcome token burns
                </button>
                <button className="button secondary" onClick={() => tradeTx("sell")} disabled={isWriting || !appConfig.predictionMarketAddress}>
                  Sell
                </button>
              </div>
            </article>

            <article className="panel">
              <div className="panel-head">
                <div>
                  <div className="panel-kicker">Liquidity + minting</div>
                  <h2>Shape the market</h2>
                </div>
              </div>

              <div className="form-grid two-up">
                <Field label="Mint collateral">
                  <input value={mintAmount} onChange={(event) => setMintAmount(event.target.value)} inputMode="decimal" />
                </Field>
                <Field label="Add liquidity">
                  <input value={lpAmount} onChange={(event) => setLpAmount(event.target.value)} inputMode="decimal" />
                </Field>
                <Field label="Remove shares">
                  <input value={removeShares} onChange={(event) => setRemoveShares(event.target.value)} inputMode="decimal" />
                </Field>
                <Field label="Current approval">
                  <input value={usdcApproval ? formatAmount(usdcApproval) : "—"} readOnly />
                </Field>
              </div>

              <div className="button-row spaced wrap">
                <button className="button secondary" onClick={() => approveUsdc(mintAmount)} disabled={isWriting || !appConfig.usdcAddress || !appConfig.predictionMarketAddress}>
                  Approve USDC
                </button>
                <button className="button" onClick={mintTx} disabled={isWriting || !appConfig.predictionMarketAddress}>
                  Mint YES/NO
                </button>
                <button className="button secondary" onClick={() => liquidityTx("addLiquidity")} disabled={isWriting || !appConfig.predictionMarketAddress}>
                  Add liquidity
                </button>
                <button className="button secondary" onClick={() => liquidityTx("removeLiquidity")} disabled={isWriting || !appConfig.predictionMarketAddress}>
                  Remove liquidity
                </button>
              </div>
            </article>
          </div>

          <div className="stacked">
            <article className="panel">
              <div className="panel-head">
                <div>
                  <div className="panel-kicker">Resolution</div>
                  <h2>Settle the market</h2>
                </div>
                <button className="button secondary" onClick={resolveTx} disabled={isWriting || !appConfig.predictionMarketAddress}>
                  Resolve
                </button>
              </div>
              <p className="panel-copy">
                Resolution uses the oracle feed stored in the market. Once resolved, the winning side can be redeemed for collateral.
              </p>
            </article>

            <article className="panel">
              <div className="panel-head">
                <div>
                  <div className="panel-kicker">Redemption</div>
                  <h2>Claim winnings</h2>
                </div>
                <button className="button" onClick={redeemTx} disabled={isWriting || !appConfig.predictionMarketAddress}>
                  Redeem
                </button>
              </div>
              <div className="form-grid single">
                <Field label="Market ID">
                  <input value={redeemMarketId} onChange={(event) => setRedeemMarketId(Number(event.target.value))} />
                </Field>
              </div>
              <p className="panel-copy">
                Redeem burns the winning ERC-1155 balance from the connected wallet and returns the proportional USDC payout.
              </p>
            </article>

            <article className="panel compact-panel">
              <div className="panel-head">
                <div>
                  <div className="panel-kicker">Status</div>
                  <h2>Live deployment notes</h2>
                </div>
              </div>
              <ul className="bullet-list">
                <li>Set the contract addresses in <code>.env</code> to activate live reads and writes.</li>
                <li>Use the local Anvil chain for fast testing, or switch the config to Sepolia.</li>
                <li>The UI is intentionally built as a single-page desk so the transaction flow stays visible.</li>
              </ul>
            </article>

            <article className="panel compact-panel">
              <div className="panel-head">
                <div>
                  <div className="panel-kicker">Subgraph</div>
                  <h2>Indexed snapshot</h2>
                </div>
              </div>

              <div className="notice">{subgraphStatus}</div>

              {subgraphMarket ? (
                <div className="market-card">
                  <div className="market-title">{subgraphMarket.question ?? "Untitled market"}</div>
                  <div className="market-meta">Created #{subgraphMarket.id} at {subgraphMarket.createdAt ?? "unknown"}</div>
                  <div className="market-grid">
                    <div>
                      <span>Collateral</span>
                      <strong>{formatAmount(subgraphMarket.totalCollateral ? BigInt(subgraphMarket.totalCollateral) : undefined)}</strong>
                    </div>
                    <div>
                      <span>YES reserve</span>
                      <strong>{formatAmount(subgraphMarket.yesReserve ? BigInt(subgraphMarket.yesReserve) : undefined)}</strong>
                    </div>
                    <div>
                      <span>NO reserve</span>
                      <strong>{formatAmount(subgraphMarket.noReserve ? BigInt(subgraphMarket.noReserve) : undefined)}</strong>
                    </div>
                    <div>
                      <span>Resolved</span>
                      <strong>{subgraphMarket.resolved ? `YES ${subgraphMarket.winningOutcome ?? ""}` : "No"}</strong>
                    </div>
                  </div>
                </div>
              ) : null}

              {recentSubgraphMarkets.length ? (
                <ul className="bullet-list">
                  {recentSubgraphMarkets.map((entry) => (
                    <li key={entry.id}>
                      #{entry.id} {entry.question ?? "Untitled"} {entry.resolved ? `(resolved ${entry.winningOutcome ?? "?"})` : "(live)"}
                    </li>
                  ))}
                </ul>
              ) : null}
            </article>
          </div>
        </section>
      </main>
    </div>
  );
}
