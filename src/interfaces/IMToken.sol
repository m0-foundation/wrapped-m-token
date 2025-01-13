// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.26;

import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

import { IContinuousIndexing } from "./IContinuousIndexing.sol";

/**
 * @title  M Token Interface.
 * @author M^0 Labs
 */
interface IMToken is IContinuousIndexing, IERC20Extended {
    /* ============ Events ============ */

    /**
     * @notice Emitted when account starts being an M earner.
     * @param  account The account that started earning.
     */
    event StartedEarning(address indexed account);

    /**
     * @notice Emitted when account stops being an M earner.
     * @param  account The account that stopped earning.
     */
    event StoppedEarning(address indexed account);

    /* ============ Custom Errors ============ */

    /**
     * @notice Emitted when there is insufficient balance to decrement from `account`.
     * @param  account     The account with insufficient balance.
     * @param  rawBalance  The raw balance of the account.
     * @param  amount      The amount to decrement the `rawBalance` by.
     */
    error InsufficientBalance(address account, uint256 rawBalance, uint256 amount);

    /// @notice Emitted when an unauthorized account calls a function reserved for the minter.
    error NotMinter();

    /// @notice Emitted when principal of total supply (earning and non-earning) will overflow a `type(uint112).max`.
    error OverflowsPrincipalOfTotalSupply();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Mints tokens.
     * @param  account The address of account to mint to.
     * @param  amount  The amount of M Token to mint.
     */
    function mint(address account, uint256 amount) external;

    /**
     * @notice Starts earning for `account`.
     * @param  account The account to start earning for.
     */
    function startEarning(address account) external;

    /**
     * @notice Set the earner rate to use going forward.
     * @param  rate The earner rate to use going forward.
     */
    function setEarnerRate(uint32 rate) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The current value of earner rate in basis points.
    function earnerRate() external view returns (uint32);

    /**
     * @notice The principal of an earner M token balance.
     * @param  account The account to get the principal balance of.
     * @return The principal balance of the account.
     */
    function principalBalanceOf(address account) external view returns (uint240);

    /// @notice The principal of the total earning supply of M Token.
    function principalOfTotalEarningSupply() external view returns (uint112);

    /// @notice The total earning supply of M Token.
    function totalEarningSupply() external view returns (uint240);

    /// @notice The total non-earning supply of M Token.
    function totalNonEarningSupply() external view returns (uint240);

    /**
     * @notice Checks if account is an earner.
     * @param  account The account to check.
     * @return True if account is an earner, false otherwise.
     */
    function isEarning(address account) external view returns (bool);

    /// @notice The account that can mint and set the earner rate.
    function minter() external view returns (address);
}
