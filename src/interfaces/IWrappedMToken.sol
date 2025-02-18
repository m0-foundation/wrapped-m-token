// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

import { IMigratable } from "./IMigratable.sol";

/**
 * @title  Wrapped M Token interface extending Extended ERC20.
 * @author M^0 Labs
 */
interface IWrappedMToken is IMigratable, IERC20Extended {
    /* ============ Events ============ */

    /**
     * @notice Emitted when some yield is claim for `account` to `recipient`.
     * @param  account The account under which yield was generated.
     * @param  yield   The amount of yield claimed.
     */
    event Claimed(address indexed account, uint240 yield);

    /**
     * @notice Emitted when Wrapped M earning is enabled.
     * @param  index The M index at the moment earning is enabled.
     */
    event EarningEnabled(uint128 index);

    /**
     * @notice Emitted when Wrapped M earning is disabled.
     * @param  index The WrappedM index at the moment earning is disabled.
     */
    event EarningDisabled(uint128 index);

    /**
     * @notice Emitted when this contract's excess M is claimed.
     * @param  excess The amount of excess M claimed.
     */
    event ExcessClaimed(uint240 excess);

    /**
     * @notice Emitted when `account` starts being an wM earner.
     * @param  account The account that started earning.
     */
    event StartedEarning(address indexed account);

    /**
     * @notice Emitted when `account` stops being an wM earner.
     * @param  account The account that stopped earning.
     */
    event StoppedEarning(address indexed account);

    /* ============ Custom Errors ============ */

    /// @notice Emitted when trying to disable earning when earning is already disabled.
    error EarningIsDisabled();

    /// @notice Emitted when trying to enable earning when earning is already enabled.
    error EarningIsEnabled();

    /// @notice Emitted when trying to disable earning when the wrapper is approved by the Registrar.
    error WrapperIsApprovedEarner();

    /**
     * @notice Emitted when there is insufficient balance to decrement from `account`.
     * @param  account The account with insufficient balance.
     * @param  balance The balance of the account.
     * @param  amount  The amount to decrement.
     */
    error InsufficientBalance(address account, uint240 balance, uint240 amount);

    /// @notice Emitted when there is no excess to claim.
    error NoExcess();

    /// @notice Emitted when trying to enable earning when the wrapper is not approved by the Registrar.
    error WrapperIsNotApprovedEarner();

    /// @notice Emitted in constructor if Excess Destination is 0x0.
    error ZeroExcessDestination();

    /// @notice Emitted in constructor if M Token is 0x0.
    error ZeroMToken();

    /// @notice Emitted in constructor if Registrar is 0x0.
    error ZeroRegistrar();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Wraps `amount` M from the caller into wM for `recipient`.
     * @param  recipient The account receiving the minted wM.
     * @param  amount    The amount of M deposited.
     * @return wrapped   The amount of wM minted.
     */
    function wrap(address recipient, uint256 amount) external returns (uint240 wrapped);

    /**
     * @notice Wraps all the M from the caller into wM for `recipient`.
     * @param  recipient The account receiving the minted wM.
     * @return wrapped   The amount of wM minted.
     */
    function wrap(address recipient) external returns (uint240 wrapped);

    /**
     * @notice Wraps `amount` M from the caller into wM for `recipient`, using a permit.
     * @param  recipient The account receiving the minted wM.
     * @param  amount    The amount of M deposited.
     * @param  deadline  The last timestamp where the signature is still valid.
     * @param  v         An ECDSA secp256k1 signature parameter (EIP-2612 via EIP-712).
     * @param  r         An ECDSA secp256k1 signature parameter (EIP-2612 via EIP-712).
     * @param  s         An ECDSA secp256k1 signature parameter (EIP-2612 via EIP-712).
     * @return wrapped   The amount of wM minted.
     */
    function wrapWithPermit(
        address recipient,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint240 wrapped);

    /**
     * @notice Wraps `amount` M from the caller into wM for `recipient`, using a permit.
     * @param  recipient The account receiving the minted wM.
     * @param  amount    The amount of M deposited.
     * @param  deadline  The last timestamp where the signature is still valid.
     * @param  signature An arbitrary signature (EIP-712).
     * @return wrapped   The amount of wM minted.
     */
    function wrapWithPermit(
        address recipient,
        uint256 amount,
        uint256 deadline,
        bytes memory signature
    ) external returns (uint240 wrapped);

    /**
     * @notice Unwraps `amount` wM from the caller into M for `recipient`.
     * @param  recipient The account receiving the withdrawn M.
     * @param  amount    The amount of wM burned.
     * @return unwrapped The amount of M withdrawn.
     */
    function unwrap(address recipient, uint256 amount) external returns (uint240 unwrapped);

