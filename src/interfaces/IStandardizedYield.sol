// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";

interface IStandardizedYield is IERC20Extended {
    /* ============ Events ============ */

    /**
     * @notice Emitted when any base tokens is deposited to mint shares.
     * @param  caller          Address which deposited the base tokens.
     * @param  receiver        Address which received the shares.
     * @param  tokenIn         Address of the base token deposited.
     * @param  amountDeposited Amount of base tokens deposited.
     * @param  amountSyOut     Amount of shares minted.
     */
    event Deposit(
        address indexed caller,
        address indexed receiver,
        address indexed tokenIn,
        uint256 amountDeposited,
        uint256 amountSyOut
    );

    /**
     * @notice Emitted when any shares are redeemed for base tokens.
     * @param  caller            Address which redeemed the shares.
     * @param  receiver          Address which received the base tokens.
     * @param  tokenOut          Address of the base token redeemed.
     * @param  amountSyToRedeem  Amount of shares redeemed.
     * @param  amountTokenOut    Amount of base tokens received.
     */
    event Redeem(
        address indexed caller,
        address indexed receiver,
        address indexed tokenOut,
        uint256 amountSyToRedeem,
        uint256 amountTokenOut
    );

    /* ============ Interactive Functions ============ */

    /**
     * @notice Mints an amount of shares by depositing a base token.
     * @dev    MUST emit the  `Deposit` event.
     *         MUST support ERC-20’s `approve` / `transferFrom` flow.
     *         MUST revert if `tokenIn` is an unsupported base token.
     *         MUST revert if `amountSharesOut` is lower than `minSharesOut`.
     *         MAY be payable if `tokenIn` is the chain’s native currency (e.g. ETH).
     * @param  receiver             Address which will receive the shares.
     * @param  tokenIn              Address of the base token deposited.
     * @param  amountTokenToDeposit Amount of base tokens to deposit into the wrapper.
     * @param  minSharesOut         Minimum amount of shares to receive.
     * @return amountSharesOut Amount of shares minted.
     */
    function deposit(
        address receiver,
        address tokenIn,
        uint256 amountTokenToDeposit,
        uint256 minSharesOut
    ) external payable returns (uint256 amountSharesOut);

    /**
     * @notice Redeems an amount of base tokens by burning shares.
     * @dev    MUST emit the `Redeem` event.
     *         MUST support ERC-20’s `approve` / `transferFrom` flow.
     *         MUST revert if `tokenOut` is an unsupported base token.
     *         MUST revert if `amountTokenOut` is lower than `minTokenOut`.
     * @param  receiver                Address which will receive the base tokens.
     * @param  amountSharesToRedeem    Amount of shares to be burned.
     * @param  tokenOut                Address of the base token to redeem.
     * @param  minTokenOut             Minimum amount of base token to receive.
     * @param  burnFromInternalBalance If true, burns from balance of `address(this)`,
     *                                 otherwise burns from `msg.sender`.
     * @return amountTokenOut Amount of base tokens redeemed.
     */
    function redeem(
        address receiver,
        uint256 amountSharesToRedeem,
        address tokenOut,
        uint256 minTokenOut,
        bool burnFromInternalBalance
    ) external returns (uint256 amountTokenOut);

    /* ============ View/Pure Functions ============ */

    /**
     * @notice Returns the current exchange rate between the shares and the base token.
     * @dev    MUST return the current exchange rate, such that `assetBalance = exchangeRate * syBalance / tokenUnit`
     *         and `syBalance = assetBalance * tokenUnit / exchangeRate`
     *         MUST NOT include fees that are charged against the underlying yield token in the SY contract.
     * @return The current exchange rate.
     */
    function exchangeRate() external view returns (uint256);

    /**
     * @notice Returns the address of the underlying yield token.
     * @dev    MUST return a token address that conforms to the ERC-20 interface, or zero address.
     *         MUST NOT revert.
     *         MUST reflect the exact underlying yield-bearing token address if the SY token is a wrapped token.
     *         MAY return 0x or zero address if the SY token is natively implemented, and not from wrapping.
     * @return Address of the underlying yield token.
     */
    function yieldToken() external view returns (address);

    /**
     * @notice Returns all tokens that can mint this SY.
     * @dev    MUST return ERC-20 token addresses.
     *         MUST return at least one address.
     *         MUST NOT revert.
     * @return Array of token addresses that can mint this SY.
     */
    function getTokensIn() external view returns (address[] memory);

    /**
     * @notice Returns all tokens that can be redeemed by this SY.
     * @dev    MUST return ERC-20 token addresses.
     *         MUST return at least one address.
     *         MUST NOT revert.
     * @return Array of token addresses that can be redeemed by this SY.
     */
    function getTokensOut() external view returns (address[] memory);

    /**
     * @notice Returns whether `token` is a valid base token or not.
     * @param token Address of the token to check.
     * @return Whether `token` is a valid base token or not.
     */
    function isValidTokenIn(address token) external view returns (bool);

    /**
     * @notice Returns whether `token` is a valid redeemable token or not.
     * @param token Address of the token to check.
     * @return Whether `token` is a valid redeemable token or not.
     */
    function isValidTokenOut(address token) external view returns (bool);

    /**
     * @notice Returns the amount of shares that would be minted by depositing `amountTokenToDeposit` of `tokenIn`.
     * @dev    MUST return an amount of shares less than or equal to the actual return value of the `deposit` method.
     *         SHOULD NOT return an amount of shares greater than the actual return value of the `deposit` method.
     *         SHOULD ONLY revert if minting SY token with the entered parameters is forbidden.
     * @param  tokenIn              Address of the token to deposit.
     * @param  amountTokenToDeposit Amount of token to deposit.
     * @return Amount of shares that would be minted.
     */
    function previewDeposit(address tokenIn, uint256 amountTokenToDeposit) external view returns (uint256);

    /**
     * @notice Returns the amount of `tokenOut` that would be redeemed by burning `amountSharesToRedeem` of SY.
     * @dev    MUST return an amount of `tokenOut` less than or equal to the actual return value of the `redeem` method.
     *         SHOULD NOT return an amount of `tokenOut` greater than the actual return value of the `redeem` method.
     *         SHOULD ONLY revert if burning SY token with the entered parameters is forbidden.
     * @param  tokenOut             Address of the token to redeem.
     * @param  amountSharesToRedeem Amount of shares to redeem.
     * @return Amount of `tokenOut` that would be redeemed.
     */
    function previewRedeem(address tokenOut, uint256 amountSharesToRedeem) external view returns (uint256);
}
