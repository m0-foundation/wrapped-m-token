// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IERC20 } from "../lib/common/src/interfaces/IERC20.sol";
import { ERC20Extended } from "../lib/common/src/ERC20Extended.sol";

import { IContinuousIndexing } from "../lib/protocol/src/interfaces/IContinuousIndexing.sol";
import { ITTGRegistrar } from "../lib/protocol/src/interfaces/ITTGRegistrar.sol";
import { IMToken } from "../lib/protocol/src/interfaces/IMToken.sol";

import { ContinuousIndexingMath } from "../lib/protocol/src/libs/ContinuousIndexingMath.sol";

import { IStandardizedYield } from "./interfaces/IStandardizedYield.sol";
import { IWM } from "./interfaces/IWM.sol";

import { TTGRegistrarReader } from "./libs/TTGRegistrarReader.sol";

/**
 * @title WM token wrapper with static balances.
 * @author M^0 Labs
 * @notice ERC5115 WM token.
 */
contract WM is IWM, ERC20Extended {
    /* ============ Structs ============ */

    /**
     * @notice WM token balance struct.
     * @param  isEarning   True if the account is earning, false otherwise.
     * @param  latestIndex Latest recorded index of account. 0 for a non earning account.
     *                     The latest M token index at the time the balance of an earning account was last updated.
     * @param  balance     Balance of MW tokens.
     * @param  earned      Earned WM tokens for a currently earning account or an account that was earning in the past.
     *                     This amount is stored at the current exchange rate between M and WM when the interest is captured.
     */
    struct WMBalance {
        bool isEarning;
        uint128 latestIndex;
        uint256 balance;
        uint256 earned;
    }

    /* ============ Variables ============ */

    /// @inheritdoc IWM
    uint128 public latestIndex;

    /// @inheritdoc IERC20
    uint256 public totalSupply;

    /// @inheritdoc IWM
    uint256 public totalEarnedM;

    /// @inheritdoc IStandardizedYield
    address public immutable yieldToken;

    /// @inheritdoc IWM
    address public immutable ttgRegistrar;

    // @notice The total principal balance of earning supply.
    uint112 internal _principalOfTotalEarningSupply;

    /// @notice M token decimals.
    uint8 private constant _DECIMALS = 6;

    /// @notice Underlying yield token unit.
    uint256 private constant _YIELD_TOKEN_UNIT = 10 ** _DECIMALS;

    /// @notice WM token balances.
    mapping(address account => WMBalance balance) internal _balances;

    /* ============ Constructor ============ */

    /**
     * @notice Constructs the WM token contract.
     * @param  mToken_       Address of the underlying yield token.
     * @param  ttgRegistrar_ Address of the TTG Registrar contract.
     */
    constructor(address mToken_, address ttgRegistrar_) ERC20Extended("WM by M^0", "M", _DECIMALS) {
        if ((yieldToken = mToken_) == address(0)) revert ZeroMToken();
        if ((ttgRegistrar = ttgRegistrar_) == address(0)) revert ZeroTTGRegistrar();

        latestIndex = IContinuousIndexing(mToken_).currentIndex();
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

    /// @inheritdoc IWM
    function distributeExcessEarnedM(uint256 minAmount_) external {
        if (!TTGRegistrarReader.isApprovedLiquidator(ttgRegistrar, msg.sender))
            revert NotApprovedLiquidator(msg.sender);

        IMToken mToken_ = IMToken(yieldToken);

        uint256 excessEarnedM = mToken_.balanceOf(address(this)) - totalEarnedM;
        minAmount_ = minAmount_ > excessEarnedM ? excessEarnedM : minAmount_;

        _mint(ITTGRegistrar(ttgRegistrar).vault(), minAmount_);

        emit ExcessEarnedMDistributed(msg.sender, minAmount_);
    }

    /// @inheritdoc IWM
    function startEarning() external {
        if (!_isApprovedEarner(msg.sender)) revert NotApprovedEarner(msg.sender);

        _startEarning(msg.sender);
    }

    /// @inheritdoc IWM
    function stopEarning() external {
        _stopEarning(msg.sender);
    }

    /// @inheritdoc IWM
    function stopEarning(address account_) external {
        if (_isApprovedEarner(account_)) revert IsApprovedEarner(account_);

        _stopEarning(account_);
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IERC20
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account].balance;
    }

    /// @inheritdoc IWM
    function isEarning(address account_) external view returns (bool) {
        return _balances[account_].isEarning;
    }

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
                ? _YIELD_TOKEN_UNIT
                : (_YIELD_TOKEN_UNIT * IERC20(yieldToken).balanceOf(address(this))) / totalSupply;
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
     * @param shares_    The amount of shares to be transferred.
     */
    function _transfer(address sender_, address receiver_, uint256 shares_) internal override {
        uint128 currentYieldTokenIndex_ = IContinuousIndexing(yieldToken).currentIndex();
        uint256 totalEarnedMToBurn_;

        // TODO: implement unchecked maths and rounding
        // TODO: safe cast shares_ to uint240 or uint112
        if (sender_ != address(0)) {
            WMBalance storage senderBalance_ = _balances[sender_];

            // If sender is earning, capture the earned M tokens and update the index
            if (senderBalance_.isEarning) {
                uint240 senderEarnedM = _getPresentAmountRoundedDown(
                    uint112(senderBalance_.balance),
                    currentYieldTokenIndex_ - senderBalance_.latestIndex
                );

                senderBalance_.earned += _previewDeposit(senderEarnedM);
                senderBalance_.latestIndex = currentYieldTokenIndex_;

                totalEarnedM += senderEarnedM;

                uint256 totalBalance_ = senderBalance_.balance + senderBalance_.earned;
                _hasEnoughBalance(sender_, totalBalance_, shares_);

                if (shares_ > senderBalance_.earned) {
                    uint256 balanceDiff_ = shares_ - senderBalance_.earned;
                    senderBalance_.balance -= balanceDiff_;

                    if (receiver_ == address(0)) {
                        totalEarnedMToBurn_ = senderBalance_.earned;
                        totalSupply -= balanceDiff_;
                    }

                    delete senderBalance_.earned;
                } else {
                    senderBalance_.earned -= shares_;

                    if (receiver_ == address(0)) {
                        totalSupply -= shares_;
                    }
                }
            } else {
                _hasEnoughBalance(sender_, senderBalance_.balance, shares_);
                senderBalance_.balance -= shares_;
            }
        }

        if (receiver_ != address(0)) {
            WMBalance storage receiverBalance_ = _balances[receiver_];

            // If receiver is earning, capture the earned M tokens and update the index
            if (receiverBalance_.isEarning) {
                uint240 receiverEarnedM = _getPresentAmountRoundedDown(
                    uint112(receiverBalance_.balance),
                    currentYieldTokenIndex_ - receiverBalance_.latestIndex
                );

                receiverBalance_.earned += _previewDeposit(receiverEarnedM);
                receiverBalance_.latestIndex = currentYieldTokenIndex_;

                totalEarnedM += receiverEarnedM;
            }

            receiverBalance_.balance += shares_;
            totalSupply += shares_;
        }

        emit Transfer(sender_, receiver_, shares_);

        latestIndex = currentYieldTokenIndex_;
    }

    /**
     * @dev   Starts earning for account.
     * @param account_ The account to start earning for.
     */
    function _startEarning(address account_) internal {
        WMBalance storage accountBalance_ = _balances[account_];

        // Account is already earning.
        if (accountBalance_.isEarning) return;

        emit StartedEarning(account_);

        accountBalance_.isEarning = true;
        accountBalance_.latestIndex = IContinuousIndexing(yieldToken).currentIndex();
    }

    /**
     * @dev   Stops earning for account.
     * @param account_ The account to stop earning for.
     */
    function _stopEarning(address account_) internal {
        WMBalance storage accountBalance_ = _balances[account_];

        // Account is currently not earning.
        if (!accountBalance_.isEarning) return;

        emit StoppedEarning(account_);

        delete accountBalance_.isEarning;
        delete accountBalance_.latestIndex;
    }

    /* ============ Internal View/Pure Functions ============ */

    /**
     * @dev    Returns the present amount (rounded down) given the principal amount and an index.
     * @param  principalAmount_ The principal amount.
     * @param  index_           An index.
     * @return The present amount rounded down.
     */
    function _getPresentAmountRoundedDown(uint112 principalAmount_, uint128 index_) internal pure returns (uint240) {
        return ContinuousIndexingMath.multiplyDown(principalAmount_, index_);
    }

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
                : (amountTokenToDeposit_ * _YIELD_TOKEN_UNIT) / exchangeRate();
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
                : (amountSharesToRedeem_ * exchangeRate()) / _YIELD_TOKEN_UNIT;
    }

    /**
     * @notice Checks if account has enough balance to transfer.
     * @param  account_ Address to check.
     * @param  balance_ Current balance of account. May account for the earned amount if account is earning.
     * @param  amount_  Amount to transfer.
     */
    function _hasEnoughBalance(address account_, uint256 balance_, uint256 amount_) internal view {
        if (balance_ < amount_) revert InsufficientBalance(account_, balance_, amount_);
    }

    /**
     * @dev    Checks if earner was approved by TTG.
     * @param  account_    The account to check.
     * @return True if approved, false otherwise.
     */
    function _isApprovedEarner(address account_) internal view returns (bool) {
        return
            TTGRegistrarReader.isEarnersListIgnored(ttgRegistrar) ||
            TTGRegistrarReader.isApprovedEarner(ttgRegistrar, account_);
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
