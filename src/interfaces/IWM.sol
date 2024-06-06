// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

interface IWM is IERC20Extended {
    /* ============ Events ============ */

    /**
     * @notice Emitted when auto claiming is set for `account`.
     * @param  caller  The account that called `setAutoClaiming()`.
     * @param  account The account for which auto claiming has been set.
     * @param  enabled Whether auto claiming was enabled or disabled.
     */
    event AutoClaimingSet(address indexed caller, address indexed account, bool enabled);

    /**
     * @notice Emitted when the earned M of an account is claimed.
     * @param  caller   The account that called `claim()`.
     * @param  account  Address of the account for which the earned M is claimed.
     * @param  receiver Address which received the claimed M tokens.
     * @param  amount   Amount of M tokens claimed.
     */
    event Claimed(address indexed caller, address indexed account, address indexed receiver, uint256 amount);

    /**
     * @notice Emitted when M tokens are deposited to mint WM shares.
     * @param  caller    Address which deposited the M tokens.
     * @param  receiver  Address which received the WM shares.
     * @param  shares    Amount of WM shares minted.
     */
    event Deposit(address indexed caller, address indexed receiver, uint256 shares);

    /**
     * @notice Emitted when WM shares are redeemed for M tokens.
     * @param  caller    Address which redeemed the WM shares.
     * @param  receiver  Address which received the M tokens.
     * @param  shares    Amount of WM shares redeemed.
     */
    event Redeem(address indexed caller, address indexed receiver, uint256 shares);

    /**
     * @notice Emitted when account starts being an M earner.
     * @param  caller  The account that called `startEarning()`.
     * @param  account The account that started earning.
     */
    event StartedEarning(address indexed caller, address indexed account);

    /**
     * @notice Emitted when account stops being a WM earner.
     * @param  caller  The account that called `stopEarning()`.
     * @param  account The account that stopped earning.
     */
    event StoppedEarning(address indexed caller, address indexed account);

    /* ============ Custom Errors ============ */

    /**
     * @notice Indicates an error related to the current `balance` of a `sender`. Used in transfers.
     * @param  sender  Address whose tokens are being transferred.
     * @param  balance Current balance for the interacting account.
     * @param  needed  Minimum amount required to perform a transfer.
     */
    error InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /**
     * @notice Emitted when calling `stopEarning` for an account earning in M token.
     * @param  account Address of the earning account.
     */
    error IsEarning(address account);

    /**
     * @notice Emitted when calling `startEarning` for an account not earning in M token.
     * @param  account Address of the earning account.
     */
    error IsNotEarning(address account);

    /**
     * @notice Emitted when calling `startEarning` for an account not managed by the WM manager.
     * @param  account Address of the account.
     */
    error IsNotManaged(address account);

    /**
     * @notice Emitted when the caller is not the claimer address approved by TTG.
     * @param  caller Address of the caller.
     */
    error NotClaimer(address caller);

    /**
     * @notice Emitted when the caller is not the manager address approved by TTG.
     * @param  caller Address of the caller.
     */
    error NotManager(address caller);

    /// @notice Emitted if amount to deposit is 0.
    error ZeroDeposit();

    /// @notice Emitted if shares to redeem is 0.
    error ZeroRedeem();

    /// @notice Emitted in constructor if M token is 0x0.
    error ZeroMToken();

    /// @notice Emitted in constructor if TTG Registrar is 0x0.
    error ZeroTTGRegistrar();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Mints an amount of WM shares by depositing M tokens.
     * @dev    MUST emit the  `Deposit` event.
     *         MUST support ERC-20’s `approve` / `transferFrom` flow.
     * @param  receiver Address which will receive the WM shares.
     * @param  amount   Amount of M tokens to deposit into the wrapper.
     * @return Amount of WM shares minted.
     */
    function deposit(address receiver, uint256 amount) external returns (uint256);

    /**
     * @notice Redeems an amount of M tokens by burning WM shares.
     * @dev    MUST emit the `Redeem` event.
     *         MUST support ERC-20’s `approve` / `transferFrom` flow.
     * @param  receiver                Address which will receive the M tokens.
     * @param  shares                  Amount of WM shares to be burned.
     * @return Amount of M tokens redeemed.
     */
    function redeem(address receiver, uint256 shares) external returns (uint256);

    /**
     * @notice Claims caller earned M.
     * @param  receiver The address that will receive the claimed M tokens.
     * @return Amount of M tokens claimed.
     */
    function claim(address receiver) external returns (uint256);

    /**
     * @notice Claims `account` earned M.
     * @dev    MUST only be callable by the claimer address approved by the TTG Registrar.
     * @dev    MUST revert if account has not added his address to the claimer list.
     * @param  account The account to claim for.
     * @param  receiver The address that will receive the claimed M tokens.
     * @return Amount of M tokens claimed.
     */
    function claim(address account, address receiver) external returns (uint256);

    /**
     * @notice Set auto claiming for caller.
     * @param  enabled Whether to enable or disable auto claiming.
     */
    function setAutoClaiming(bool enabled) external;

    /**
     * @notice Set auto claiming for `account`.
     * @dev    MUST only be callable by the manager address approved by the TTG Registrar.
     * @param  account The account to set auto claiming for.
     * @param  enabled Whether to enable or disable auto claiming.
     */
    function setAutoClaiming(address account, bool enabled) external;

    /**
     * @notice Starts earning for caller.
     * @dev    MUST revert if caller is not earning in M token.
     */
    function startEarning() external;

    /**
     * @notice Starts earning for `account`.
     * @dev    MUST revert if caller is not earning in M token.
     * @param  account The account to start earning for.
     */
    function startEarning(address account) external;

    /// @notice Stops earning for caller.
    function stopEarning() external;

    /**
     * @notice Stops earning for `account`.
     * @dev    MUST revert if `account` is earning in M token.
     * @param  account The account to stop earning for.
     */
    function stopEarning(address account) external;

    /* ============ View/Pure Functions ============ */

    /**
     * @notice Returns the latest recorded M token index.
     * @return Latest recorded M token index.
     */
    function index() external view returns (uint128);

    /**
     * @notice Returns the address of the underlying M token.
     * @return Address of the underlying M token.
     */
    function mToken() external view returns (address);

    /**
     * @notice The total amount of excess M earned by the WM token.
     * @dev    Amount of M earned by the non earning supply of M that is not yet claimed.
     * @dev    Can be claimed by the claimer by calling `claimExcessEarnedM`.
     * @return Total amount of excess M earned.
     */
    function totalExcessEarnedM() external view returns (uint112);

    /**
     * @notice The total amount of M earning in the WM token.
     * @return Total amount of M earning.
     */
    function totalEarningSupply() external view returns (uint112);

    /**
     * @notice The total amount of M not earning in the WM token.
     * @return Total amount of M not earning.
     */
    function totalNonEarningSupply() external view returns (uint112);

    /**
     * @notice Returns the TTG Registrar address.
     * @return Address of the TTG Registrar.
     */
    function ttgRegistrar() external view returns (address);
}
