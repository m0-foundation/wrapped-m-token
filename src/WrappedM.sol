// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import {UIntMath} from "../lib/common/src/libs/UIntMath.sol";

import {ERC20Extended} from "../lib/common/src/ERC20Extended.sol";

import {IndexingMath} from "./libs/IndexingMath.sol";

import {IMTokenLike} from "./interfaces/IMTokenLike.sol";
import {IWrappedM} from "./interfaces/IWrappedM.sol";
import {IRegistrarLike} from "./interfaces/IRegistrarLike.sol";

import {Migratable} from "./Migratable.sol";

contract WrappedM is IWrappedM, Migratable, ERC20Extended {
    type BalanceInfo is uint256;

    /* ============ Variables ============ */

    /// @dev Storage slot with the address of the current factory. `keccak256('eip1967.proxy.implementation') - 1`.
    bytes32 private constant _IMPLEMENTATION_SLOT =
        bytes32(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);

    uint56 internal constant _EXP_SCALED_ONE = 1e12;

    bytes32 internal constant _EARNERS_LIST_IGNORED = "earners_list_ignored";
    bytes32 internal constant _EARNERS_LIST = "earners";
    bytes32 internal constant _CLAIM_DESTINATION_PREFIX = "wm_claim_destination";
    bytes32 internal constant _MIGRATOR_V1_PREFIX = "wm_migrator_v1";

    address public immutable mToken;
    address public immutable registrar;
    address public immutable vault;

    uint112 internal _principalOfTotalEarningSupply;
    uint128 internal _indexOfTotalEarningSupply;

    uint240 public totalNonEarningSupply;

    mapping(address account => BalanceInfo balance) internal _balances;

    /* ============ Constructor ============ */

    constructor(address mToken_) ERC20Extended("WrappedM by M^0", "wM", 6) {
        if ((mToken = mToken_) == address(0)) revert ZeroMToken();

        registrar = IMTokenLike(mToken_).ttgRegistrar();
        vault = IRegistrarLike(registrar).vault();
    }

    /* ============ Interactive Functions ============ */

    function claimFor(address account_) external returns (uint240 yield_) {
        return _claim(account_, currentIndex());
    }

    function claimExcess() external returns (uint240 yield_) {
        emit ExcessClaim(yield_ = excess());

        IMTokenLike(mToken).transfer(vault, yield_);
    }

    function deposit(address destination_, uint256 amount_) external {
        emit Transfer(address(0), destination_, amount_);

        _addAmount(destination_, UIntMath.safe240(amount_));

        IMTokenLike(mToken).transferFrom(msg.sender, address(this), amount_);
    }

    function startEarningFor(address account_) external {
        if (!_isApprovedEarner(account_)) revert NotApprovedEarner();

        (bool isEarning_,, uint240 rawBalance_) = _getBalanceInfo(account_);

        if (isEarning_) return;

        emit StartedEarning(account_);

        uint128 currentIndex_ = currentIndex();

        _setBalanceInfo(
            account_, true, currentIndex_, IndexingMath.getPrincipalAmountRoundedDown(rawBalance_, currentIndex_)
        );

        totalNonEarningSupply -= rawBalance_;

        _addTotalEarningSupply(rawBalance_, currentIndex_);
    }

    function stopEarningFor(address account_) external {
        if (_isApprovedEarner(account_)) revert ApprovedEarner();

        (bool isEarning_,,) = _getBalanceInfo(account_);

        if (!isEarning_) return;

        emit StoppedEarning(account_);

        uint128 currentIndex_ = currentIndex();

        _claim(account_, currentIndex_);

        (, uint128 index_, uint256 rawBalance_) = _getBalanceInfo(account_);

        uint240 amount_ = IndexingMath.getPresentAmountRoundedDown(uint112(rawBalance_), index_);

        _setBalanceInfo(account_, false, 0, amount_);
        totalNonEarningSupply += amount_;

        _subtractTotalEarningSupply(amount_, currentIndex_);
    }

    function withdraw(address destination_, uint256 amount_) external {
        emit Transfer(msg.sender, address(0), amount_);

        _subtractAmount(msg.sender, UIntMath.safe240(amount_));

        IMTokenLike(mToken).transfer(destination_, amount_);
    }

    /* ============ View/Pure Functions ============ */

    function accruedYieldOf(address account_) external view returns (uint240 yield_) {
        (bool isEarning_, uint128 index_, uint240 rawBalance_) = _getBalanceInfo(account_);

        return isEarning_ ? _getAccruedYield(uint112(rawBalance_), index_, currentIndex()) : 0;
    }

    function balanceOf(address account_) external view returns (uint256 balance_) {
        (bool isEarning_, uint128 index_, uint240 rawBalance_) = _getBalanceInfo(account_);

        return isEarning_ ? IndexingMath.getPresentAmountRoundedDown(uint112(rawBalance_), index_) : rawBalance_;
    }

    function currentIndex() public view returns (uint128 index_) {
        return IMTokenLike(mToken).currentIndex();
    }

    function excess() public view returns (uint240 yield_) {
        uint240 balance_ = uint240(IMTokenLike(mToken).balanceOf(address(this)));
        uint240 earmarked_ = uint240(totalSupply()) + totalAccruedYield();

        return balance_ > earmarked_ ? balance_ - earmarked_ : 0;
    }

    function totalAccruedYield() public view returns (uint240 yield_) {
        return _getTotalAccruedYield(currentIndex());
    }

    function totalEarningSupply() public view returns (uint240 totalSupply_) {
        return IndexingMath.getPresentAmountRoundedUp(_principalOfTotalEarningSupply, _indexOfTotalEarningSupply);
    }

    function totalSupply() public view returns (uint256 totalSupply_) {
        return totalEarningSupply() + totalNonEarningSupply;
    }

    /* ============ Internal Interactive Functions ============ */

    function _addAmount(address recipient_, uint240 amount_) internal {
        (bool isEarning_,,) = _getBalanceInfo(recipient_);

        if (!isEarning_) return _addNonEarningAmount(recipient_, amount_);

        uint128 currentIndex_ = currentIndex();

        _claim(recipient_, currentIndex_);
        _addEarningAmount(recipient_, amount_, currentIndex_);
    }

    function _addNonEarningAmount(address recipient_, uint240 amount_) internal {
        (,, uint240 rawBalance_) = _getBalanceInfo(recipient_);
        _setBalanceInfo(recipient_, false, 0, rawBalance_ + amount_);
        totalNonEarningSupply += amount_;
    }

    function _addEarningAmount(address recipient_, uint240 amount_, uint128 currentIndex_) internal {
        (,, uint240 rawBalance_) = _getBalanceInfo(recipient_);

        _setBalanceInfo(
            recipient_,
            true,
            currentIndex_,
            rawBalance_ + IndexingMath.getPrincipalAmountRoundedDown(amount_, currentIndex_)
        );

        _addTotalEarningSupply(amount_, currentIndex_);
    }

    function _claim(address account_, uint128 currentIndex_) internal returns (uint240 yield_) {
        (bool isEarner_, uint128 index_, uint240 rawBalance_) = _getBalanceInfo(account_);

        if (!isEarner_) return 0;

        yield_ = _getAccruedYield(uint112(rawBalance_), index_, currentIndex_);
        _setBalanceInfo(account_, true, currentIndex_, rawBalance_);

        if (yield_ == 0) return 0;

        emit Claim(account_, yield_);
        emit Transfer(address(0), account_, yield_);

        _setTotalEarningSupply(totalEarningSupply() + yield_, _principalOfTotalEarningSupply);

        address claimOverrideDestination_ = _getClaimOverrideDestination(account_);

        if (claimOverrideDestination_ == address(0)) return yield_;

        // // NOTE: Watch out for a long chain of claim override destinations.
        // // TODO: Maybe can be optimized since we know `account_` is an earner and already claimed.
        _transfer(account_, claimOverrideDestination_, yield_, currentIndex_);
    }

    function _setBalanceInfo(address account_, bool isEarning_, uint128 index_, uint240 amount_) internal {
        _balances[account_] = isEarning_
            ? BalanceInfo.wrap((uint256(1) << 248) | (uint256(index_) << 112) | uint256(amount_))
            : BalanceInfo.wrap(uint256(amount_));
    }

    function _subtractAmount(address account_, uint240 amount_) internal {
        (bool isEarning_,,) = _getBalanceInfo(account_);

        if (!isEarning_) return _subtractNonEarningAmount(account_, amount_);

        uint128 currentIndex_ = currentIndex();

        _claim(account_, currentIndex_);
        _subtractEarningAmount(account_, amount_, currentIndex_);
    }

    function _subtractNonEarningAmount(address account_, uint240 amount_) internal {
        (,, uint240 rawBalance_) = _getBalanceInfo(account_);
        _setBalanceInfo(account_, false, 0, rawBalance_ - amount_);
        totalNonEarningSupply -= amount_;
    }

    function _subtractEarningAmount(address account_, uint240 amount_, uint128 currentIndex_) internal {
        (,, uint240 rawBalance_) = _getBalanceInfo(account_);

        _setBalanceInfo(
            account_,
            true,
            currentIndex_,
            rawBalance_ - IndexingMath.getPrincipalAmountRoundedUp(amount_, currentIndex_)
        );

        _subtractTotalEarningSupply(amount_, currentIndex_);
    }

    function _transfer(address sender_, address recipient_, uint240 amount_, uint128 currentIndex_) internal {
        _claim(sender_, currentIndex_);
        _claim(recipient_, currentIndex_);

        emit Transfer(sender_, recipient_, amount_);

        (bool senderIsEarning_,,) = _getBalanceInfo(sender_);
        (bool recipientIsEarning_,,) = _getBalanceInfo(recipient_);

        senderIsEarning_
            ? _subtractEarningAmount(sender_, amount_, currentIndex_)
            : _subtractNonEarningAmount(sender_, amount_);

        recipientIsEarning_
            ? _addEarningAmount(recipient_, amount_, currentIndex_)
            : _addNonEarningAmount(recipient_, amount_);
    }

    function _transfer(address sender_, address recipient_, uint256 amount_) internal override {
        _transfer(sender_, recipient_, UIntMath.safe240(amount_), currentIndex());
    }

    function _addTotalEarningSupply(uint240 amount_, uint128 currentIndex_) internal {
        _setTotalEarningSupply(
            totalEarningSupply() + amount_,
            _principalOfTotalEarningSupply + IndexingMath.getPrincipalAmountRoundedDown(amount_, currentIndex_)
        );
    }

    function _subtractTotalEarningSupply(uint240 amount_, uint128 currentIndex_) internal {
        _setTotalEarningSupply(
            totalEarningSupply() - amount_,
            _principalOfTotalEarningSupply - IndexingMath.getPrincipalAmountRoundedDown(amount_, currentIndex_)
        );
    }

    function _setTotalEarningSupply(uint240 amount_, uint112 principalAmount_) internal {
        _indexOfTotalEarningSupply =
            principalAmount_ == 0 ? 0 : IndexingMath.divide240by112Down(amount_, principalAmount_);

        _principalOfTotalEarningSupply = principalAmount_;
    }

    /* ============ Internal View/Pure Functions ============ */

    function _getAccruedYield(uint112 principalAmount_, uint128 index_, uint128 currentIndex_)
        internal
        pure
        returns (uint240)
    {
        return IndexingMath.getPresentAmountRoundedDown(principalAmount_, currentIndex_ - index_);
    }

    function _getBalanceInfo(address account_)
        internal
        view
        returns (bool isEarning_, uint128 index_, uint240 rawBalance_)
    {
        uint256 unwrapped_ = BalanceInfo.unwrap(_balances[account_]);

        return (unwrapped_ >> 248) != 0
            ? (true, uint128((unwrapped_ << 8) >> 120), uint112(unwrapped_))
            : (false, uint128(0), uint240(unwrapped_));
    }

    function _getClaimOverrideDestination(address account_) internal view returns (address) {
        return address(
            uint160(uint256(IRegistrarLike(registrar).get(keccak256(abi.encode(_CLAIM_DESTINATION_PREFIX, account_)))))
        );
    }

    function _getTotalAccruedYield(uint128 currentIndex_) internal view returns (uint240 yield_) {
        uint240 totalProjectedSupply_ =
            IndexingMath.getPresentAmountRoundedUp(_principalOfTotalEarningSupply, currentIndex_);

        uint240 totalEarningSupply_ = totalEarningSupply();

        return totalProjectedSupply_ <= totalEarningSupply_ ? 0 : totalProjectedSupply_ - totalEarningSupply_;
    }

    function _isApprovedEarner(address account_) internal view returns (bool) {
        return IRegistrarLike(registrar).get(_EARNERS_LIST_IGNORED) != bytes32(0)
            || IRegistrarLike(registrar).listContains(_EARNERS_LIST, account_);
    }

    function _getMigrator() internal view override returns (address migrator_) {
        return address(
            uint160(uint256(IRegistrarLike(registrar).get(keccak256(abi.encode(_MIGRATOR_V1_PREFIX, address(this))))))
        );
    }
}
