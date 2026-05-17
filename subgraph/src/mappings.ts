import { BigInt, Bytes, Address } from "@graphprotocol/graph-ts";
import { PredictionMarket as PredictionMarketContract } from "../generated/PredictionMarket/PredictionMarket";
import {
  MarketCreated,
  MarketResolved,
  TokensPurchased,
  TokensSold,
  LiquidityAdded,
  LiquidityRemoved,
  WinningsRedeemed,
  CollateralMinted
} from "../generated/PredictionMarket/PredictionMarket";
import { Market, Trade, LiquidityEvent, User, DailyVolume } from "../generated/schema";

// Constants
const FEE_BPS = 30;
const BPS = 10000;

// Helper: Get or create User entity
function getOrCreateUser(address: Bytes): User {
  let user = User.load(address.toHex());
  if (user == null) {
    user = new User(address.toHex());
    user.firstActivity = BigInt.zero();
    user.lastActivity = BigInt.zero();
    user.totalTrades = BigInt.zero();
    user.totalVolume = BigInt.zero();
    user.totalFeesPaid = BigInt.zero();
    user.marketsTraded = [];
    user.totalLiquidityAdded = BigInt.zero();
    user.totalLiquidityRemoved = BigInt.zero();
    user.currentLpPositions = BigInt.zero();
    user.totalRedeemed = BigInt.zero();
  }
  return user;
}

// Helper: Update User activity timestamp
function updateUserActivity(user: User, timestamp: BigInt): void {
  if (user.firstActivity.equals(BigInt.zero())) {
    user.firstActivity = timestamp;
  }
  user.lastActivity = timestamp;
}

// Helper: Get or create DailyVolume entity
function getOrCreateDailyVolume(marketId: string, timestamp: BigInt): DailyVolume {
  let dayTimestamp = timestamp.div(BigInt.fromI32(86400)).times(BigInt.fromI32(86400));
  let id = marketId + "-" + dayTimestamp.toString();
  let volume = DailyVolume.load(id);
  if (volume == null) {
    volume = new DailyVolume(id);
    volume.market = marketId;
    volume.date = dayTimestamp;
    volume.volumeUSD = BigInt.zero();
    volume.trades = BigInt.zero();
    volume.fees = BigInt.zero();
    volume.addLiquidity = BigInt.zero();
    volume.removeLiquidity = BigInt.zero();
  }
  return volume;
}

// ==================== Market Lifecycle Handlers ====================

export function handleMarketCreated(event: MarketCreated): void {
  let id = event.params.marketId.toString();
  let market = new Market(id);

  market.question = event.params.question;
  market.creator = event.params.creator;
  market.oracleFeed = event.params.oracleFeed;
  market.createdAt = event.block.timestamp;
  market.resolutionTime = BigInt.zero();
  market.resolved = false;
  market.winningOutcome = 0;
  market.totalCollateral = BigInt.zero();
  market.yesReserve = BigInt.zero();
  market.noReserve = BigInt.zero();
  market.feesAccrued = BigInt.zero();
  market.tradeCount = BigInt.zero();
  market.volume = BigInt.zero();
  market.liquidityProviderCount = BigInt.zero();

  market.save();
}

export function handleMarketResolved(event: MarketResolved): void {
  let id = event.params.marketId.toString();
  let market = Market.load(id);
  if (market == null) return;

  market.resolved = true;
  market.winningOutcome = event.params.winningOutcome as i32;

  // Sync final state from contract
  let contract = PredictionMarketContract.bind(event.address);
  let result = contract.getMarket(event.params.marketId);
  market.yesReserve = result.yesReserve;
  market.noReserve = result.noReserve;
  market.totalCollateral = result.totalCollateral;

  market.save();
}

// ==================== Trading Handlers ====================

