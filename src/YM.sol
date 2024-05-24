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
import { IYM } from "./interfaces/IYM.sol";

import { TTGRegistrarReader } from "./libs/TTGRegistrarReader.sol";

/**
 * @title YM token.
 * @author M^0 Labs
 * @notice Interest bearing YM token.
 */
contract YM is IYM, ERC20Extended {
    /* ============ Structs ============ */

    /**
     * @notice YM token balance struct.
     * @param  isEarning  True if the account is earning, false otherwise.
     * @param  balance    YM token balance which is equivalent to the amount of underlying M tokens earning M.
     * @param  earnedM    Earned M tokens.
     * @param  index      Latest recorded index of the earning account.
     */
    struct YMBalance {
        bool isEarning;
        uint240 balance;
        uint256 earnedM;
        uint128 index;
    }

    /* ============ Variables ============ */

    /// @inheritdoc IERC20
    uint256 public totalSupply;

    /// @inheritdoc IYM
    address public immutable mToken;

    /// @inheritdoc IYM
    address public immutable ttgRegistrar;

    /// @inheritdoc IYM
    address public immutable wMToken;

    /// @notice Dead address to send YM tokens to if caller is not on the earners list.
    address private constant _DEAD_ADDRESS = address(0x000000000000000000000000000000000000dEaD);

    /// @notice YM token balances.
    mapping(address account => YMBalance balance) internal _balances;

    /* ============ Modifiers ============ */

    /// @dev Modifier to check if caller is WM token.
    modifier onlyWM() {
        if (msg.sender != wMToken) revert NotWMToken();

        _;
    }

    /* ============ Constructor ============ */

    /**
     * @notice Constructs the YM token contract.
     * @param  mToken_       Address of the underlying M token.
     * @param  wMToken_      The wrapped M token address.
     * @param  ttgRegistrar_ Address of the TTG Registrar contract.
     */
    constructor(address mToken_, address wMToken_, address ttgRegistrar_) ERC20Extended("YM by M^0", "YM", 6) {
        if ((mToken = mToken_) == address(0)) revert ZeroMToken();
        if ((wMToken = wMToken_) == address(0)) revert ZeroWMToken();
        if ((ttgRegistrar = ttgRegistrar_) == address(0)) revert ZeroTTGRegistrar();
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IYM
    function mint(address account_, uint256 amount_) external onlyWM {
        _mint(account_, amount_);
    }

    /// @inheritdoc IYM
    function burn(address account, uint256 amount_) external onlyWM {
        _burn(account, amount_);
    }

    /// @inheritdoc IYM
    function distributeExcessEarnedM(uint256 amount_) external {
        if (!TTGRegistrarReader.isApprovedLiquidator(ttgRegistrar, msg.sender))
            revert NotApprovedLiquidator(msg.sender);

        YMBalance storage deadBalance_ = _balances[_DEAD_ADDRESS];
        uint128 newIndex_ = IContinuousIndexing(mToken).updateIndex();

        _updateIndex(deadBalance_, newIndex_);

        if (amount_ > deadBalance_.earnedM) revert InsufficientExcessEarnedM(deadBalance_.earnedM, amount_);

        uint256 shares_ = _earnedMToShares(deadBalance_, amount_);

        // Safe to use unchecked here since we check above that the dead address has enough balance.
        unchecked {
            deadBalance_.balance -= uint240(shares_);
            deadBalance_.earnedM -= amount_;
        }

        _mint(ITTGRegistrar(ttgRegistrar).vault(), shares_);

        emit ExcessEarnedMDistributed(msg.sender, amount_, shares_);
    }

    /// @inheritdoc IYM
    function stopEarning() external {
        _stopEarning(msg.sender);
    }

    /// @inheritdoc IYM
    function stopEarning(address account_) external {
        if (IMToken(mToken).isEarning(account_)) revert IsEarning(account_);

        _stopEarning(account_);
    }

    /* ============ External View/Pure Functions ============ */

    /// @inheritdoc IYM
    function balanceOfEarnedM(address account_) external view returns (uint256) {
        return _balances[account_].earnedM;
    }

    /// @inheritdoc IERC20
    function balanceOf(address account_) public view returns (uint256) {
        return _balances[account_].balance;
    }

    /* ============ Internal Interactive Functions ============ */

    /**
     * @dev   Mints `shares_` amount to `receiver_`.
     * @param receiver_  Address to mint to.
     * @param shares_    Amount of shares to mint.
     */
    function _mint(address receiver_, uint256 shares_) internal {
        _transfer(address(0), receiver_, shares_);
    }

    /**
     * @dev   Burns `shares_` amount from `account_`.
     * @param account_   Address to burn from.
     * @param shares_    Amount of shares to burn.
     */
    function _burn(address account_, uint256 shares_) internal returns (uint256) {
        _transfer(account_, address(0), shares_);
    }

    /**
     * @dev   Internal ERC20 transfer function.
     * @param sender_    The sender's address.
     * @param receiver_  The receiver's address.
     * @param shares_    The amount of shares to be transferred.
     */
    function _transfer(address sender_, address receiver_, uint256 shares_) internal override {
        // Update M token index to update the amount of M tokens earned.
        uint128 newIndex_ = IContinuousIndexing(mToken).updateIndex();

        if (sender_ != address(0)) {
            YMBalance storage senderBalance_ = _balances[sender_];

            if (balanceOf(sender_) < shares_) revert InsufficientBalance(sender_, balanceOf(sender_), shares_);

            _updateIndex(senderBalance_, newIndex_);

            // Safe to use unchecked here since we check above that the sender has enough balance.
            unchecked {
                _balances[sender_].balance -= uint240(shares_);
                senderBalance_.earnedM -= _sharesToEarnedM(senderBalance_, shares_);
            }
        } else {
            totalSupply += shares_;
        }

        if (receiver_ != address(0)) {
            YMBalance storage receiverBalance_ = _balances[receiver_];

            // Set initial index for a new YM token holder.
            if (sender_ == address(0) && !receiverBalance_.isEarning) {
                _updateIndex(receiverBalance_, newIndex_);
                receiverBalance_.isEarning = true;
            }

            _updateIndex(receiverBalance_, newIndex_);

            _balances[receiver_].balance += uint240(shares_);
            receiverBalance_.earnedM += _sharesToEarnedM(receiverBalance_, shares_);
        } else {
            totalSupply -= shares_;
        }

        emit Transfer(sender_, receiver_, shares_);
    }

    /**
     * @dev   Stops earning for account.
     * @param account_ The account to stop earning for.
     */
    function _stopEarning(address account_) internal {
        YMBalance storage accountBalance_ = _balances[account_];

        if (!accountBalance_.isEarning) return;

        uint128 newIndex_ = IContinuousIndexing(mToken).updateIndex();

        accountBalance_.isEarning = false;
        _updateIndex(accountBalance_, newIndex_);

        emit StoppedEarning(account_);
    }

    /**
     * @dev   Updates the amount of earned M tokens for an account.
     * @param accountBalance_ Account balance struct to update.
     * @param newIndex_       New index to update to.
     */
    function _updateIndex(YMBalance storage accountBalance_, uint128 newIndex_) internal {
        // If index is 0, it means that the account is not earning yet.
        if (accountBalance_.index == 0) {
            accountBalance_.earnedM += _getPresentAmountRoundedDown(
                uint112(accountBalance_.balance),
                newIndex_ - accountBalance_.index
            );
        }

        accountBalance_.index = newIndex_;
    }

    /* ============ Internal View/Pure Functions ============ */

    /**
     * @notice Returns the amount of YM shares for a given amount of underlying earned M tokens.
     * @param  accountBalance_ Account balance struct to compute YM shares for.
     * @param  amount_         Amount of earned M tokens to comvert.
     * @return Amount of YM shares for the given amount of earned M tokens.
     */
    function _earnedMToShares(YMBalance storage accountBalance_, uint256 amount_) internal view returns (uint256) {
        // Return balance if converting all earned M tokens of account.
        if (amount_ == accountBalance_.earnedM) return accountBalance_.balance;

        // shares = (earnedMTokens * accountBalance) / accountEarnedM
        return amount_ == 0 ? amount_ : (amount_ * accountBalance_.balance) / accountBalance_.earnedM;
    }

    /**
     * @notice Returns the amount of underlying earned M tokens for a given amount of YM shares.
     * @param  accountBalance_ Account balance struct to compute earned M for.
     * @param  shares_         Amount of YM shares to convert.
     * @return Amount of earned M tokens for the given amount of YM shares.
     */
    function _sharesToEarnedM(YMBalance storage accountBalance_, uint256 shares_) internal view returns (uint256) {
        // Return earnedM if converting all YM shares of account.
        if (shares_ == accountBalance_.balance) return accountBalance_.earnedM;

        // earnedMTokens = (shares * accountEarnedM) / accountBalance
        return shares_ == 0 ? shares_ : (shares_ * accountBalance_.earnedM) / accountBalance_.balance;
    }

    /**
     * @dev    Returns the present amount (rounded down) given the principal amount and an index.
     * @param  principalAmount_ The principal amount.
     * @param  index_           An index.
     * @return The present amount rounded down.
     */
    function _getPresentAmountRoundedDown(uint112 principalAmount_, uint128 index_) internal pure returns (uint240) {
        return ContinuousIndexingMath.multiplyDown(principalAmount_, index_);
    }
}
