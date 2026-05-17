// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPredictionMarket
/// @notice Interface for the core binary prediction market contract
/// @dev Defines the Market struct, all events, and all external function signatures
interface IPredictionMarket {
    // Structs

    /// @notice Full state of a single prediction market
    /// @param id              Unique market identifier
    /// @param question        Human-readable question this market resolves
    /// @param collateralToken USDC address used as collateral
    /// @param oracleFeed      Chainlink feed address used for resolution
    /// @param resolutionTime  Earliest timestamp at which oracle can resolve
    /// @param winningOutcome  0 = unresolved, 1 = YES wins, 2 = NO wins
    /// @param resolved        True once the market has been resolved
    /// @param totalCollateral Total USDC locked in this market
    /// @param yesReserve      AMM reserve for YES tokens
    /// @param noReserve       AMM reserve for NO tokens
    /// @param feesAccrued     Total fees collected in USDC
    /// @param creator         Address that created this market
    struct Market {
        uint256 id;
        string question;
        address collateralToken;
        address oracleFeed;
        uint256 resolutionTime;
        uint8 winningOutcome;
        bool resolved;
        uint256 totalCollateral;
        uint256 yesReserve;
        uint256 noReserve;
        uint256 feesAccrued;
        address creator;
    }
    // Events

    /// @notice Emitted when a new prediction market is created
    /// @param marketId  Unique ID of the new market
    /// @param question  The market question
    /// @param creator   Address that created the market
    /// @param oracleFeed Chainlink feed that will resolve the market
    event MarketCreated(uint256 indexed marketId, string question, address indexed creator, address oracleFeed);

    /// @notice Emitted when liquidity is added to a market's AMM
    /// @param marketId  Target market
    /// @param provider  Liquidity provider address
    /// @param usdcAmount USDC deposited
    /// @param yesAdded  YES tokens added to reserve
    /// @param noAdded   NO tokens added to reserve
    event LiquidityAdded(
        uint256 indexed marketId, address indexed provider, uint256 usdcAmount, uint256 yesAdded, uint256 noAdded
    );

    /// @notice Emitted when liquidity is removed from a market's AMM
    /// @param marketId  Target market
    /// @param provider  Liquidity provider address
    /// @param lpShares  LP shares burned
    /// @param usdcReturned USDC returned to provider
    event LiquidityRemoved(uint256 indexed marketId, address indexed provider, uint256 lpShares, uint256 usdcReturned);

    /// @notice Emitted when outcome tokens are purchased via the AMM
    /// @param marketId  Target market
    /// @param buyer     Buyer address
    /// @param outcome   1 = YES, 2 = NO
    /// @param amountIn  USDC spent
    /// @param amountOut Outcome tokens received
    event TokensPurchased(
        uint256 indexed marketId, address indexed buyer, uint8 outcome, uint256 amountIn, uint256 amountOut
    );

    /// @notice Emitted when outcome tokens are sold back via the AMM
    /// @param marketId  Target market
    /// @param seller    Seller address
    /// @param outcome   1 = YES, 2 = NO
    /// @param amountIn  Outcome tokens sold
    /// @param amountOut USDC received (after fee)
    event TokensSold(
        uint256 indexed marketId, address indexed seller, uint8 outcome, uint256 amountIn, uint256 amountOut
    );

    /// @notice Emitted when a market is resolved via the oracle
    /// @param marketId      Target market
    /// @param winningOutcome 1 = YES, 2 = NO
    event MarketResolved(uint256 indexed marketId, uint8 winningOutcome);

    /// @notice Emitted when a user redeems winning tokens for USDC
    /// @param marketId Target market
    /// @param redeemer Address redeeming tokens
    /// @param amount   USDC paid out
    event WinningsRedeemed(uint256 indexed marketId, address indexed redeemer, uint256 amount);

    /// @notice Emitted when a user mints an equal set of YES+NO tokens
    /// @param marketId Target market
    /// @param user     Address receiving the tokens
    /// @param amount   Amount of each token minted
    event CollateralMinted(uint256 indexed marketId, address indexed user, uint256 amount);
    // Functions

    /// @notice Creates a new binary prediction market
    /// @param question        Human-readable question
    /// @param oracleFeed      Chainlink feed for resolution
    /// @param resolutionTime  Earliest resolution timestamp
    /// @param initialLiquidity USDC amount for initial AMM seeding
    /// @return marketId The newly created market's ID
    function createMarket(
        string calldata question,
        address oracleFeed,
        uint256 resolutionTime,
        uint256 initialLiquidity
    ) external returns (uint256 marketId);

    /// @notice Adds liquidity to a market's AMM
    /// @param marketId   Target market
    /// @param usdcAmount USDC to deposit
    /// @param minLpShares Minimum LP shares to receive (slippage guard)
    function addLiquidity(uint256 marketId, uint256 usdcAmount, uint256 minLpShares) external;

    /// @notice Removes liquidity from a market's AMM
    /// @param marketId Target market
    /// @param lpShares LP shares to burn
    /// @param minUsdc  Minimum USDC to receive (slippage guard)
    function removeLiquidity(uint256 marketId, uint256 lpShares, uint256 minUsdc) external;

    /// @notice Buys outcome tokens using USDC via the AMM
    /// @param marketId    Target market
    /// @param outcome     1 = YES, 2 = NO
    /// @param amountIn    USDC to spend
    /// @param minAmountOut Minimum outcome tokens to receive (slippage guard)
    /// @return amountOut  Outcome tokens received
    function buy(uint256 marketId, uint8 outcome, uint256 amountIn, uint256 minAmountOut)
        external
        returns (uint256 amountOut);

    /// @notice Sells outcome tokens for USDC via the AMM
    /// @param marketId     Target market
    /// @param outcome      1 = YES, 2 = NO
    /// @param tokenAmountIn Outcome tokens to sell
    /// @param minUsdcOut   Minimum USDC to receive (slippage guard)
    /// @return usdcOut     USDC received after fee
    function sell(uint256 marketId, uint8 outcome, uint256 tokenAmountIn, uint256 minUsdcOut)
        external
        returns (uint256 usdcOut);

    /// @notice Mints an equal amount of YES and NO tokens against USDC collateral
    /// @param marketId Target market
    /// @param amount   USDC to lock (and amount of each token minted)
    function mintOutcomeTokens(uint256 marketId, uint256 amount) external;

    /// @notice Redeems winning outcome tokens for proportional USDC payout
    /// @param marketId Target (resolved) market
    function redeemWinningTokens(uint256 marketId) external;

    /// @notice Resolves a market using its Chainlink oracle feed
    /// @param marketId Target market
    function resolveMarket(uint256 marketId) external;

    /// @notice Returns the full state of a market
    /// @param marketId Target market
    /// @return The Market struct
    function getMarket(uint256 marketId) external view returns (Market memory);

    /// @notice Returns the AMM spot price of an outcome token
    /// @param marketId Target market
    /// @param outcome  1 = YES, 2 = NO
    /// @return price   Price in 1e18 fixed-point (0-1e18)
    function getPrice(uint256 marketId, uint8 outcome) external view returns (uint256 price);
}