export function handleTokensPurchased(event: TokensPurchased): void {
  let marketId = event.params.marketId.toString();
  let market = Market.load(marketId);
  if (market == null) return;

  let tradeId = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  let trade = new Trade(tradeId);
  trade.market = marketId;
  trade.trader = event.params.buyer;
  trade.tradeType = "BUY";
  trade.outcome = event.params.outcome as i32;
  trade.amountIn = event.params.amountIn;
  trade.amountOut = event.params.amountOut;
  trade.fee = event.params.amountIn.times(BigInt.fromI32(FEE_BPS)).div(BigInt.fromI32(BPS));
  trade.price = trade.amountOut.times(BigInt.fromI32(10).pow(18)).div(trade.amountIn);
  trade.blockNumber = event.block.number;
  trade.timestamp = event.block.timestamp;
  trade.txHash = event.transaction.hash;
  trade.save();

  // Update Market stats
  market.tradeCount = market.tradeCount.plus(BigInt.fromI32(1));
  market.volume = market.volume.plus(event.params.amountIn);
  market.feesAccrued = market.feesAccrued.plus(trade.fee);
  market.save();

  // Update User
  let user = getOrCreateUser(event.params.buyer);
  updateUserActivity(user, event.block.timestamp);
  user.totalTrades = user.totalTrades.plus(BigInt.fromI32(1));
  user.totalVolume = user.totalVolume.plus(event.params.amountIn);
  user.totalFeesPaid = user.totalFeesPaid.plus(trade.fee);
  user.save();

  // Update DailyVolume
  let daily = getOrCreateDailyVolume(marketId, event.block.timestamp);
  daily.volumeUSD = daily.volumeUSD.plus(event.params.amountIn);
  daily.trades = daily.trades.plus(BigInt.fromI32(1));
  daily.fees = daily.fees.plus(trade.fee);
  daily.save();
}

export function handleTokensSold(event: TokensSold): void {
  let marketId = event.params.marketId.toString();
  let market = Market.load(marketId);
  if (market == null) return;

  let tradeId = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  let trade = new Trade(tradeId);
  trade.market = marketId;
  trade.trader = event.params.seller;
  trade.tradeType = "SELL";
  trade.outcome = event.params.outcome as i32;
  trade.amountIn = event.params.amountIn;
  trade.amountOut = event.params.amountOut;
  // Fee on sell is taken from output (USDC)
  let grossOut = event.params.amountOut.times(BigInt.fromI32(BPS)).div(BigInt.fromI32(BPS - FEE_BPS));
  trade.fee = grossOut.minus(event.params.amountOut);
  trade.price = trade.amountOut.times(BigInt.fromI32(10).pow(18)).div(trade.amountIn);
  trade.blockNumber = event.block.number;
  trade.timestamp = event.block.timestamp;
  trade.txHash = event.transaction.hash;
  trade.save();

  // Update Market stats
  market.tradeCount = market.tradeCount.plus(BigInt.fromI32(1));
  market.volume = market.volume.plus(event.params.amountOut);
  market.feesAccrued = market.feesAccrued.plus(trade.fee);
  market.save();

  // Update User
  let user = getOrCreateUser(event.params.seller);
  updateUserActivity(user, event.block.timestamp);
  user.totalTrades = user.totalTrades.plus(BigInt.fromI32(1));
  user.totalVolume = user.totalVolume.plus(event.params.amountOut);
  user.totalFeesPaid = user.totalFeesPaid.plus(trade.fee);
  user.save();

  // Update DailyVolume
  let daily = getOrCreateDailyVolume(marketId, event.block.timestamp);
  daily.volumeUSD = daily.volumeUSD.plus(event.params.amountOut);
  daily.trades = daily.trades.plus(BigInt.fromI32(1));
  daily.fees = daily.fees.plus(trade.fee);
  daily.save();
}

// ==================== Liquidity Handlers ====================

