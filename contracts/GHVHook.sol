// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IHooks} from "v4-core-main/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core-main/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core-main/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core-main/src/types/PoolKey.sol";
import {Currency} from "v4-core-main/src/types/Currency.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core-main/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core-main/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core-main/src/types/BeforeSwapDelta.sol";

import {GHVToken} from "./GHVToken.sol";
import {Curve} from "./lib/Curve.sol";
import {IGoldhavenNFT} from "./interfaces/IGoldhavenNFT.sol";
import {IGoldhavenVault} from "./interfaces/IGoldhavenVault.sol";
import {IGoldhavenPriceOracle} from "./interfaces/IGoldhavenPriceOracle.sol";

/// @title GHVHook
/// @notice Goldhaven Uniswap v4 hook: curve buy/sell, 2% arena tax, and on-chain NFT minting.
/// @dev This uses beforeSwapReturnDelta custom accounting. Deploy with a HookMiner-compatible address.
contract GHVHook is IHooks {
    uint256 public constant K_SUPPLY = 21_000_000e18;
    uint256 public constant S = 73_884_348_733_790_717_179;
    uint256 public constant MAX_BUY_WEI = 5 ether;
    uint256 public constant COOLDOWN_BLOCKS = 1;
    uint24 public constant POOL_FEE = 3000;
    uint256 public constant ENTROPY_BLOCKS = 100;

    /// @notice 2% buy/sell tax, routed to arena vault accounting.
    uint256 internal constant FEE_NUMERATOR = 200;
    uint256 internal constant FEE_DENOMINATOR = 10_000;

    IPoolManager public immutable POOL_MANAGER;
    GHVToken public immutable GHV_TOKEN;
    IGoldhavenNFT public immutable GHV_NFT;
    IGoldhavenVault public immutable GHV_VAULT;
    IGoldhavenPriceOracle public immutable PRICE_ORACLE;
    Currency public immutable ETH_CURRENCY;
    Currency public immutable GHV_CURRENCY;
    uint256 public immutable GENESIS_BLOCK;
    bytes32 public immutable GENESIS_HASH;
    uint256 public immutable NFT_THRESHOLD_USD_WAD;

    /// @notice ETH actually backing the curve. Does not include arena tax funds.
    uint256 public ethCum;

    /// @notice ETH tax balance reserved for arenas.
    uint256 public arenaVaultEth;

    /// @notice Address allowed to pull daily arena funding. Locked at deployment, usually ArenaFactory.
    address public immutable ARENA_CONTROLLER;

    bool public poolInitialized;
    mapping(address account => uint256 blockNumber) public lastBuyBlock;

    error NotPoolManager();
    error NotArenaController();
    error InvalidPool();
    error LiquidityAdditionsForbidden();
    error BuyTooLarge();
    error CooldownActive();
    error ExactOutputUnsupported();
    error MissingSwapperInHookData();
    error InsufficientEthReserves();
    error InsufficientArenaVault();
    error ZeroAddress();
    error TokenSupplyZero();

    event ArenaControllerLocked(address indexed controller);
    event Bought(address indexed swapper, uint256 ethIn, uint256 fee, uint256 curveEth, uint256 ghvOut);
    event Sold(address indexed swapper, uint256 ghvIn, uint256 ethRaw, uint256 fee, uint256 ethOut);
    event ArenaFundingPulled(address indexed to, uint256 amount);
    event ArenaFeeDeposited(address indexed from, uint256 amount);

    constructor(
        IPoolManager poolManager,
        GHVToken ghvToken,
        IGoldhavenNFT ghvNFT,
        IGoldhavenVault ghvVault,
        IGoldhavenPriceOracle priceOracle,
        uint256 nftThresholdUsdWad,
        address arenaController_
    ) {
        if (address(poolManager) == address(0) || address(ghvToken) == address(0) || address(ghvNFT) == address(0)) {
            revert ZeroAddress();
        }
        if (address(ghvVault) == address(0) || address(priceOracle) == address(0) || arenaController_ == address(0)) {
            revert ZeroAddress();
        }
        POOL_MANAGER = poolManager;
        GHV_TOKEN = ghvToken;
        GHV_NFT = ghvNFT;
        GHV_VAULT = ghvVault;
        PRICE_ORACLE = priceOracle;
        ETH_CURRENCY = Currency.wrap(address(0));
        GHV_CURRENCY = Currency.wrap(address(ghvToken));
        GENESIS_BLOCK = block.number;
        GENESIS_HASH = blockhash(block.number - 1);
        NFT_THRESHOLD_USD_WAD = nftThresholdUsdWad;
        ARENA_CONTROLLER = arenaController_;
        emit ArenaControllerLocked(arenaController_);
        Hooks.validateHookPermissions(this, getHookPermissions());
    }

    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function totalMintedFair() external view returns (uint256) {
        return Curve.totalMinted(ethCum);
    }

    function curveReserveEth() external view returns (uint256) {
        return ethCum;
    }

    function marginalPrice() external view returns (uint256) {
        return Curve.marginalPrice(ethCum);
    }

    modifier onlyPoolManager() {
        if (msg.sender != address(POOL_MANAGER)) revert NotPoolManager();
        _;
    }

    modifier onlyArenaController() {
        if (msg.sender != ARENA_CONTROLLER) revert NotArenaController();
        _;
    }

    /// @notice Backwards-compatible getter for frontends expecting `arenaController()`.
    function arenaController() external view returns (address) {
        return ARENA_CONTROLLER;
    }

    /// @notice Vault/NFT staking fee entry point. Anyone may donate to the arena treasury.
    function depositArenaFee() external payable {
        arenaVaultEth += msg.value;
        emit ArenaFeeDeposited(msg.sender, msg.value);
    }

    /// @notice Pull arena funds; ArenaFactory should call this with 70% of arenaVaultEth at daily open.
    function pullArenaFunding(address payable to, uint256 amount) external onlyArenaController {
        if (amount > arenaVaultEth) revert InsufficientArenaVault();
        arenaVaultEth -= amount;
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert InsufficientEthReserves();
        emit ArenaFundingPulled(to, amount);
    }

    function beforeInitialize(address, PoolKey calldata key, uint160) external onlyPoolManager returns (bytes4) {
        if (Currency.unwrap(key.currency0) != address(0)) revert InvalidPool();
        if (Currency.unwrap(key.currency1) != address(GHV_TOKEN)) revert InvalidPool();
        if (key.fee != POOL_FEE) revert InvalidPool();
        if (address(key.hooks) != address(this)) revert InvalidPool();
        poolInitialized = true;
        return IHooks.beforeInitialize.selector;
    }

    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4)
    {
        revert LiquidityAdditionsForbidden();
    }

    function beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external
        onlyPoolManager
        returns (bytes4 selector, BeforeSwapDelta delta, uint24 lpFeeOverride)
    {
        if (params.amountSpecified >= 0) revert ExactOutputUnsupported();
        if (Currency.unwrap(key.currency0) != address(0) || Currency.unwrap(key.currency1) != address(GHV_TOKEN)) {
            revert InvalidPool();
        }
        if (hookData.length < 32) revert MissingSwapperInHookData();
        address swapper = _decodeSwapper(hookData);
        if (params.zeroForOne) {
            return _executeBuy(uint256(-params.amountSpecified), swapper);
        }
        return _executeSell(uint256(-params.amountSpecified), swapper);
    }

    // Unused hook selectors are implemented to satisfy IHooks.
    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure returns (bytes4) { return IHooks.afterInitialize.selector; }

    function afterAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata)
        external
        pure
        returns (bytes4, BalanceDelta)
    {
        return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata) external pure returns (bytes4) {
        return IHooks.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata)
        external
        pure
        returns (bytes4, BalanceDelta)
    {
        return (IHooks.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    function afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata) external pure returns (bytes4, int128) {
        return (IHooks.afterSwap.selector, int128(0));
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IHooks.beforeDonate.selector;
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IHooks.afterDonate.selector;
    }

    function _decodeSwapper(bytes calldata hookData) internal pure returns (address swapper) {
        if (hookData.length >= 96) {
            string memory ignoredImageURI;
            (swapper, ignoredImageURI) = abi.decode(hookData, (address, string));
        } else {
            swapper = abi.decode(hookData, (address));
        }
    }

    function _executeBuy(uint256 ethIn, address swapper) internal returns (bytes4, BeforeSwapDelta, uint24) {
        if (ethIn > MAX_BUY_WEI) revert BuyTooLarge();
        uint256 fee = (ethIn * FEE_NUMERATOR) / FEE_DENOMINATOR;
        uint256 ethToCurve = ethIn - fee;
        uint256 fairGHV = Curve.mintFor(ethCum, ethToCurve);
        uint256 mintAmount = _applyEntropy(fairGHV, swapper, ethIn);

        POOL_MANAGER.sync(GHV_CURRENCY);
        GHV_TOKEN.mint(address(POOL_MANAGER), mintAmount);
        POOL_MANAGER.settle();

        POOL_MANAGER.take(ETH_CURRENCY, address(this), ethIn);

        ethCum += ethToCurve;
        arenaVaultEth += fee;
        lastBuyBlock[swapper] = block.number;


        uint256 buyUsdWad = PRICE_ORACLE.ethToUsdWad(ethIn);
        if (buyUsdWad > NFT_THRESHOLD_USD_WAD) {
            uint256 avgUsdWad = GHV_VAULT.averageLockUsdWad24h();
            bytes32 seed = keccak256(abi.encodePacked(GENESIS_HASH, block.prevrandao, blockhash(block.number - 1), swapper, ethIn, mintAmount, ethCum));
            GHV_NFT.mintFromHook(swapper, buyUsdWad, avgUsdWad, seed);
        }

        emit Bought(swapper, ethIn, fee, ethToCurve, mintAmount);
        BeforeSwapDelta delta = toBeforeSwapDelta(int128(int256(ethIn)), -int128(int256(mintAmount)));
        return (IHooks.beforeSwap.selector, delta, 0);
    }

    function _executeSell(uint256 ghvIn, address swapper) internal returns (bytes4, BeforeSwapDelta, uint24) {
        uint256 lastBlock = lastBuyBlock[swapper];
        if (lastBlock != 0 && (block.number - lastBlock) < COOLDOWN_BLOCKS) revert CooldownActive();

        uint256 actualSupply = GHV_TOKEN.totalSupply();
        if (actualSupply == 0) revert TokenSupplyZero();
        uint256 currentFairSupply = Curve.totalMinted(ethCum);
        uint256 ghvFairIn = (ghvIn * currentFairSupply) / actualSupply;
        if (ghvFairIn > currentFairSupply) ghvFairIn = currentFairSupply;

        uint256 ethRaw = Curve.burnFor(currentFairSupply, ghvFairIn);
        uint256 fee = (ethRaw * FEE_NUMERATOR) / FEE_DENOMINATOR;
        uint256 ethOut = ethRaw - fee;

        if (ethRaw > ethCum || address(this).balance < ethOut) revert InsufficientEthReserves();

        POOL_MANAGER.take(GHV_CURRENCY, address(this), ghvIn);
        GHV_TOKEN.burn(address(this), ghvIn);
        POOL_MANAGER.settle{value: ethOut}();

        ethCum -= ethRaw;
        arenaVaultEth += fee;

        emit Sold(swapper, ghvIn, ethRaw, fee, ethOut);
        BeforeSwapDelta delta = toBeforeSwapDelta(int128(int256(ghvIn)), -int128(int256(ethOut)));
        return (IHooks.beforeSwap.selector, delta, 0);
    }

    function unaccountedEth() external view returns (uint256) {
        uint256 accounted = ethCum + arenaVaultEth;
        uint256 balance = address(this).balance;
        return balance > accounted ? balance - accounted : 0;
    }

    function _applyEntropy(uint256 fairGHV, address swapper, uint256 ethIn) internal view returns (uint256) {
        if (block.number >= GENESIS_BLOCK + ENTROPY_BLOCKS) return fairGHV;
        bytes32 h = keccak256(abi.encodePacked(blockhash(block.number - 1), swapper, ethIn));
        uint256 mul = 9000 + (uint256(h) % 2001);
        return (fairGHV * mul) / 10_000;
    }

    receive() external payable {
        // PoolManager transfers native ETH here during swaps; those amounts are accounted
        // explicitly in _executeBuy(). Direct ETH donations are treated as arena funding.
        if (msg.sender != address(POOL_MANAGER) && msg.value > 0) {
            arenaVaultEth += msg.value;
            emit ArenaFeeDeposited(msg.sender, msg.value);
        }
    }
}
