// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;
import { console2 } from "../lib/forge-std/src/Test.sol";

import { IERC20 } from "../lib/common/src/interfaces/IERC20.sol";
import { ERC20Extended } from "../lib/common/src/ERC20Extended.sol";

import { IContinuousIndexing } from "../lib/protocol/src/interfaces/IContinuousIndexing.sol";
import { IMToken } from "../lib/protocol/src/interfaces/IMToken.sol";

import { ContinuousIndexingMath } from "../lib/protocol/src/libs/ContinuousIndexingMath.sol";

import { IWM } from "./interfaces/IWM.sol";

import { TTGRegistrarReader } from "./libs/TTGRegistrarReader.sol";

/**
 * @title WM token wrapper.
 * @author M^0 Labs
 * @notice WM allows M token holders to wrap their M tokens and start using across the M^0 ecosystem.
 *         Earners and non earners can use this wrapper. In order for this token to be non-rebasing,
 *         earners need to claim their earned M tokens
 */
contract WM is IWM, ERC20Extended {
    /* ============ Structs ============ */

    /**
     * @notice WM token balance struct.
     * @param  isEarning      True if the account is earning, false otherwise.
     * @param  isAutoClaiming True if the account has enabled auto claiming, false otherwise.
     * @param  balance        WM token balance which is equivalent to the amount of underlying M tokens.
     * @param  index          Latest recorded index of the earning account. 0 if not earning.
     */
    struct WMBalance {
        bool isEarning;
        bool isAutoClaiming;
        uint112 balance;
        uint128 index;
    }

    /* ============ Variables ============ */

    /// @inheritdoc IWM
    uint128 public index;

    /// @inheritdoc IWM
    uint112 public totalEarningSupply;

    /// @inheritdoc IWM
    uint112 public totalNonEarningSupply;

    /// @inheritdoc IWM
    address public immutable mToken;

    /// @inheritdoc IWM
    address public immutable ttgRegistrar;

    /// @notice WM token balances.
    mapping(address account => WMBalance balance) internal _balances;

    /* ============ Modifiers ============ */

    /// @dev Modifier to check if caller is the claimer address approved by TTG.
    modifier onlyClaimer() {
        if (!TTGRegistrarReader.isApprovedClaimer(ttgRegistrar, msg.sender)) revert NotClaimer(msg.sender);

        _;
    }

    /// @dev Modifier to check if caller is the manager address approved by TTG.
    modifier onlyManager() {
        if (!TTGRegistrarReader.isApprovedManager(ttgRegistrar, msg.sender)) revert NotManager(msg.sender);

        _;
    }

    /* ============ Constructor ============ */

    /**
     * @notice Constructs the WM token contract.
     * @param  mToken_       Address of the underlying M token.
     * @param  ttgRegistrar_ Address of the TTG Registrar contract.
     */
    constructor(address mToken_, address ttgRegistrar_) ERC20Extended("WM by M^0", "WM", 6) {
        if ((mToken = mToken_) == address(0)) revert ZeroMToken();
        if ((ttgRegistrar = ttgRegistrar_) == address(0)) revert ZeroTTGRegistrar();

        index = IContinuousIndexing(mToken).updateIndex();
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IWM
    function deposit(address receiver_, uint256 amount_) external returns (uint256) {
        if (amount_ == 0) revert ZeroDeposit();

        IERC20(mToken).transferFrom(msg.sender, address(this), amount_);

        // WM shares are minted 1:1 to the amount of M tokens deposited.
        _mint(receiver_, amount_);

        emit Deposit(msg.sender, receiver_, amount_);

        return amount_;
    }

    /// @inheritdoc IWM
    function redeem(address receiver_, uint256 shares_) external returns (uint256) {
        if (shares_ == 0) revert ZeroRedeem();

        // WM shares are burned 1:1 to the amount of M tokens withdrawn.
        _burn(msg.sender, shares_);

        IERC20(mToken).transfer(receiver_, shares_);

        emit Redeem(msg.sender, receiver_, shares_);

        return shares_;
    }

    /// @inheritdoc IWM
    function claim(address receiver_) external returns (uint256) {
        if (!_isEarning(msg.sender)) revert IsNotEarning(msg.sender);

        uint256 claimedAmount_;

        if (msg.sender != receiver_) {
            claimedAmount_ = _claim(msg.sender, msg.sender, receiver_);
        } else {
            claimedAmount_ = _claim(msg.sender, msg.sender);
        }

        return claimedAmount_;
    }

    /// @inheritdoc IWM
    function claim(address account_, address receiver_) external onlyClaimer returns (uint256) {
        if (!_isEarning(account_)) revert IsNotEarning(account_);

        uint256 claimedAmount_;

        if (account_ != receiver_) {
            claimedAmount_ = _claim(msg.sender, account_, receiver_);
        } else {
            claimedAmount_ = _claim(msg.sender, account_);
        }

        return claimedAmount_;
    }

    /// @inheritdoc IWM
    function setAutoClaiming(bool enabled_) external {
        _setAutoClaiming(msg.sender, msg.sender, enabled_);
    }

    /// @inheritdoc IWM
    function setAutoClaiming(address account_, bool enabled_) external onlyManager {
        _setAutoClaiming(msg.sender, account_, enabled_);
    }

    /// @inheritdoc IWM
    function startEarning() external {
        _startEarning(msg.sender, msg.sender);
    }

    /// @inheritdoc IWM
    function startEarning(address account_) external onlyManager {
        if (!_isManaged(account_)) revert IsNotManaged(account_);

        _startEarning(msg.sender, account_);
    }

    /// @inheritdoc IWM
    function stopEarning() external {
        _stopEarning(msg.sender, msg.sender);
    }

    /// @inheritdoc IWM
    function stopEarning(address account_) external {
        if (IMToken(mToken).isEarning(account_)) revert IsEarning(account_);

        _stopEarning(msg.sender, account_);
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc IWM
    function totalExcessEarnedM() external view returns (uint112) {
        return _getEarnedM(totalNonEarningSupply, index, IContinuousIndexing(mToken).latestIndex());
    }

    /// @inheritdoc IERC20
    function totalSupply() external view returns (uint256) {
        return totalNonEarningSupply + totalEarningSupply;
    }

    /// @inheritdoc IERC20
    function balanceOf(address account_) public view returns (uint256) {
        return _balances[account_].balance;
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
                _balances[sender_].balance -= uint112(shares_);
            }
        } else {
            // TODO: need to update global index
            if (_isEarning(receiver_)) {
                totalEarningSupply += uint112(shares_);
            } else {
                totalNonEarningSupply += uint112(shares_);
            }
        }

        if (receiver_ != address(0)) {
            _balances[receiver_].balance += uint112(shares_);
        } else {
            // Safe to use unchecked here since we can burn at most
            // the balance of the sender which can't exceed the total supply.
            unchecked {
                if (_isEarning(sender_)) {
                    totalEarningSupply -= uint112(shares_);
                } else {
                    totalNonEarningSupply -= uint112(shares_);
                }
            }
        }

        emit Transfer(sender_, receiver_, shares_);
    }

    /**
     * @dev    Claim `account_` earned M.
     * @param  caller_  The address that called the function.
     * @param  account_ The account to claim for.
     * @return Amount of M tokens claimed.
     */
    function _claim(address caller_, address account_) internal returns (uint112) {
        WMBalance storage accountBalance_ = _balances[account_];

        // Update M token index to update the amount of M tokens earned.
        uint128 newIndex_ = IContinuousIndexing(mToken).updateIndex();
        uint112 accountEarnedM_ = _getEarnedM(accountBalance_.balance, accountBalance_.index, newIndex_);

        index = newIndex_;
        accountBalance_.index = newIndex_;
        accountBalance_.balance += accountEarnedM_;
        totalEarningSupply += accountEarnedM_;

        emit Claimed(caller_, account_, account_, accountEarnedM_);

        return accountEarnedM_;
    }

    /**
     * @dev    Claim `account_` earned M and transfer to `receiver_`.
     * @param  caller_   The address that called the function.
     * @param  account_  The account to claim for.
     * @param  receiver_ The address to send the claimed M tokens to.
     * @return Amount of M tokens claimed.
     */
    function _claim(address caller_, address account_, address receiver_) internal returns (uint112) {
        WMBalance storage accountBalance_ = _balances[account_];
        WMBalance storage receiverBalance_ = _balances[receiver_];

        // Update M token index to update the amount of M tokens earned.
        uint128 newIndex_ = IContinuousIndexing(mToken).updateIndex();
        uint112 accountEarnedM_ = _getEarnedM(accountBalance_.balance, accountBalance_.index, newIndex_);

        // If receiver is earner, need to update their index and claim their earned M.
        if (_isEarning(receiver_)) {
            uint112 receiverEarnedM_ = _getEarnedM(receiverBalance_.balance, receiverBalance_.index, newIndex_);

            receiverBalance_.index = newIndex_;
            receiverBalance_.balance += receiverEarnedM_;
            totalEarningSupply += receiverEarnedM_;

            emit Claimed(caller_, receiver_, receiver_, receiverEarnedM_);
        }

        index = newIndex_;
        receiverBalance_.balance += accountEarnedM_;
        totalEarningSupply += accountEarnedM_;

        emit Claimed(caller_, account_, receiver_, accountEarnedM_);

        return accountEarnedM_;
    }

    /**
     * @dev   Sets auto claiming for account.
     * @param caller_  The account that called the function.
     * @param account_ The account to set auto claiming for.
     * @param enabled_ True to enable auto claiming, false to disable.
     */
    function _setAutoClaiming(address caller_, address account_, bool enabled_) internal {
        _balances[account_].isAutoClaiming = enabled_;

        emit AutoClaimingSet(caller_, account_, enabled_);
    }
    /**
     * @dev   Starts earning for account.
     * @param caller_  The account that called the function.
     * @param account_ The account to start earning for.
     */
    function _startEarning(address caller_, address account_) internal {
        address earner_ = caller_ == account_ ? caller_ : account_;

        if (!IMToken(mToken).isEarning(earner_)) revert IsNotEarning(earner_);

        // Return early if account is already earning.
        if (_isEarning(account_)) return;

        WMBalance storage accountBalance_ = _balances[account_];

        accountBalance_.index = IContinuousIndexing(mToken).updateIndex();
        accountBalance_.isEarning = true;

        emit StartedEarning(caller_, account_);
    }

    /**
     * @dev   Stops earning for account.
     * @param caller_  The account that called the function.
     * @param account_ The account to stop earning for.
     */
    function _stopEarning(address caller_, address account_) internal {
        if (!_isEarning(account_)) return;

        // Claim earned M tokens before stopping earning.
        _claim(caller_, account_);

        // Reset account's earning state.
        delete _balances[account_].index;
        delete _balances[account_].isEarning;

        emit StoppedEarning(caller_, account_);
    }

    /* ============ Internal View/Pure Functions ============ */

    /**
     * @dev    Checks if account is an earner.
     * @param  account_    The account to check.
     * @return True if earning, false otherwise.
     */
    function _isEarning(address account_) internal view returns (bool) {
        return _balances[account_].isEarning;
    }

    /**
     * @dev    Checks if `account_` is on managed by the WM manager.
     * @param  account_ The account to check.
     * @return True if approved, false otherwise.
     */
    function _isManaged(address account_) internal view returns (bool) {
        return
            TTGRegistrarReader.isManagerListIgnored(ttgRegistrar) ||
            TTGRegistrarReader.isOnManagerList(ttgRegistrar, account_);
    }

    /**
     * @dev   Calculates the amount of earned M tokens.
     * @param balance_  The balance of the account.
     * @param index_    The latest recorded index of the account.
     * @param newIndex_ The current M token index.
     * @return The amount of earned M tokens.
     */
    function _getEarnedM(uint112 balance_, uint128 index_, uint128 newIndex_) internal pure returns (uint112) {
        // earnedM = principalBalance * deltaIndex
        return uint112(_getPresentAmount(_getPrincipalAmount(balance_, index_), newIndex_ - index_));
    }

    /**
     * @dev    Returns the present amount (rounded down) given the principal amount and an index.
     *         All present amounts are rounded down in favor of the protocol, since they are assets.
     * @param  principalAmount_ The principal amount.
     * @param  index_           An index
     * @return The present amount.
     */
    function _getPresentAmount(uint112 principalAmount_, uint128 index_) internal pure returns (uint240) {
        return ContinuousIndexingMath.multiplyDown(principalAmount_, index_);
    }

    /**
     * @dev    Returns the principal amount given the present amount, using the current index.
     * @param  presentAmount_ The present amount.
     * @param  index_         An index.
     * @return The principal amount rounded down.
     */
    function _getPrincipalAmount(uint240 presentAmount_, uint128 index_) internal pure returns (uint112) {
        return ContinuousIndexingMath.divideDown(presentAmount_, index_);
    }
}
