// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { UIntMath } from "../lib/common/src/libs/UIntMath.sol";

import { ERC20Extended } from "../lib/common/src/ERC20Extended.sol";

import { IMTokenLike } from "./interfaces/IMTokenLike.sol";
import { IRegistrarLike } from "./interfaces/IRegistrarLike.sol";
import { IWrappedM } from "./interfaces/IWrappedM.sol";

contract WrappedM is IWrappedM, ERC20Extended {
    /* ============ Variables ============ */

    uint56 internal constant _EXP_SCALED_ONE = 1e12;

    bytes32 internal constant _EARNERS_LIST = "wm_earners";
    bytes32 internal constant _EARNING_CLAIMER_PREFIX = "wm_earning_claimer";

    address public immutable registrar;
    address public immutable mToken;

    // Totals
    uint256 public principalOfTotalEarningSupply;
    uint256 public totalNonEarningSupply;
    uint256 public totalSupply;

    mapping(address account => uint256 balance) internal _balances; // for earners and non-earners

    // Bitpack
    mapping(address account => bool isEarning) internal _isEarning;
    mapping(address account => uint256 principal) internal _earningPrincipals;
    mapping(address account => uint256 index) internal _lastAccrueIndices;

    /* ============ Constructor ============ */

    constructor(address mToken_, address registrar_) ERC20Extended("WM by M^0", "WM", 6) {
        if ((registrar = registrar_) == address(0)) revert ZeroRegistrar();
        if ((mToken = mToken_) == address(0)) revert ZeroMToken();
    }

    /* ============ Interactive Functions ============ */

    function wrap(address account_, uint256 amount_) external {
        IMTokenLike(mToken).transferFrom(msg.sender, address(this), amount_);
        _mint(account_, amount_);
    }

    function unwrap(address account_, uint256 amount_) external {
        _burn(msg.sender, amount_);
        IMTokenLike(mToken).transfer(account_, amount_);
    }

    function startEarning(address account_) external {
        if (!_isApprovedWEarner(account_)) revert NotApprovedEarner();

        _startEarning(account_);
    }

    function stopEarning(address account_) external {
        if (_isApprovedWEarner(account_)) revert IsApprovedEarner();

        _stopEarning(account_);
    }

    function claim(address earner_) external returns (uint256) {
        return _accrueYield(earner_);
    }

    function claimExcess() external {
        // TODO: check supply/token after this
        IMTokenLike(mToken).transfer(IRegistrarLike(registrar).vault(), excessOfM());
    }

    /* ============ View/Pure Functions ============ */

    function accruedYieldOf(address account_) public view returns (uint256) {
        if (!_isEarning[account_]) return 0;

        return
            _getPresentAmountRoundedDown(
                uint112(_earningPrincipals[account_]),
                currentIndex() - uint128(_lastAccrueIndices[account_])
            );
    }

    function balanceOf(address account_) external view returns (uint256) {
        return _balances[account_];
    }

    function totalEarningSupply() public view returns (uint256) {
        return _getPresentAmountRoundedDown(uint112(principalOfTotalEarningSupply), currentIndex());
    }

    function currentIndex() public view returns (uint128) {
        return IMTokenLike(mToken).currentIndex();
    }

    function excessOfM() public view returns (uint256) {
        uint256 totalProjectedSupply_ = totalNonEarningSupply + totalEarningSupply();

        return IMTokenLike(mToken).balanceOf(address(this)) - totalProjectedSupply_;
    }

    /* ============ Internal Interactive Functions ============ */

    function _accrueYield(address account_) internal returns (uint256 yield_) {
        if (!_isEarning[account_]) return 0;

        yield_ = accruedYieldOf(account_);

        _lastAccrueIndices[account_] = currentIndex();

        _balances[account_] += yield_;
        totalSupply += yield_;

        address claimer_ = _getClaimer(account_);

        if (claimer_ != address(0) && claimer_ != account_) {
            _transfer(account_, claimer_, yield_);
        }
    }

    function _mint(address recipient_, uint256 amount_) internal {
        _accrueYield(recipient_);

        if (_isEarning[recipient_]) {
            _addEarningAmount(recipient_, amount_);
        } else {
            _addNonEarningAmount(recipient_, amount_);
        }

        totalSupply += amount_;
    }

    function _burn(address account_, uint256 amount_) internal {
        _accrueYield(account_);

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
        uint256 principalAmount_ = _getPrincipalAmountRoundedDown(uint240(amount_), currentIndex());

        _earningPrincipals[account_] = principalAmount_;

        // Totals update
        principalOfTotalEarningSupply += principalAmount_;
        totalNonEarningSupply -= amount_;
    }

    function _stopEarning(address account_) internal {
        if (!_isEarning[account_]) return;

        _accrueYield(account_);

        // Totals update
        uint256 principalAmount_ = _earningPrincipals[account_];

        totalNonEarningSupply += _getPresentAmountRoundedDown(uint112(principalAmount_), currentIndex());
        principalOfTotalEarningSupply -= principalAmount_;

        // Account update
        delete _earningPrincipals[account_];
        delete _lastAccrueIndices[account_];
        delete _isEarning[account_];
    }

    function _addEarningAmount(address account_, uint256 amount_) internal {
        _balances[account_] += amount_;

        uint256 principalAmount_ = _getPrincipalAmountRoundedDown(uint240(amount_), currentIndex());

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
        uint256 principalAmount_ = _getPrincipalAmountRoundedDown(uint240(amount_), currentIndex());

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
        _accrueYield(sender_);
        _accrueYield(recipient_);

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
        return IRegistrarLike(registrar).listContains(_EARNERS_LIST, account_);
    }

    function _getClaimer(address earner_) internal view returns (address) {
        return
            address(
                uint160(uint256(IRegistrarLike(registrar).get(keccak256(abi.encode(_EARNING_CLAIMER_PREFIX, earner_)))))
            );
    }

    function _multiplyDown(uint112 x_, uint128 index_) internal pure returns (uint240 z) {
        unchecked {
            return uint240((uint256(x_) * index_) / _EXP_SCALED_ONE);
        }
    }

    function _divideDown(uint240 x_, uint128 index_) internal pure returns (uint112 z) {
        if (index_ == 0) revert DivisionByZero();

        unchecked {
            return UIntMath.safe112((uint256(x_) * _EXP_SCALED_ONE) / index_);
        }
    }

    function _divideUp(uint240 x, uint128 index) internal pure returns (uint112 z) {
        if (index == 0) revert DivisionByZero();

        unchecked {
            return UIntMath.safe112(((uint256(x) * _EXP_SCALED_ONE) + index - 1) / index);
        }
    }

    function _getPresentAmountRoundedDown(
        uint112 principalAmount_,
        uint128 index_
    ) internal pure returns (uint240 presentAmount_) {
        return _multiplyDown(principalAmount_, index_);
    }

    function _getPrincipalAmountRoundedDown(
        uint240 presentAmount_,
        uint128 index_
    ) internal pure returns (uint112 principalAmount_) {
        return _divideDown(presentAmount_, index_);
    }

    function _getPrincipalAmountRoundedUp(
        uint240 presentAmount_,
        uint128 index_
    ) internal pure returns (uint112 principalAmount_) {
        return _divideUp(presentAmount_, index_);
    }
}
