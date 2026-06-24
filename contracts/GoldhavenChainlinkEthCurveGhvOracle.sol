// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice The interface expected by Goldhaven Hook and Vault.
interface IGoldhavenPriceOracle {
    function ethToUsdWad(uint256 ethWei) external view returns (uint256 usdWad);
    function ghvToUsdWad(uint256 ghvAmount) external view returns (uint256 usdWad);
}

/// @notice Minimal Chainlink AggregatorV3Interface.
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

/// @notice Minimal Goldhaven Hook pricing interface.
/// @dev marginalPrice() is expected to return ETH WAD per 1 full GHV token.
/// Example: 1 GHV = 0.001 ETH => marginalPrice() = 0.001e18.
interface IGoldhavenHookCurvePrice {
    function marginalPrice() external view returns (uint256 ethWadPerGhv);
    function curveReserveEth() external view returns (uint256);
    function totalMintedFair() external view returns (uint256);
}

/// @title GoldhavenChainlinkEthCurveGhvOracle
/// @notice ETH/USD comes from Chainlink; GHV/USD is derived from the Hook curve price.
/// @dev Deployment flow:
/// 1. Deploy this oracle before GHVHook. The constructor does not take a Hook address.
/// 2. Deploy GHVHook with this oracle address.
/// 3. Call oracle.setGhvHook(GHVHook) exactly once.
///
/// Outputs use USD WAD: 1 USD = 1e18.
contract GoldhavenChainlinkEthCurveGhvOracle is IGoldhavenPriceOracle {
    address public owner;
    address public pendingOwner;

    AggregatorV3Interface public immutable ethUsdFeed;
    IGoldhavenHookCurvePrice public ghvHook;

    /// @notice Max age of Chainlink ETH/USD answer.
    uint256 public maxStaleSeconds;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event GhvHookSet(address indexed hook);
    event MaxStaleSecondsUpdated(uint256 oldValue, uint256 newValue);

    error NotOwner();
    error NotPendingOwner();
    error ZeroAddress();
    error InvalidStaleWindow();
    error HookNotSet();
    error BadFeedAnswer();
    error StaleFeedAnswer();
    error BadCurvePrice();
    error HookAlreadySet();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(
        address ethUsdFeed_,
        uint256 maxStaleSeconds_,
        address initialOwner_
    ) {
        if (ethUsdFeed_ == address(0) || initialOwner_ == address(0)) revert ZeroAddress();
        if (maxStaleSeconds_ == 0) revert InvalidStaleWindow();

        ethUsdFeed = AggregatorV3Interface(ethUsdFeed_);
        maxStaleSeconds = maxStaleSeconds_;
        owner = initialOwner_;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, owner);
    }

    /// @notice Locks the Hook address exactly once after GHVHook deployment.
    function setGhvHook(address newGhvHook) external onlyOwner {
        if (address(ghvHook) != address(0)) revert HookAlreadySet();
        if (newGhvHook == address(0)) revert ZeroAddress();
        ghvHook = IGoldhavenHookCurvePrice(newGhvHook);
        emit GhvHookSet(newGhvHook);
    }

    function setMaxStaleSeconds(uint256 newMaxStaleSeconds) external onlyOwner {
        if (newMaxStaleSeconds == 0) revert InvalidStaleWindow();
        uint256 old = maxStaleSeconds;
        maxStaleSeconds = newMaxStaleSeconds;
        emit MaxStaleSecondsUpdated(old, newMaxStaleSeconds);
    }

    /// @notice Returns Chainlink ETH/USD price normalized to WAD.
    function ethUsdWad() public view returns (uint256) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) =
            ethUsdFeed.latestRoundData();

        if (answer <= 0) revert BadFeedAnswer();
        if (updatedAt == 0 || block.timestamp - updatedAt > maxStaleSeconds) {
            revert StaleFeedAnswer();
        }
        if (answeredInRound < roundId) revert StaleFeedAnswer();

        uint8 feedDecimals = ethUsdFeed.decimals();

        if (feedDecimals == 18) return uint256(answer);
        if (feedDecimals < 18) return uint256(answer) * (10 ** (18 - feedDecimals));
        return uint256(answer) / (10 ** (feedDecimals - 18));
    }

    /// @notice Returns current GHV/USD marginal price in WAD.
    /// @dev ghvUsdWad = hook.marginalPrice() ETH/GHV * ETH/USD.
    function ghvUsdWad() public view returns (uint256) {
        IGoldhavenHookCurvePrice hook = ghvHook;
        if (address(hook) == address(0)) revert HookNotSet();

        uint256 ethWadPerGhv = hook.marginalPrice();
        if (ethWadPerGhv == 0) revert BadCurvePrice();

        return (ethWadPerGhv * ethUsdWad()) / 1e18;
    }

    /// @notice Convert ETH wei to USD WAD.
    /// @dev If ETH/USD = 3500e18, ethToUsdWad(1 ether) = 3500e18.
    function ethToUsdWad(uint256 ethWei) external view returns (uint256 usdWad) {
        return (ethWei * ethUsdWad()) / 1e18;
    }

    /// @notice Convert GHV amount to USD WAD using current Hook marginal price.
    /// @dev Assumes GHV has 18 decimals.
    function ghvToUsdWad(uint256 ghvAmount) external view returns (uint256 usdWad) {
        return (ghvAmount * ghvUsdWad()) / 1e18;
    }

    /// @notice Helper: convert GHV amount to ETH wei using current Hook marginal price.
    function ghvToEthWei(uint256 ghvAmount) external view returns (uint256 ethWei) {
        IGoldhavenHookCurvePrice hook = ghvHook;
        if (address(hook) == address(0)) revert HookNotSet();

        uint256 ethWadPerGhv = hook.marginalPrice();
        if (ethWadPerGhv == 0) revert BadCurvePrice();

        return (ghvAmount * ethWadPerGhv) / 1e18;
    }
}