export function handleLiquidityAdded(event: LiquidityAdded): void {
  let marketId = event.params.marketId.toString();
  let market = Market.load(marketId);
  if (market == null) return;

  let eventId = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  let liquidityEvent = new LiquidityEvent(eventId);
  liquidityEvent.market = marketId;
  liquidityEvent.provider = event.params.provider;
  liquidityEvent.eventType = "ADD";
  liquidityEvent.usdcAmount = event.params.usdcAmount;
  liquidityEvent.yesReserveChange = event.params.yesAdded;
  liquidityEvent.noReserveChange = event.params.noAdded;
  liquidityEvent.lpShares = BigInt.zero(); // Would need to fetch from contract
  liquidityEvent.blockNumber = event.block.number;
  liquidityEvent.timestamp = event.block.timestamp;
  liquidityEvent.txHash = event.transaction.hash;
  liquidityEvent.save();

  // Update Market reserves
  market.yesReserve = market.yesReserve.plus(event.params.yesAdded);
  market.noReserve = market.noReserve.plus(event.params.noAdded);
  market.totalCollateral = market.totalCollateral.plus(event.params.usdcAmount);
  market.save();

  // Update User
  let user = getOrCreateUser(event.params.provider);
  updateUserActivity(user, event.block.timestamp);
  user.totalLiquidityAdded = user.totalLiquidityAdded.plus(event.params.usdcAmount);
  user.save();

  // Update DailyVolume
  let daily = getOrCreateDailyVolume(marketId, event.block.timestamp);
  daily.addLiquidity = daily.addLiquidity.plus(event.params.usdcAmount);
  daily.save();
}

export function handleLiquidityRemoved(event: LiquidityRemoved): void {
  let marketId = event.params.marketId.toString();
  let market = Market.load(marketId);
  if (market == null) return;

  let eventId = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  let liquidityEvent = new LiquidityEvent(eventId);
  liquidityEvent.market = marketId;
  liquidityEvent.provider = event.params.provider;
  liquidityEvent.eventType = "REMOVE";
  liquidityEvent.usdcAmount = event.params.usdcReturned;
  liquidityEvent.lpShares = event.params.lpShares;
  liquidityEvent.yesReserveChange = BigInt.zero();
  liquidityEvent.noReserveChange = BigInt.zero();
  liquidityEvent.blockNumber = event.block.number;
  liquidityEvent.timestamp = event.block.timestamp;
  liquidityEvent.txHash = event.transaction.hash;
  liquidityEvent.save();

  // Update Market (fetch fresh state from contract)
  let contract = PredictionMarketContract.bind(event.address);
  let result = contract.getMarket(event.params.marketId);
  market.yesReserve = result.yesReserve;
  market.noReserve = result.noReserve;
  market.totalCollateral = result.totalCollateral;
  market.save();

  // Update User
  let user = getOrCreateUser(event.params.provider);
  updateUserActivity(user, event.block.timestamp);
  user.totalLiquidityRemoved = user.totalLiquidityRemoved.plus(event.params.usdcReturned);
  user.save();

  // Update DailyVolume
  let daily = getOrCreateDailyVolume(marketId, event.block.timestamp);
  daily.removeLiquidity = daily.removeLiquidity.plus(event.params.usdcReturned);
  daily.save();
}

// ==================== Redemption & Minting Handlers ====================

export function handleWinningsRedeemed(event: WinningsRedeemed): void {
  let user = getOrCreateUser(event.params.redeemer);
  updateUserActivity(user, event.block.timestamp);
  user.totalRedeemed = user.totalRedeemed.plus(event.params.amount);
  user.save();

  // Update Market totalCollateral
  let marketId = event.params.marketId.toString();
  let market = Market.load(marketId);
  if (market != null) {
    market.totalCollateral = market.totalCollateral.minus(event.params.amount);
    market.save();
  }
}

export function handleCollateralMinted(event: CollateralMinted): void {
  // Update Market collateral
  let marketId = event.params.marketId.toString();
  let market = Market.load(marketId);
  if (market == null) return;

  market.totalCollateral = market.totalCollateral.plus(event.params.amount);
  market.save();

  // Update User
  let user = getOrCreateUser(event.params.user);
  updateUserActivity(user, event.block.timestamp);
  user.save();
}