    /**
     * @notice Unwraps all the wM from the caller into M for `recipient`.
     * @param  recipient The account receiving the withdrawn M.
     * @return unwrapped The amount of M withdrawn.
     */
    function unwrap(address recipient) external returns (uint240 unwrapped);

    /**
     * @notice Claims any claimable yield for `account`.
     * @param  account The account under which yield was generated.
     * @return yield   The amount of yield claimed.
     */
    function claimFor(address account) external returns (uint240 yield);

    /**
     * @notice Claims any excess M of this contract.
     * @return claimed The amount of excess claimed.
     */
    function claimExcess() external returns (uint240 claimed);

    /// @notice Enables earning of Wrapped M if allowed by the Registrar and if it has never been done.
    function enableEarning() external;

    /// @notice Disables earning of Wrapped M if disallowed by the Registrar and if it has never been done.
    function disableEarning() external;

    /**
     * @notice Starts earning for `account` if allowed.
     * @param  account The account to start earning for.
     */
    function startEarningFor(address account) external;

    /**
     * @notice Starts earning for multiple accounts if individually allowed.
     * @param  accounts The accounts to start earning for.
     */
    function startEarningFor(address[] calldata accounts) external;

    /**
     * @notice Stops earning for `account` if disallowed.
     * @param  account The account to stop earning for.
     */
    function stopEarningFor(address account) external;

    /**
     * @notice Stops earning for multiple accounts if individually disallowed.
     * @param  accounts The accounts to stop earning for.
     */
    function stopEarningFor(address[] calldata accounts) external;

    /* ============ View/Pure Functions ============ */

    /// @notice Registrar key holding value of whether the earners list can be ignored or not.
    function EARNERS_LIST_IGNORED_KEY() external pure returns (bytes32 earnersListIgnoredKey);

    /// @notice Registrar key of earners list.
    function EARNERS_LIST_NAME() external pure returns (bytes32 earnersListName);

    /**
     * @notice Returns the yield accrued for `account`, which is claimable.
     * @param  account The account being queried.
     * @return yield   The amount of yield that is claimable.
     */
    function accruedYieldOf(address account) external view returns (uint240 yield);

    /**
     * @notice Returns the token balance of `account` including any accrued yield.
     * @param  account The address of some account.
     * @return balance The token balance of `account` including any accrued yield.
     */
    function balanceWithYieldOf(address account) external view returns (uint256 balance);

    /**
     * @notice Returns the earning principal of `account`.
     * @param  account          The address of some account.
     * @return earningPrincipal The earning principal of `account`.
     */
    function earningPrincipalOf(address account) external view returns (uint112 earningPrincipal);

    /// @notice The current index of Wrapped M's earning mechanism.
    function currentIndex() external view returns (uint128 index);

    /// @notice The M token's index when earning was most recently enabled.
    function enableMIndex() external view returns (uint128 enableMIndex);

    /// @notice This contract's current excess M that is not earmarked for account balances or accrued yield.
    function excess() external view returns (int248 excess);

    /// @notice The wrapper's index when earning was most recently disabled.
    function disableIndex() external view returns (uint128 disableIndex);

    /**
     * @notice Returns whether `account` is a wM earner.
     * @param  account   The account being queried.
     * @return isEarning Whether the account is a wM earner.
     */
    function isEarning(address account) external view returns (bool isEarning);

    /// @notice Whether Wrapped M earning is enabled.
    function isEarningEnabled() external view returns (bool isEnabled);

    /// @notice The address of the M Token contract.
    function mToken() external view returns (address mToken);

    /// @notice The projected total earning supply if all accrued yield was claimed at this moment.
    function projectedEarningSupply() external view returns (uint240 supply);

    /// @notice The address of the Registrar.
    function registrar() external view returns (address registrar);

    /// @notice The portion of total supply that is not earning yield.
    function totalNonEarningSupply() external view returns (uint240 totalSupply);

    /// @notice The accrued yield of the portion of total supply that is earning yield.
    function totalAccruedYield() external view returns (uint240 yield);

    /// @notice The portion of total supply that is earning yield.
    function totalEarningSupply() external view returns (uint240 totalSupply);

    /// @notice The total earning principal to help compute totalAccruedYield(), and thus excess().
    function totalEarningPrincipal() external view returns (uint112 totalEarningPrincipal);

    /// @notice The address of the destination where excess is claimed to.
    function excessDestination() external view returns (address excessDestination);

    /// @notice The amount of rounding error the contract has lost due to rounding in favour of users.
    function roundingError() external view returns (int144 roundingError);
}
