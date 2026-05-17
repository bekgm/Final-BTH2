// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UUPSUpgradeable} from
    "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from
    "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPredictionMarket} from "../interfaces/IPredictionMarket.sol";
import {IOracleAdapter} from "../interfaces/IOracleAdapter.sol";
import {AMM} from "./AMM.sol";
import {OutcomeToken} from "../tokens/OutcomeToken.sol";
import {FeeVault} from "../vault/FeeVault.sol";

/// @title PredictionMarket
/// @notice Core contract for creating and trading in binary prediction markets
/// @dev    Implements UUPS upgradeable proxy pattern. Storage layout is frozen —
///         new variables must only be added at the END of the storage block.
///         Uses CPMM (x*y=k) AMM with 0.3% fee routed to FeeVault (ERC-4626).
///         Oracle resolution uses Chainlink feeds via OracleAdapter.
/// @custom:security-contact security@predictionprotocol.xyz
contract PredictionMarket is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IPredictionMarket
{
    using SafeERC20 for IERC20;
    // Roles

    /// @notice Role that permits creating new markets (granted via governance)
    bytes32 public constant MARKET_CREATOR_ROLE = keccak256("MARKET_CREATOR_ROLE");

    /// @notice Role that permits pausing/unpausing the contract
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role that authorises UUPS upgrades
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    // Constants

    /// @notice Protocol fee in basis points (0.3%)
    uint256 public constant FEE_BPS = 30;

    /// @notice Basis-point denominator
    uint256 public constant BPS = 10_000;
    // Storage — DO NOT reorder; append-only for upgrade safety

    /// @dev Auto-incrementing market counter (starts at 1 after first create)
    uint256 internal _marketCount;

    /// @dev marketId → Market struct
    mapping(uint256 => Market) internal _markets;

    /// @dev marketId → provider → LP shares
    mapping(uint256 => mapping(address => uint256)) internal _lpShares;

    /// @dev marketId → total LP shares outstanding
    mapping(uint256 => uint256) internal _totalLpShares;

    /// @notice Address of the OutcomeToken (ERC-1155) contract
    address public outcomeToken;

    /// @notice Address of the FeeVault (ERC-4626) contract
    address public feeVault;

    /// @notice Address of the USDC ERC-20 token used as collateral
    address public usdc;

    /// @notice Address of the OracleAdapter contract
    address public oracleAdapter;
    // Custom errors

    error StalePrice(uint256 updatedAt, uint256 blockTimestamp);
    error InsufficientLiquidity(uint256 available, uint256 required);
    error MarketAlreadyResolved(uint256 marketId);
    error MarketNotResolved(uint256 marketId);
    error InvalidOutcome(uint8 outcome);
    error SlippageExceeded(uint256 expected, uint256 actual);
    error ZeroAmount();
    error Unauthorized(address caller, bytes32 role);
    error InvalidQuestion();
    error InvalidFeed();
    error InvalidResolutionTime();
    error ResolutionTooEarly(uint256 resolutionTime, uint256 blockTimestamp);
    // Initializer

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialises the PredictionMarket proxy
    /// @dev    Must be called exactly once via the proxy's initialize() call.
    ///         Grants all roles to _admin.
    /// @param _usdc          USDC token address
    /// @param _outcomeToken  OutcomeToken (ERC-1155) contract address
    /// @param _feeVault      FeeVault (ERC-4626) contract address
    /// @param _oracleAdapter OracleAdapter contract address
    /// @param _admin         Address receiving all privileged roles
    function initialize(
        address _usdc,
        address _outcomeToken,
        address _feeVault,
        address _oracleAdapter,
        address _admin
    ) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        usdc = _usdc;
        outcomeToken = _outcomeToken;
        feeVault = _feeVault;
        oracleAdapter = _oracleAdapter;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MARKET_CREATOR_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _grantRole(UPGRADER_ROLE, _admin);
    }
    // Pausable

    /// @notice Pauses all market operations
    /// @dev Only callable by PAUSER_ROLE
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpauses all market operations
    /// @dev Only callable by PAUSER_ROLE
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    // Market lifecycle

    /// @notice Creates a new binary prediction market seeded with initial USDC liquidity
    /// @dev    CEI pattern:
    ///           Checks: question non-empty, valid feed, future resolution, liquidity > 0
    ///           Effects: writes market struct, LP shares, reserves
    ///           Interactions: pull USDC, mint outcome tokens
    ///         Only callable by MARKET_CREATOR_ROLE.
    /// @param question        Human-readable question string
    /// @param oracleFeed      Chainlink feed address used for resolution
    /// @param resolutionTime  Earliest Unix timestamp at which oracle resolution is valid
    /// @param initialLiquidity USDC amount used to seed the AMM (split equally YES/NO)
    /// @return marketId The newly assigned market ID
    function createMarket(
        string calldata question,
        address oracleFeed,
        uint256 resolutionTime,
        uint256 initialLiquidity
    )
        external
        override
        onlyRole(MARKET_CREATOR_ROLE)
        nonReentrant
        whenNotPaused
        returns (uint256 marketId)
    {
        // --- Checks ---
        if (bytes(question).length == 0) revert InvalidQuestion();
        if (oracleFeed == address(0)) revert InvalidFeed();
        if (resolutionTime <= block.timestamp) revert InvalidResolutionTime();
        if (initialLiquidity == 0) revert ZeroAmount();

        // --- Effects ---
        marketId = ++_marketCount;

        uint256 halfLiquidity = initialLiquidity / 2;

        _markets[marketId] = Market({
            id: marketId,
            question: question,
            collateralToken: usdc,
            oracleFeed: oracleFeed,
            resolutionTime: resolutionTime,
            winningOutcome: 0,
            resolved: false,
            totalCollateral: initialLiquidity,
            yesReserve: halfLiquidity,
            noReserve: halfLiquidity,
            feesAccrued: 0,
            creator: msg.sender
        });

        uint256 lpShares = _sqrtAssembly(initialLiquidity);
        _lpShares[marketId][msg.sender] = lpShares;
        _totalLpShares[marketId] = lpShares;

        // --- Interactions ---
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), initialLiquidity);

        uint256 yesId = OutcomeToken(outcomeToken).yesTokenId(marketId);
        uint256 noId = OutcomeToken(outcomeToken).noTokenId(marketId);

        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = yesId;
        ids[1] = noId;
        amounts[0] = halfLiquidity;
        amounts[1] = halfLiquidity;

        OutcomeToken(outcomeToken).mintBatch(address(this), ids, amounts, "");

        // Track initial supply for both outcome tokens
        _winningSupply[marketId][1] += halfLiquidity; // YES held by contract
        _winningSupply[marketId][2] += halfLiquidity; // NO held by contract

        emit MarketCreated(marketId, question, msg.sender, oracleFeed);
        emit LiquidityAdded(marketId, msg.sender, initialLiquidity, halfLiquidity, halfLiquidity);
    }

    /// @notice Mints an equal amount of YES and NO outcome tokens against USDC
    /// @dev    Useful for providing two-sided positions without going through AMM.
    ///         CEI: check amount > 0, pull USDC, mint tokens, update collateral.
    /// @param marketId Target market (must not be resolved)
    /// @param amount   USDC to lock; user receives `amount` YES + `amount` NO tokens
    function mintOutcomeTokens(
        uint256 marketId,
        uint256 amount
    ) external override nonReentrant whenNotPaused {
        // --- Checks ---
        if (amount == 0) revert ZeroAmount();
        Market storage market = _markets[marketId];
        if (market.resolved) revert MarketAlreadyResolved(marketId);

        // --- Effects ---
        market.totalCollateral += amount;

        // --- Interactions ---
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);

        uint256 yesId = OutcomeToken(outcomeToken).yesTokenId(marketId);
        uint256 noId  = OutcomeToken(outcomeToken).noTokenId(marketId);

        OutcomeToken(outcomeToken).mint(msg.sender, yesId, amount, "");
        OutcomeToken(outcomeToken).mint(msg.sender, noId,  amount, "");

        // Track circulating supply for both sides
        _winningSupply[marketId][1] += amount;
        _winningSupply[marketId][2] += amount;

        emit CollateralMinted(marketId, msg.sender, amount);
    }
    // Liquidity provision

    /// @notice Adds proportional liquidity to a market's AMM reserves
    /// @dev    Mints LP shares proportional to USDC contribution relative to
    ///         existing totalCollateral. Both YES and NO reserves grow proportionally.
    ///         CEI: slippage check → effects (shares, reserves) → interactions (pull USDC, mint tokens).
    /// @param marketId   Target market
    /// @param usdcAmount USDC to deposit
    /// @param minLpShares Minimum LP shares to receive (slippage protection)
    function addLiquidity(
        uint256 marketId,
        uint256 usdcAmount,
        uint256 minLpShares
    ) external override nonReentrant whenNotPaused {
        // --- Checks ---
        if (usdcAmount == 0) revert ZeroAmount();
        Market storage market = _markets[marketId];
        if (market.resolved) revert MarketAlreadyResolved(marketId);

        uint256 totalCol = market.totalCollateral;
        uint256 totalShares = _totalLpShares[marketId];

        uint256 shares;
        uint256 yesToAdd;
        uint256 noToAdd;

        if (totalShares == 0 || totalCol == 0) {
            // Bootstrap: first liquidity after an unusual state reset
            shares = _sqrtAssembly(usdcAmount);
            yesToAdd = usdcAmount / 2;
            noToAdd  = usdcAmount / 2;
        } else {
            yesToAdd = (usdcAmount * market.yesReserve) / totalCol;
            noToAdd  = (usdcAmount * market.noReserve)  / totalCol;
            shares   = (usdcAmount * totalShares) / totalCol;
        }

        if (shares < minLpShares) revert SlippageExceeded(minLpShares, shares);

        // --- Effects ---
        market.yesReserve    += yesToAdd;
        market.noReserve     += noToAdd;
        market.totalCollateral += usdcAmount;
        _lpShares[marketId][msg.sender] += shares;
        _totalLpShares[marketId] += shares;

        // --- Interactions ---
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), usdcAmount);

        uint256 yesId = OutcomeToken(outcomeToken).yesTokenId(marketId);
        uint256 noId  = OutcomeToken(outcomeToken).noTokenId(marketId);

        OutcomeToken(outcomeToken).mint(address(this), yesId, yesToAdd, "");
        OutcomeToken(outcomeToken).mint(address(this), noId,  noToAdd,  "");

        _winningSupply[marketId][1] += yesToAdd;
        _winningSupply[marketId][2] += noToAdd;

        emit LiquidityAdded(marketId, msg.sender, usdcAmount, yesToAdd, noToAdd);
    }

    /// @notice Removes liquidity proportional to LP shares burned
    /// @dev    Burns `lpShares` from msg.sender and returns proportional USDC.
    ///         Corresponding outcome tokens held by the contract are burned too.
    ///         removeLiquidity is NOT guarded by whenNotPaused so LPs can always exit.
    /// @param marketId Target market
    /// @param lpShares LP shares to burn
    /// @param minUsdc  Minimum USDC to receive (slippage protection)
    function removeLiquidity(
        uint256 marketId,
        uint256 lpShares,
        uint256 minUsdc
    ) external override nonReentrant {
        // --- Checks ---
        if (lpShares == 0) revert ZeroAmount();
        Market storage market = _markets[marketId];

        uint256 senderShares = _lpShares[marketId][msg.sender];
        if (senderShares < lpShares) {
            revert InsufficientLiquidity(senderShares, lpShares);
        }

        uint256 totalShares = _totalLpShares[marketId];
        uint256 usdcToReturn = (lpShares * market.totalCollateral) / totalShares;

        if (usdcToReturn < minUsdc) revert SlippageExceeded(minUsdc, usdcToReturn);

        uint256 yesToBurn = (lpShares * market.yesReserve) / totalShares;
        uint256 noToBurn  = (lpShares * market.noReserve)  / totalShares;

        // --- Effects ---
        _lpShares[marketId][msg.sender] -= lpShares;
        _totalLpShares[marketId] -= lpShares;
        market.yesReserve     -= yesToBurn;
        market.noReserve      -= noToBurn;
        market.totalCollateral -= usdcToReturn;

        // --- Interactions ---
        uint256 yesId = OutcomeToken(outcomeToken).yesTokenId(marketId);
        uint256 noId  = OutcomeToken(outcomeToken).noTokenId(marketId);

        OutcomeToken(outcomeToken).burn(address(this), yesId, yesToBurn);
        OutcomeToken(outcomeToken).burn(address(this), noId,  noToBurn);

        _winningSupply[marketId][1] -= yesToBurn;
        _winningSupply[marketId][2] -= noToBurn;

        IERC20(usdc).safeTransfer(msg.sender, usdcToReturn);

        emit LiquidityRemoved(marketId, msg.sender, lpShares, usdcToReturn);
    }
    // Trading

    /// @notice Buys outcome tokens using USDC as input via the CPMM AMM
    /// @dev    CEI pattern:
    ///           Checks (market state, outcome validity, slippage)
    ///           → Effects (reserve update, fee accrual)
    ///           → Interactions (pull USDC, send fee, transfer outcome tokens)
    ///         outcome == 1 → buying YES (NO reserve is the input side)
    ///         outcome == 2 → buying NO  (YES reserve is the input side)
    /// @param marketId    Target market ID
    /// @param outcome     1 = YES, 2 = NO
    /// @param amountIn    USDC amount to spend (must be pre-approved)
    /// @param minAmountOut Minimum outcome tokens to receive (slippage protection)
    /// @return amountOut  Actual outcome tokens received
    function buy(
        uint256 marketId,
        uint8 outcome,
        uint256 amountIn,
        uint256 minAmountOut
    )
        external
        virtual
        override
        nonReentrant
        whenNotPaused
        returns (uint256 amountOut)
    {
        // --- Checks ---
        if (amountIn == 0) revert ZeroAmount();
        if (outcome != 1 && outcome != 2) revert InvalidOutcome(outcome);

        Market storage market = _markets[marketId];
        if (market.resolved) revert MarketAlreadyResolved(marketId);

        uint256 oldYes = market.yesReserve;
        uint256 oldNo  = market.noReserve;

        uint256 reserveIn;
        uint256 reserveOut;

        if (outcome == 1) {
            reserveIn  = oldNo;
            reserveOut = oldYes;
        } else {
            reserveIn  = oldYes;
            reserveOut = oldNo;
        }

        uint256 fee;
        (amountOut, fee) = AMM.getAmountOut(amountIn, reserveIn, reserveOut);

        if (amountOut < minAmountOut) revert SlippageExceeded(minAmountOut, amountOut);

        // Compute new reserves for k-invariant check
        uint256 newYes;
        uint256 newNo;
        uint256 amountInAfterFee = amountIn - fee;

        if (outcome == 1) {
            // User buys YES: NO reserve grows by amountInAfterFee, YES reserve shrinks
            newNo  = oldNo  + amountInAfterFee;
            newYes = oldYes - amountOut;
        } else {
            // User buys NO: YES reserve grows by amountInAfterFee, NO reserve shrinks
            newYes = oldYes + amountInAfterFee;
            newNo  = oldNo  - amountOut;
        }

        // k-invariant: newYes * newNo >= oldYes * oldNo
        if (!AMM.checkInvariant(oldYes, oldNo, newYes, newNo)) {
            revert InsufficientLiquidity(0, 0);
        }

        // --- Effects ---
        market.yesReserve   = newYes;
        market.noReserve    = newNo;
        market.feesAccrued += fee;
        // Tokens move from contract reserve to user — supply stays constant for winning side
        // No change to _winningSupply: tokens already counted from creation/mint

        // --- Interactions ---
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amountIn);

        // Route fee to FeeVault
        IERC20(usdc).safeIncreaseAllowance(feeVault, fee);
        FeeVault(feeVault).depositFees(fee);

        // Transfer outcome tokens from contract to buyer
        uint256 tokenId = (outcome == 1)
            ? OutcomeToken(outcomeToken).yesTokenId(marketId)
            : OutcomeToken(outcomeToken).noTokenId(marketId);

        IERC1155(outcomeToken).safeTransferFrom(
            address(this), msg.sender, tokenId, amountOut, ""
        );

        emit TokensPurchased(marketId, msg.sender, outcome, amountIn, amountOut);
    }

    /// @notice Sells outcome tokens back to the AMM for USDC
    /// @dev    Reverse CPMM: user gives outcome tokens, receives USDC minus fee.
    ///         CEI pattern:
    ///           Checks (market state, outcome, slippage)
    ///           → Effects (reserve update, fee accrual)
    ///           → Interactions (burn tokens, send fee, transfer USDC)
    /// @param marketId      Target market ID
    /// @param outcome       1 = YES, 2 = NO
    /// @param tokenAmountIn Outcome tokens to sell
    /// @param minUsdcOut    Minimum USDC to receive after fee (slippage protection)
    /// @return usdcOut      Net USDC received by seller (after fee deduction)
    function sell(
        uint256 marketId,
        uint8 outcome,
        uint256 tokenAmountIn,
        uint256 minUsdcOut
    )
        external
        virtual
        override
        nonReentrant
        whenNotPaused
        returns (uint256 usdcOut)
    {
        // --- Checks ---
        if (tokenAmountIn == 0) revert ZeroAmount();
        if (outcome != 1 && outcome != 2) revert InvalidOutcome(outcome);

        Market storage market = _markets[marketId];
        if (market.resolved) revert MarketAlreadyResolved(marketId);

        uint256 oldYes = market.yesReserve;
        uint256 oldNo  = market.noReserve;

        // When selling YES tokens: the YES side is the input reserve, NO is output
        uint256 reserveIn;
        uint256 reserveOut;

        if (outcome == 1) {
            reserveIn  = oldYes;
            reserveOut = oldNo;
        } else {
            reserveIn  = oldNo;
            reserveOut = oldYes;
        }

        // Gross USDC out before fee
        uint256 grossUsdcOut;
        (grossUsdcOut, ) = AMM.getAmountOut(tokenAmountIn, reserveIn, reserveOut);

        // Fee on output
        uint256 fee = (grossUsdcOut * FEE_BPS) / BPS;
        usdcOut = grossUsdcOut - fee;

        if (usdcOut < minUsdcOut) revert SlippageExceeded(minUsdcOut, usdcOut);

        // New reserves: input reserve grows by tokenAmountIn, output reserve shrinks by grossUsdcOut
        uint256 newYes;
        uint256 newNo;

        if (outcome == 1) {
            newYes = oldYes + tokenAmountIn;
            newNo  = oldNo  - grossUsdcOut;
        } else {
            newNo  = oldNo  + tokenAmountIn;
            newYes = oldYes - grossUsdcOut;
        }

        // k-invariant check
        if (!AMM.checkInvariant(oldYes, oldNo, newYes, newNo)) {
            revert InsufficientLiquidity(0, 0);
        }

        // --- Effects ---
        market.yesReserve   = newYes;
        market.noReserve    = newNo;
        market.feesAccrued += fee;
        // Selling burns tokens from circulation — decrease tracked supply
        _winningSupply[marketId][outcome] -= tokenAmountIn;

        // --- Interactions ---
        uint256 tokenId = (outcome == 1)
            ? OutcomeToken(outcomeToken).yesTokenId(marketId)
            : OutcomeToken(outcomeToken).noTokenId(marketId);

        // Burn seller's outcome tokens
        OutcomeToken(outcomeToken).burn(msg.sender, tokenId, tokenAmountIn);

        // Route fee to FeeVault
        IERC20(usdc).safeIncreaseAllowance(feeVault, fee);
        FeeVault(feeVault).depositFees(fee);

        // Transfer net USDC to seller
        IERC20(usdc).safeTransfer(msg.sender, usdcOut);

        emit TokensSold(marketId, msg.sender, outcome, tokenAmountIn, usdcOut);
    }
    // Oracle resolution

    /// @notice Resolves a market using its Chainlink oracle feed
    /// @dev    Can be called by anyone once resolutionTime has passed and the
    ///         oracle data is fresh. Price > 0 → YES wins; price == 0 → NO wins.
    /// @param marketId Target market to resolve
    function resolveMarket(
        uint256 marketId
    ) external override nonReentrant {
        // --- Checks ---
        Market storage market = _markets[marketId];
        if (market.resolved) revert MarketAlreadyResolved(marketId);
        if (block.timestamp < market.resolutionTime) {
            revert ResolutionTooEarly(market.resolutionTime, block.timestamp);
        }

        (int256 price, uint256 updatedAt) =
            IOracleAdapter(oracleAdapter).getLatestPrice(market.oracleFeed);

        // Staleness check (1 hour window)
        if (updatedAt < block.timestamp - 3600) {
            revert StalePrice(updatedAt, block.timestamp);
        }

        uint8 winningOutcome = (price > 0) ? 1 : 2;

        // --- Effects ---
        market.resolved = true;
        market.winningOutcome = winningOutcome;

        emit MarketResolved(marketId, winningOutcome);
    }
    // Redemption

    /// @notice Redeems winning outcome tokens for a proportional USDC payout
    /// @dev    Payout = userBalance * totalCollateral / totalWinningSupply
    ///         CEI pattern strictly enforced: balance checks → state updates
    ///         (burn) → USDC transfer.
    /// @param marketId Target resolved market
    function redeemWinningTokens(
        uint256 marketId
    ) external override nonReentrant {
        // --- Checks ---
        Market storage market = _markets[marketId];
        if (!market.resolved) revert MarketNotResolved(marketId);

        uint256 winningTokenId = (market.winningOutcome == 1)
            ? OutcomeToken(outcomeToken).yesTokenId(marketId)
            : OutcomeToken(outcomeToken).noTokenId(marketId);

        uint256 userBalance = IERC1155(outcomeToken).balanceOf(msg.sender, winningTokenId);
        if (userBalance == 0) revert ZeroAmount();

        // _winningSupply tracks every minted token for each outcome side,
        // decremented on sell (burn) and on redemption. ERC-1155 has no built-in
        // totalSupply, so this mapping is the authoritative circulating supply.
        // payout = userBalance * totalCollateral / totalWinningSupply

        uint256 totalWinningSupply = _winningSupply[marketId][market.winningOutcome];
        if (totalWinningSupply == 0) revert InsufficientLiquidity(0, 1);

        uint256 payout = (userBalance * market.totalCollateral) / totalWinningSupply;

        // --- Effects (burn before transfer — CEI) ---
        market.totalCollateral -= payout;
        _winningSupply[marketId][market.winningOutcome] -= userBalance;

        // Burn user's winning tokens
        OutcomeToken(outcomeToken).burn(msg.sender, winningTokenId, userBalance);

        // --- Interactions ---
        IERC20(usdc).safeTransfer(msg.sender, payout);

        emit WinningsRedeemed(marketId, msg.sender, payout);
    }
    // Views

    /// @notice Returns the full Market struct for a given market ID
    /// @param marketId Target market
    /// @return The Market struct
    function getMarket(
        uint256 marketId
    ) external view override returns (Market memory) {
        return _markets[marketId];
    }

    /// @notice Returns the AMM spot price of an outcome token in 1e18 fixed-point
    /// @dev    price(YES) = noReserve / (yesReserve + noReserve) * 1e18
    ///         price(NO)  = yesReserve / (yesReserve + noReserve) * 1e18
    /// @param marketId Target market
    /// @param outcome  1 = YES, 2 = NO
    /// @return price in 1e18 (range 0 < price < 1e18)
    function getPrice(
        uint256 marketId,
        uint8 outcome
    ) external view override returns (uint256 price) {
        if (outcome != 1 && outcome != 2) revert InvalidOutcome(outcome);
        Market storage market = _markets[marketId];
        if (outcome == 1) {
            price = AMM.spotPrice(market.noReserve, market.yesReserve);
        } else {
            price = AMM.spotPrice(market.yesReserve, market.noReserve);
        }
    }

    /// @notice Returns the LP share balance for an address in a given market
    /// @param marketId Target market
    /// @param provider Liquidity provider address
    /// @return LP share balance
    function getLpShares(
        uint256 marketId,
        address provider
    ) external view returns (uint256) {
        return _lpShares[marketId][provider];
    }

    /// @notice Returns the total LP shares for a given market
    /// @param marketId Target market
    /// @return Total LP shares outstanding
    function getTotalLpShares(uint256 marketId) external view returns (uint256) {
        return _totalLpShares[marketId];
    }

    /// @notice Returns the current total market count
    /// @return Number of markets created
    function marketCount() external view returns (uint256) {
        return _marketCount;
    }
    // Yul assembly sqrt (required by spec)

    /// @notice Computes integer square root using the Babylonian method in Yul assembly
    /// @dev    Used in createMarket to compute initial LP shares = sqrt(initialLiquidity).
    ///         Matches the pure-Solidity _sqrtSolidity output exactly.
    /// @param x Input value
    /// @return result Floor square root of x
    function _sqrtAssembly(uint256 x) internal pure returns (uint256 result) {
        assembly {
            // Handle edge case: sqrt(0) = 0
            switch x
            case 0 { result := 0 }
            default {
                // Initial guess: bit-length / 2 approximation
                result := x
                let z := add(div(x, 2), 1)
                // Babylonian iteration: converges to floor(sqrt(x))
                for {} lt(z, result) {} {
                    result := z
                    z := div(add(div(x, z), z), 2)
                }
            }
        }
    }

    /// @notice Pure-Solidity Babylonian sqrt for benchmarking and verification
    /// @dev    Produces identical output to _sqrtAssembly; used in test gas comparisons.
    /// @param x Input value
    /// @return result Floor square root of x
    function _sqrtSolidity(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) return 0;
        result = x;
        uint256 z = x / 2 + 1;
        while (z < result) {
            result = z;
            z = (x / z + z) / 2;
        }
    }
    // UUPS upgrade authorisation

    /// @notice Authorises a UUPS upgrade to newImplementation
    /// @dev    Restricted to UPGRADER_ROLE. Empty body — the role check is the guard.
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {}
    // Additional storage (MUST stay at the end for upgrade safety)

    /// @dev marketId → outcome (1/2) → total circulating supply of that outcome token
    ///      Updated on every mint/burn path to enable accurate redemption payouts.
    mapping(uint256 => mapping(uint8 => uint256)) internal _winningSupply;

    // Gap for future storage variables (50 slots reserved)
    uint256[50] private __gap;
}
