// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IERC20 } from "../lib/common/src/interfaces/IERC20.sol";
import { ERC20Extended } from "../lib/common/src/ERC20Extended.sol";

import { IMToken } from "../lib/protocol/src/interfaces/IMToken.sol";

import { IWM } from "./interfaces/IWM.sol";
import { IYM } from "./interfaces/IYM.sol";

import { TTGRegistrarReader } from "./libs/TTGRegistrarReader.sol";

/**
 * @title WM token wrapper with static balances.
 * @author M^0 Labs
 * @notice ERC5115 WM token.
 */
contract WM is IWM, ERC20Extended {
    /* ============ Variables ============ */

    /// @inheritdoc IERC20
    uint256 public totalSupply;
    /// @inheritdoc IWM
    address public immutable mToken;

    /// @inheritdoc IWM
    address public immutable ttgRegistrar;

    /// @inheritdoc IWM
    address public immutable yMToken;

    /// @notice Dead address to send YM tokens to if caller is not on the earners list.
    address private constant _DEAD_ADDRESS = address(0x000000000000000000000000000000000000dEaD);

    /// @notice WM token balances.
    mapping(address account => uint256 balance) internal _balances;

    /* ============ Constructor ============ */

    /**
     * @notice Constructs the WM token contract.
     * @param  mToken_       Address of the underlying M token.
     * @param  yMToken_      Address of the Yield M token.
     * @param  ttgRegistrar_ Address of the TTG Registrar contract.
     */
    constructor(address mToken_, address yMToken_, address ttgRegistrar_) ERC20Extended("WM by M^0", "WM", 6) {
        if ((mToken = mToken_) == address(0)) revert ZeroMToken();
        if ((yMToken = yMToken_) == address(0)) revert ZeroYMToken();
        if ((ttgRegistrar = ttgRegistrar_) == address(0)) revert ZeroTTGRegistrar();
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IWM
    function deposit(address receiver_, uint256 amount_) external payable returns (uint256) {
        if (amount_ == 0) revert ZeroDeposit();

        IERC20(mToken).transferFrom(msg.sender, address(this), amount_);

        bool isEarning_ = _isEarning(msg.sender);

        // WM shares are minted 1:1 to the amount of M tokens deposited.
        _mint(receiver_, amount_);

        IYM(yMToken).mint(isEarning_ ? receiver_ : _DEAD_ADDRESS, amount_);

        emit Deposit(msg.sender, receiver_, amount_, amount_, isEarning_);

        return amount_;
    }

    /// @inheritdoc IWM
    function redeem(address receiver_, uint256 shares_) external returns (uint256) {
        if (shares_ == 0) revert ZeroRedeem();

        IYM yMToken_ = IYM(yMToken);

        uint256 balanceOfEarnedM_ = yMToken_.balanceOfEarnedM(msg.sender);

        // WM shares are burned 1:1 to the amount of M tokens withdrawn.
        _burn(msg.sender, shares_);
        yMToken_.burn(msg.sender, shares_);

        uint256 redeemAmount_ = shares_ + (balanceOfEarnedM_ - yMToken_.balanceOfEarnedM(msg.sender));

        IERC20(mToken).transfer(receiver_, redeemAmount_);

        emit Redeem(msg.sender, receiver_, shares_, redeemAmount_);

        return redeemAmount_;
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IWM
    function totalEarnedM() external view returns (uint256) {
        // Safe to use unchecked here since the balance of M tokens
        // will always be greater than or equal to the amount of WM tokens minted.
        unchecked {
            return IERC20(mToken).balanceOf(address(this)) - totalSupply;
        }
    }

    /// @inheritdoc IERC20
    function balanceOf(address account_) public view returns (uint256) {
        return _balances[account_];
    }

    /* ============ Internal Interactive Functions ============ */

    /**
     * @dev   Burns `shares_` amount from `account_`.
     * @dev   WM shares are burned 1:1 to the amount of M tokens withdrawn.
     * @param account_ Address to burn from.
     * @param shares_  Amount of shares to burn.
     */
    function _burn(address account_, uint256 shares_) internal {
        _transfer(account_, address(0), shares_);
    }

    /**
     * @dev   Mints `shares_` amount to `receiver_`.
     * @dev   WM shares are minted 1:1 to the amount of M tokens deposited.
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
        if (sender_ != address(0)) {
            if (balanceOf(sender_) < shares_) revert InsufficientBalance(sender_, balanceOf(sender_), shares_);

            // Safe to use unchecked here since we check above that the sender has enough balance.
            unchecked {
                _balances[sender_] -= shares_;
            }
        } else {
            totalSupply += shares_;
        }

        if (receiver_ != address(0)) {
            _balances[receiver_] += shares_;
        } else {
            // Safe to use unchecked here since we can burn at most
            // the balance of the sender which can't exceed the total supply.
            unchecked {
                totalSupply -= shares_;
            }
        }

        emit Transfer(sender_, receiver_, shares_);
    }

    /* ============ Internal View/Pure Functions ============ */

    /**
     * @dev    Checks if account is an earner.
     * @param  account_    The account to check.
     * @return True if earning, false otherwise.
     */
    function _isEarning(address account_) internal view returns (bool) {
        return IMToken(mToken).isEarning(account_);
    }
}
