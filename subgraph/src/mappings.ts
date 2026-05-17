import { BigInt } from "@graphprotocol/graph-ts";
import { PredictionMarket as PredictionMarketContract } from "../generated/PredictionMarket/PredictionMarket";
import { MarketCreated, MarketResolved } from "../generated/PredictionMarket/PredictionMarket";
import { Market } from "../generated/schema";

export function handleMarketCreated(event: MarketCreated): void {
  let id = event.params.marketId.toString();
  let market = new Market(id);

  // Basic data from event
  market.question = event.params.question;
  market.creator = event.params.creator;
  market.oracleFeed = event.params.oracleFeed;
  market.createdAt = event.block.timestamp;

  // Try to fetch on-chain full market struct
  let contract = PredictionMarketContract.bind(event.address);
  let result = contract.getMarket(event.params.marketId);
  market.resolutionTime = result.resolutionTime;
  market.resolved = result.resolved;
  market.winningOutcome = result.winningOutcome;
  market.totalCollateral = result.totalCollateral;
  market.yesReserve = result.yesReserve;
  market.noReserve = result.noReserve;
  market.feesAccrued = result.feesAccrued;

  market.save();
}

export function handleMarketResolved(event: MarketResolved): void {
  let id = event.params.marketId.toString();
  let market = Market.load(id);
  if (market == null) {
    market = new Market(id);
  }
  market.resolved = true;
  market.winningOutcome = event.params.winningOutcome as i32;
  market.save();
}
