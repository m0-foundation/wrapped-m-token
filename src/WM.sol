// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import {ERC20Extended} from "../lib/common/src/ERC20Extended.sol";
import {IERC20} from "../lib/common/src/interfaces/IERC20.sol";
import {IMToken} from "../lib/protocol/src/interfaces/IMToken.sol";

interface ITTGRegistrar {
    function listContains(bytes32 list, address account) external view returns (bool);
}

contract WM is IERC20, ERC20Extended {
    /* ============ Variables ============ */

    address public immutable ttgRegistrar;
    address public immutable mToken;
    address public immutable distributionVault; // distribute all excess of MToken

    // Totals
    uint256 public principalOfTotalEarningSupply;
    uint256 public totalNonEarningSupply;
    uint256 public totalSupply;

    // TODO: storage slots is subject to massive optimization here
    mapping(address account => uint256 balance) internal _balances; // for earners and non-earners

    mapping(address account => bool isEarning) internal _isEarning;

    // Earners only
    mapping(address account => uint256 reward) internal _rewards;

    mapping(address account => uint256 principal) internal _earningPrincipals;
    mapping(address account => uint256 index) internal _lastAccrueIndices;

    /* ============ Errors ============ */

    error ZeroTTGRegistrar();
    error ZeroMToken();
    error ZeroDistributionVault();
    error NotApprovedEarner();
    error IsApprovedEarner();
    error NotWrapper();

    /* ============ Constructor ============ */

    constructor(address ttgRegistrar_, address mToken_, address distributionVault_)
        ERC20Extended("WM by M^0", "WM", 6)
    {
        if ((ttgRegistrar = ttgRegistrar_) == address(0)) revert ZeroTTGRegistrar();
        if ((mToken = mToken_) == address(0)) revert ZeroMToken();
        if ((distributionVault = distributionVault_) == address(0)) revert ZeroDistributionVault();
    }

    /* ============ Interactive Functions ============ */

    function wrap(address account_, uint256 amount_) external {
        IMToken(mToken).transferFrom(msg.sender, address(this), amount_);
        _mint(account_, amount_);
    }

    function unwrap(address account_, uint256 amount_) external {
        _burn(msg.sender, amount_);
        IMToken(mToken).transfer(account_, amount_);
    }

    function startEarning(address account) external {
        if (!_isApprovedWEarner(account)) revert NotApprovedEarner();

        _startEarning(account);
    }

    function stopEarning(address account_) external {
        if (_isApprovedWEarner(account_)) revert IsApprovedEarner();

        _stopEarning(account_);
    }

    // TODO add claim forwarding logic instead of recipient
    function claimRewards(address recipient) external {
        _accrueRewards(msg.sender);

        uint256 claimableAmount_ = _rewards[msg.sender];

        if (claimableAmount_ == 0) return;

        _rewards[msg.sender] = 0;

        IMToken(mToken).transfer(recipient, claimableAmount_);
    }

    function claimExcessToDistributionVault() external {
        IMToken(mToken).transfer(distributionVault, excessOfM());
    }

    /* ============ View/Pure Functions ============ */

    function balanceOf(address account_) external view returns (uint256 balance_) {
        return _balances[account_];
    }

    function totalEarningSupply() public view returns (uint256) {
        return principalOfTotalEarningSupply * currentIndex();
    }

    function currentIndex() public view returns (uint128) {
        return IMToken(mToken).currentIndex();
    }

    function excessOfM() public view returns (uint256) {
        uint256 totalProjectedSupply_ = totalNonEarningSupply + totalEarningSupply();

        return IMToken(mToken).balanceOf(address(this)) - totalProjectedSupply_;
    }

    /* ============ Internal Interactive Functions ============ */

    function _accrueRewards(address account_) internal {
        if (!_isEarning[account_]) return;

        uint256 currentIndex_ = currentIndex();

        uint256 newReward_ = _earningPrincipals[account_] * (currentIndex_ - _lastAccrueIndices[account_]);
        _rewards[account_] += newReward_;
        _lastAccrueIndices[account_] = currentIndex_;
    }

    function _mint(address recipient_, uint256 amount_) internal {
        _accrueRewards(recipient_);

        if (_isEarning[recipient_]) {
            _addEarningAmount(recipient_, amount_);
        } else {
            _addNonEarningAmount(recipient_, amount_);
        }

        totalSupply += amount_;
    }

    function _burn(address account_, uint256 amount_) internal {
        _accrueRewards(account_);

        if (_isEarning[account_]) {
            _subtractEarningAmount(account_, amount_);
        } else {
            _subtractNonEarningAmount(account_, amount_);
        }

        totalSupply -= amount_;
    }

    function _startEarning(address account_) internal {
        if (_isEarning[account_]) return;

        // Account update
        _isEarning[account_] = true;
        _lastAccrueIndices[account_] = currentIndex();

        uint256 amount_ = _balances[account_];
        uint256 principalAmount_ = amount_ / currentIndex();

        _earningPrincipals[account_] = principalAmount_;

        // Totals update
        principalOfTotalEarningSupply += principalAmount_;
        totalNonEarningSupply -= amount_;
    }

    function _stopEarning(address account_) internal {
        if (!_isEarning[account_]) return;

        _accrueRewards(account_);

        // Totals update
        uint256 principalAmount_ = _earningPrincipals[account_];

        totalNonEarningSupply += principalAmount_ * currentIndex();
        principalOfTotalEarningSupply -= principalAmount_;

        // Account update
        delete _earningPrincipals[account_];
        delete _lastAccrueIndices[account_];
        _isEarning[account_] = false;
    }

    function _addEarningAmount(address account_, uint256 amount_) internal {
        _balances[account_] += amount_;

        uint256 principalAmount_ = amount_ / currentIndex();

        _earningPrincipals[account_] += principalAmount_;
        principalOfTotalEarningSupply += principalAmount_;
    }

    function _addNonEarningAmount(address account_, uint256 amount_) internal {
        // Account update
        _balances[account_] += amount_;

        // Totals update
        totalNonEarningSupply += amount_;
    }

    function _subtractEarningAmount(address account_, uint256 amount_) internal {
        uint256 principalAmount_ = amount_ / currentIndex();

        // Account update
        _balances[account_] -= amount_;
        _earningPrincipals[account_] -= principalAmount_;

        // Totals update
        principalOfTotalEarningSupply -= principalAmount_;
    }

    function _subtractNonEarningAmount(address account_, uint256 amount_) internal {
        // Account update
        _balances[account_] -= amount_;

        // Totals update
        totalNonEarningSupply -= amount_;
    }

    function _transfer(address sender_, address recipient_, uint256 amount_) internal override {
        _accrueRewards(sender_);
        _accrueRewards(recipient_);

        if (_isEarning[sender_]) {
            _subtractEarningAmount(sender_, amount_);
        } else {
            _subtractNonEarningAmount(sender_, amount_);
        }

        if (_isEarning[recipient_]) {
            _addEarningAmount(recipient_, amount_);
        } else {
            _addNonEarningAmount(recipient_, amount_);
        }
    }

    /* ============ Internal View/Pure Functions ============ */

    function _isApprovedWEarner(address account_) internal view returns (bool) {
        return ITTGRegistrar(ttgRegistrar).listContains("wm_earners_list", account_);
    }
}
