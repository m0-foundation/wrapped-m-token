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
    address public immutable wrapper;

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
    error ZeroWrapper();
    error NotApprovedEarner();
    error IsApprovedEarner();
    error NotWrapper();

    modifier onlyWrapper() {
        if (msg.sender != wrapper) revert NotWrapper();

        _;
    }

    /* ============ Constructor ============ */

    constructor(address ttgRegistrar_, address mToken_, address wrapper_) ERC20Extended("WM by M^0", "WM", 6) {
        if ((ttgRegistrar = ttgRegistrar_) == address(0)) revert ZeroTTGRegistrar();
        if ((mToken = mToken_) == address(0)) revert ZeroMToken();
        if ((wrapper = wrapper_) == address(0)) revert ZeroWrapper();
    }

    /* ============ Interactive Functions ============ */

    /// 1:1 wrap
    function mint(address account_, uint256 amount_) external onlyWrapper {
        _mint(account_, amount_);
    }

    // 1:1 unwrap
    function burn(address account_, uint256 amount_) external onlyWrapper {
        _burn(account_, amount_);
    }

    function startEarning(address account) external {
        if (!_isApprovedWEarner(account)) revert NotApprovedEarner();

        _startEarning(account);
    }

    function stopEarning(address account_) external {
        if (_isApprovedWEarner(account_)) revert IsApprovedEarner();

        _stopEarning(account_);
    }

    /* ============ View/Pure Functions ============ */

    function totalEarningSupply() public view returns (uint256) {
        return principalOfTotalEarningSupply * currentIndex();
    }

    function balanceOf(address account_) external view returns (uint256 balance_) {
        return _balances[account_];
    }

    function currentIndex() public view returns (uint128) {
        return IMToken(mToken).currentIndex();
    }

    function excessOfM() external view returns (uint256) {
        uint256 totalSupply_ = totalNonEarningSupply + totalEarningSupply();

        return IMToken(mToken).balanceOf(wrapper) - totalSupply_;
    }

    /* ============ Internal Interactive Functions ============ */

    function _accrueRewards(address account_) internal {
        if (!_isEarning[account_]) return;

        uint256 currentIndex_ = currentIndex();

        if (_lastAccrueIndices[account_] == 0) {
            _lastAccrueIndices[account_] = currentIndex_;
            return;
        }

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
    }

    function _startEarning(address account_) internal {
        if (_isEarning[account_]) return;

        _isEarning[account_] = true;
        _lastAccrueIndices[account_] = currentIndex();

        _earningPrincipals[account_] = _balances[account_] / currentIndex();
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
        _balances[account_] += amount_;
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

    // function _claim(address earner_, uint256 amount_) internal {
    //     _accrueRewards(earner_);

    //     address claimer_ = _claimers[earner_];

    //     // _mint(claimer_, amount_);
    //     _balances[claimer_] += amount_; // do not update principal if claimer is an earner?
    // }

    /* ============ Internal View/Pure Functions ============ */

    function _isApprovedWEarner(address account_) internal view returns (bool) {
        return ITTGRegistrar(ttgRegistrar).listContains("wm_earners_list", account_);
    }
}
