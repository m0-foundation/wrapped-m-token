// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IERC20 } from "../lib/common/src/interfaces/IERC20.sol";

import { ERC20Extended } from "../lib/common/src/ERC20Extended.sol";

import { IStandardizedYield } from "./interfaces/IStandardizedYield.sol";

/**
 * @title WM token wrapper with static balances.
 * @author M^0 Labs
 * @notice ERC5115 WM token.
 */
contract WM is IStandardizedYield, ERC20Extended {
    /* ============ Variables ============ */

    /// @inheritdoc IERC20
    mapping(address account => uint256 shares) public balanceOf;

    /// @inheritdoc IERC20
    uint256 public totalSupply;

    /// @inheritdoc IStandardizedYield
    address public immutable yieldToken;

    /// @notice Underlying yield token unit.
    uint256 private immutable _yieldTokenUnit;

    /* ============ Custom Errors ============ */

    /**
     * @notice Emitted if the amount of shares minted is lower than the minimum required.
     * @param  amountSharesOut Amount of shares minted.
     * @param  minSharesOut    Minimum amount of shares required.
     */
    error InsufficientSharesOut(uint256 amountSharesOut, uint256 minSharesOut);

    /**
     * @notice Emitted if the amount of token redeemed is lower than the minimum required.
     * @param  amountTokenOut Amount of token redeemed.
     * @param  minTokenOut    Minimum amount of token required.
     */
    error InsufficientTokenOut(uint256 amountTokenOut, uint256 minTokenOut);

    /**
     * @notice Emitted if `tokenIn` is unsupported by the WM token wrapper.
     * @param  tokenIn Address of the unsupported token.
     */
    error InvalidTokenIn(address tokenIn);

    /**
     * @notice Emitted if `tokenOut` is unsupported by the WM token wrapper.
     * @param  tokenOut Address of the unsupported token.
     */
    error InvalidTokenOut(address tokenOut);

    /// @notice Emitted if `amountTokenToDeposit` is 0.
    error ZeroDeposit();

    /// @notice Emitted in constructor if M token is 0x0.
    error ZeroMToken();

    /// @notice Emitted if `amountSharesToRedeem` is 0.
    error ZeroRedeem();

    /* ============ Constructor ============ */

    /**
     * @notice Constructs the WM token contract.
     * @param  mToken_ Address of the underlying yield token.
     */
    constructor(address mToken_) ERC20Extended("WM by M^0", "M", IERC20(mToken_).decimals()) {
        if ((yieldToken = mToken_) == address(0)) revert ZeroMToken();
        _yieldTokenUnit = 10 ** IERC20(mToken_).decimals();
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IStandardizedYield
    function deposit(
        address receiver_,
        address tokenIn_,
        uint256 amountTokenToDeposit_,
        uint256 minSharesOut_
    ) external payable returns (uint256 amountSharesOut_) {
        // TODO: handle deposit from non earner
        _isValidTokenIn(tokenIn_);
        if (amountTokenToDeposit_ == 0) revert ZeroDeposit();

        IERC20(tokenIn_).transferFrom(msg.sender, address(this), amountTokenToDeposit_);

        amountSharesOut_ = _previewDeposit(amountTokenToDeposit_);
        if (amountSharesOut_ < minSharesOut_) revert InsufficientSharesOut(amountSharesOut_, minSharesOut_);

        _mint(receiver_, amountSharesOut_);
        emit Deposit(msg.sender, receiver_, tokenIn_, amountTokenToDeposit_, amountSharesOut_);
    }

    /// @inheritdoc IStandardizedYield
    function redeem(
        address receiver_,
        uint256 amountSharesToRedeem_,
        address tokenOut_,
        uint256 minTokenOut_,
        bool burnFromInternalBalance_
    ) external returns (uint256 amountTokenOut_) {
        // TODO: handle redeem from non earner
        _isValidTokenOut(tokenOut_);
        if (amountSharesToRedeem_ == 0) revert ZeroRedeem();

        if (burnFromInternalBalance_) {
            _burn(address(this), amountSharesToRedeem_);
        } else {
            _burn(msg.sender, amountSharesToRedeem_);
        }

        amountTokenOut_ = _previewRedeem(amountSharesToRedeem_);
        if (amountTokenOut_ < minTokenOut_) revert InsufficientTokenOut(amountTokenOut_, minTokenOut_);

        emit Redeem(msg.sender, receiver_, tokenOut_, amountSharesToRedeem_, amountTokenOut_);
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IStandardizedYield
    function previewDeposit(address tokenIn_, uint256 amountTokenToDeposit_) external view returns (uint256) {
        _isValidTokenIn(tokenIn_);
        return _previewDeposit(amountTokenToDeposit_);
    }

    /// @inheritdoc IStandardizedYield
    function previewRedeem(address tokenOut, uint256 amountSharesToRedeem) external view returns (uint256) {
        _isValidTokenOut(tokenOut);
        return _previewRedeem(amountSharesToRedeem);
    }

    /// @inheritdoc IStandardizedYield
    function exchangeRate() public view returns (uint256) {
        // exchangeRate = (yieldTokenUnit * wrapperBalanceOfYieldToken) / totalSupply
        return
            totalSupply == 0
                ? _yieldTokenUnit
                : (_yieldTokenUnit * IERC20(yieldToken).balanceOf(address(this))) / totalSupply;
    }

    /// @inheritdoc IStandardizedYield
    function getTokensIn() public view override returns (address[] memory) {
        address[] memory tokensIn_ = new address[](1);
        tokensIn_[0] = yieldToken;
        return tokensIn_;
    }

    /// @inheritdoc IStandardizedYield
    function getTokensOut() public view override returns (address[] memory) {
        address[] memory tokensOut_ = new address[](1);
        tokensOut_[0] = yieldToken;
        return tokensOut_;
    }

    /// @inheritdoc IStandardizedYield
    function isValidTokenIn(address token_) public view override returns (bool) {
        return token_ == yieldToken;
    }

    /// @inheritdoc IStandardizedYield
    function isValidTokenOut(address token_) public view override returns (bool) {
        return token_ == yieldToken;
    }

    /* ============ Internal Interactive Functions ============ */

    /**
     * @dev   Burns `shares_` amount from `account_`.
     * @param account_ Address to burn from.
     * @param shares_  Amount of shares to burn.
     */
    function _burn(address account_, uint256 shares_) internal {
        _transfer(account_, address(0), shares_);
    }

    /**
     * @dev   Mints `shares_` amount to `receiver_`.
     * @param receiver_ Address to mint to.
     * @param shares_   Amount of shares to mint.
     */
    function _mint(address receiver_, uint256 shares_) internal {
        _transfer(address(0), receiver_, shares_);
    }

    /**
     * @dev   Internal ERC20 transfer function.
     * @param sender_    The sender's address.
     * @param receiver_  The receiver's address.
     * @param amount_    The amount to be transferred.
     */
    function _transfer(address sender_, address receiver_, uint256 amount_) internal override {
        // TODO: improve this logic
        if (sender_ != address(0)) {
            balanceOf[sender_] -= amount_;
        }

        if (receiver_ != address(0)) {
            balanceOf[receiver_] += amount_;
        }

        if (sender_ == address(0)) {
            totalSupply += amount_;
        }

        if (receiver_ == address(0)) {
            totalSupply -= amount_;
        }

        emit Transfer(sender_, receiver_, amount_);
    }

    /* ============ Internal View/Pure Functions ============ */

    /**
     * @notice Returns the amount of shares that would be minted for a given amount of token to deposit.
     * @param  amountTokenToDeposit_ Amount of token to deposit.
     * @return Amount of shares that would be minted.
     */
    function _previewDeposit(uint256 amountTokenToDeposit_) internal view returns (uint256) {
        // shares = (amountTokenToDeposit_ * totalSupply) / wrapperBalanceOfYieldToken
        return
            amountTokenToDeposit_ == 0
                ? amountTokenToDeposit_
                : (amountTokenToDeposit_ * _yieldTokenUnit) / exchangeRate();
    }

    /**
     * @notice Returns the amount of token that would be redeemed for a given amount of shares to redeem.
     * @param  amountSharesToRedeem_ Amount of shares to redeem.
     * @return Amount of token that would be redeemed.
     */
    function _previewRedeem(uint256 amountSharesToRedeem_) internal view returns (uint256) {
        // tokenOut = (amountSharesToRedeem_ * wrapperBalanceOfYieldToken) / totalSupply
        return
            amountSharesToRedeem_ == 0
                ? amountSharesToRedeem_
                : (amountSharesToRedeem_ * exchangeRate()) / _yieldTokenUnit;
    }

    /**
     * @notice Checks if `tokenIn_` is a valid token to deposit.
     * @param  tokenIn_ Address of the token to check.
     */
    function _isValidTokenIn(address tokenIn_) internal view {
        if (!isValidTokenIn(tokenIn_)) revert InvalidTokenIn(tokenIn_);
    }

    /**
     * @notice Checks if `tokenOut_` is a valid token to redeem.
     * @param  tokenOut_ Address of the token to check.
     */
    function _isValidTokenOut(address tokenOut_) internal view {
        if (!isValidTokenOut(tokenOut_)) revert InvalidTokenOut(tokenOut_);
    }
}
