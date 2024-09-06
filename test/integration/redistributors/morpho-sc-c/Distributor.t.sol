// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { console2 } from "../../../../lib/forge-std/src/Test.sol";

import { IERC20 } from "../../../../lib/common/src/interfaces/IERC20.sol";

import { Distributor } from "../../../../src/redistributors/morpho-sc-c/Distributor.sol";

import {
    Id,
    MarketParams,
    IMorphoVaultFactoryLike,
    IMorphoVaultLike,
    IMorphoBlueLike
} from "../../vendor/morpho-blue/Interfaces.sol";

import { TestBase } from "../../TestBase.sol";

contract DistributorTests is TestBase {
    uint256 internal constant _MARKET_PARAMS_BYTES_LENGTH = 5 * 32;

    // Morpho Blue factory on Ethereum Mainnet
    address internal constant _morpho = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    // Morpho Vault factory on Ethereum Mainnet
    address internal constant _morphoVaultFactory = 0xA9c3D3a366466Fa809d1Ae982Fb2c46E5fC41101;

    Id internal constant _IDLE_MARKET_ID = Id.wrap(0x7725318760d6d193e11f889f0be58eba134f64a8c22ed9050cac7bd4a70a64f0);

    address[] internal _vaults;

    Distributor internal _distributor;

    uint256 internal _morphoBalance;
    uint256 internal _distributorBalance;

    uint256 internal _morphoYield;

    uint256[] internal _balances;

    uint256[][] internal _claimable;

    function setUp() external {
        _distributor = new Distributor(address(_wrappedMToken), _morpho, _morphoVaultFactory);

        _createVault(_alice, "V0", bytes32(0));
        _createVault(_bob, "V1", bytes32(0));
        _createVault(_carol, "V2", bytes32(0));

        _submitVaultMarketCap(_vaults[0], address(_wrappedMToken), address(0), address(0), 0, type(uint184).max);
        _submitVaultMarketCap(_vaults[1], address(_wrappedMToken), address(0), address(0), 0, type(uint184).max);
        _submitVaultMarketCap(_vaults[2], address(_wrappedMToken), address(0), address(0), 0, type(uint184).max);

        vm.warp(vm.getBlockTimestamp() + 1 days);

        _acceptVaultMarketCap(_vaults[0], address(_wrappedMToken), address(0), address(0), 0);
        _acceptVaultMarketCap(_vaults[1], address(_wrappedMToken), address(0), address(0), 0);
        _acceptVaultMarketCap(_vaults[2], address(_wrappedMToken), address(0), address(0), 0);

        Id[] memory newSupplyQueue_ = new Id[](1);
        newSupplyQueue_[0] = _IDLE_MARKET_ID;

        _setVaultSupplyQueue(_vaults[0], newSupplyQueue_);
        _setVaultSupplyQueue(_vaults[1], newSupplyQueue_);
        _setVaultSupplyQueue(_vaults[2], newSupplyQueue_);

        for (uint256 i_; i_ < _accounts.length; ++i_) {
            _giveWM(_accounts[i_], 100_000e6);
            _balances.push(100_000e6);
        }

        _addToList(_EARNERS_LIST, _morpho);
        _wrappedMToken.startEarningFor(_morpho);

        _setClaimOverrideRecipient(_morpho, address(_distributor));

        _morphoBalance = _wrappedMToken.balanceOf(_morpho);
        _distributorBalance = _wrappedMToken.balanceOf(address(_distributor));
        _morphoYield = _wrappedMToken.accruedYieldOf(_morpho);
    }

    function test_equalSharePrices() external {
        /* ============ First Round Of Deposits ============ */

        _deposit(_vaults[0], _accounts[0], _depositToVault(_accounts[0], _vaults[0], 30_000e6));

        _deposit(_vaults[1], _accounts[1], _depositToVault(_accounts[1], _vaults[1], 20_000e6));
        _deposit(_vaults[1], _accounts[2], _depositToVault(_accounts[2], _vaults[1], 10_000e6));

        _deposit(_vaults[2], _accounts[3], _depositToVault(_accounts[3], _vaults[2], 5_000e6));
        _deposit(_vaults[2], _accounts[4], _depositToVault(_accounts[4], _vaults[2], 5_000e6));
        _deposit(_vaults[2], _accounts[5], _depositToVault(_accounts[5], _vaults[2], 5_000e6));

        assertEq(IMorphoVaultLike(_vaults[0]).balanceOf(_accounts[0]), 0);
        assertEq(IMorphoVaultLike(_vaults[1]).balanceOf(_accounts[1]), 0);
        assertEq(IMorphoVaultLike(_vaults[1]).balanceOf(_accounts[2]), 0);
        assertEq(IMorphoVaultLike(_vaults[2]).balanceOf(_accounts[3]), 0);
        assertEq(IMorphoVaultLike(_vaults[2]).balanceOf(_accounts[4]), 0);
        assertEq(IMorphoVaultLike(_vaults[2]).balanceOf(_accounts[5]), 0);

        assertEq(_wrappedMToken.balanceOf(_accounts[0]), _balances[0] -= 30_000e6);
        assertEq(_wrappedMToken.balanceOf(_accounts[1]), _balances[1] -= 20_000e6);
        assertEq(_wrappedMToken.balanceOf(_accounts[2]), _balances[2] -= 10_000e6);
        assertEq(_wrappedMToken.balanceOf(_accounts[3]), _balances[3] -= 5_000e6);
        assertEq(_wrappedMToken.balanceOf(_accounts[4]), _balances[4] -= 5_000e6);
        assertEq(_wrappedMToken.balanceOf(_accounts[5]), _balances[5] -= 5_000e6);

        assertEq(_wrappedMToken.balanceOf(_morpho), _morphoBalance += 75_000e6);
        assertEq(_wrappedMToken.accruedYieldOf(_morpho), _morphoYield);

        /* ============ 180 Days Elapse ============ */

        vm.warp(vm.getBlockTimestamp() + 180 days);

        assertEq(_wrappedMToken.balanceOf(_morpho), _morphoBalance += 0);
        assertEq(_wrappedMToken.accruedYieldOf(_morpho), _morphoYield += 754_604987);

        _wrappedMToken.claimFor(_morpho);

        _distributor.distribute();

        assertEq(_distributor.getClaimable(_accounts[0]), _claimable[0][0] += (30 * _morphoYield) / 75);
        assertEq(_distributor.getClaimable(_accounts[1]), _claimable[1][1] += (20 * _morphoYield) / 75);
        assertEq(_distributor.getClaimable(_accounts[2]), _claimable[1][2] += (10 * _morphoYield) / 75);
        assertEq(_distributor.getClaimable(_accounts[3]), _claimable[2][3] += (5 * _morphoYield) / 75);
        assertEq(_distributor.getClaimable(_accounts[4]), _claimable[2][4] += (5 * _morphoYield) / 75);
        assertEq(_distributor.getClaimable(_accounts[5]), _claimable[2][5] += (5 * _morphoYield) / 75);

        assertEq(_wrappedMToken.balanceOf(address(_distributor)), _distributorBalance += _morphoYield);

        assertEq(_wrappedMToken.balanceOf(_morpho), _morphoBalance += 0);
        assertEq(_wrappedMToken.accruedYieldOf(_morpho), _morphoYield -= _morphoYield);

        /* ============ Second Round Of Deposits ============ */

        _deposit(_vaults[0], _accounts[0], _depositToVault(_accounts[0], _vaults[0], 10_000e6));

        _deposit(_vaults[1], _accounts[1], _depositToVault(_accounts[1], _vaults[1], 10_000e6));

        _deposit(_vaults[2], _accounts[3], _depositToVault(_accounts[3], _vaults[2], 10_000e6));

        assertEq(IMorphoVaultLike(_vaults[0]).balanceOf(_accounts[0]), 0);
        assertEq(IMorphoVaultLike(_vaults[1]).balanceOf(_accounts[1]), 0);
        assertEq(IMorphoVaultLike(_vaults[2]).balanceOf(_accounts[3]), 0);

        assertEq(_wrappedMToken.balanceOf(_accounts[0]), _balances[0] -= 10_000e6);
        assertEq(_wrappedMToken.balanceOf(_accounts[1]), _balances[1] -= 10_000e6);
        assertEq(_wrappedMToken.balanceOf(_accounts[3]), _balances[3] -= 10_000e6);

        assertEq(_wrappedMToken.balanceOf(_morpho), _morphoBalance += 30_000e6);
        assertEq(_wrappedMToken.accruedYieldOf(_morpho), _morphoYield);

        /* ============ 180 Days Elapse ============ */

        vm.warp(vm.getBlockTimestamp() + 180 days);

        assertEq(_wrappedMToken.balanceOf(_morpho), _morphoBalance += 0);
        assertEq(_wrappedMToken.accruedYieldOf(_morpho), _morphoYield += 1_056_442074);

        _wrappedMToken.claimFor(_morpho);

        _distributor.distribute();

        assertEq(_distributor.getClaimable(_accounts[0]), _claimable[0][0] += (40 * _morphoYield) / 105 + 1);
        assertEq(_distributor.getClaimable(_accounts[1]), _claimable[1][1] += (30 * _morphoYield) / 105 + 1);
        assertEq(_distributor.getClaimable(_accounts[2]), _claimable[1][2] += (10 * _morphoYield) / 105 + 1);
        assertEq(_distributor.getClaimable(_accounts[3]), _claimable[2][3] += (15 * _morphoYield) / 105);
        assertEq(_distributor.getClaimable(_accounts[4]), _claimable[2][4] += (5 * _morphoYield) / 105);
        assertEq(_distributor.getClaimable(_accounts[5]), _claimable[2][5] += (5 * _morphoYield) / 105);

        assertEq(_wrappedMToken.balanceOf(address(_distributor)), _distributorBalance += _morphoYield);

        assertEq(_wrappedMToken.balanceOf(_morpho), _morphoBalance += 0);
        assertEq(_wrappedMToken.accruedYieldOf(_morpho), _morphoYield -= _morphoYield);

        /* ============ Some Claims ============ */

        _claim(_accounts[0]);
        _claim(_accounts[2]);
        _claim(_accounts[5]);

        assertEq(_wrappedMToken.balanceOf(_accounts[0]), _balances[0] += _claimable[0][0]);
        assertEq(_wrappedMToken.balanceOf(_accounts[2]), _balances[2] += _claimable[1][2]);
        assertEq(_wrappedMToken.balanceOf(_accounts[5]), _balances[5] += _claimable[2][5]);

        assertEq(
            _wrappedMToken.balanceOf(address(_distributor)),
            _distributorBalance -= _claimable[0][0] + _claimable[1][2] + _claimable[2][5]
        );

        assertEq(_distributor.getClaimable(_accounts[0]), _claimable[0][0] -= _claimable[0][0]);
        assertEq(_distributor.getClaimable(_accounts[2]), _claimable[1][2] -= _claimable[1][2]);
        assertEq(_distributor.getClaimable(_accounts[5]), _claimable[2][5] -= _claimable[2][5]);

        /* ============ Some Withdrawals ============ */

        _withdraw(_vaults[0], _accounts[0], 10_000e6 * 1e12);
        _withdraw(_vaults[1], _accounts[1], 6_000e6 * 1e12);
        _withdraw(_vaults[2], _accounts[4], 2_000e6 * 1e12);

        // NOTE: vault shares decimals are `18 - underlyingDecimals`, so 12 since wM is 6.
        assertEq(IMorphoVaultLike(_vaults[0]).balanceOf(_accounts[0]), 10_000e6 * 1e12);
        assertEq(IMorphoVaultLike(_vaults[1]).balanceOf(_accounts[1]), 6_000e6 * 1e12);
        assertEq(IMorphoVaultLike(_vaults[2]).balanceOf(_accounts[4]), 2_000e6 * 1e12);

        /* ============ 180 Days Elapse ============ */

        vm.warp(vm.getBlockTimestamp() + 180 days);

        assertEq(_wrappedMToken.balanceOf(_morpho), _morphoBalance += 0);
        assertEq(_wrappedMToken.accruedYieldOf(_morpho), _morphoYield += 1_056_442073);

        _wrappedMToken.claimFor(_morpho);

        _distributor.distribute();

        assertEq(_distributor.getClaimable(_accounts[0]), _claimable[0][0] += (30 * _morphoYield) / 87);
        assertEq(_distributor.getClaimable(_accounts[1]), _claimable[1][1] += (24 * _morphoYield) / 87);
        assertEq(_distributor.getClaimable(_accounts[2]), _claimable[1][2] += (10 * _morphoYield) / 87);
        assertEq(_distributor.getClaimable(_accounts[3]), _claimable[2][3] += (15 * _morphoYield) / 87);
        assertEq(_distributor.getClaimable(_accounts[4]), _claimable[2][4] += (3 * _morphoYield) / 87);
        assertEq(_distributor.getClaimable(_accounts[5]), _claimable[2][5] += (5 * _morphoYield) / 87 + 1);

        assertEq(_wrappedMToken.balanceOf(address(_distributor)), _distributorBalance += _morphoYield);

        assertEq(_wrappedMToken.balanceOf(_morpho), _morphoBalance += 0);
        assertEq(_wrappedMToken.accruedYieldOf(_morpho), _morphoYield -= _morphoYield);

        /* ============ Complete Withdrawals ============ */

        _withdraw(_vaults[0], _accounts[0], 30_000e6 * 1e12);
        _withdraw(_vaults[1], _accounts[1], 24_000e6 * 1e12);
        _withdraw(_vaults[1], _accounts[2], 10_000e6 * 1e12);
        _withdraw(_vaults[2], _accounts[3], 15_000e6 * 1e12);
        _withdraw(_vaults[2], _accounts[4], 3_000e6 * 1e12);
        _withdraw(_vaults[2], _accounts[5], 5_000e6 * 1e12);

        assertEq(IMorphoVaultLike(_vaults[0]).balanceOf(_accounts[0]), 40_000e6 * 1e12);
        assertEq(IMorphoVaultLike(_vaults[1]).balanceOf(_accounts[1]), 30_000e6 * 1e12);
        assertEq(IMorphoVaultLike(_vaults[1]).balanceOf(_accounts[2]), 10_000e6 * 1e12);
        assertEq(IMorphoVaultLike(_vaults[2]).balanceOf(_accounts[3]), 15_000e6 * 1e12);
        assertEq(IMorphoVaultLike(_vaults[2]).balanceOf(_accounts[4]), 5_000e6 * 1e12);
        assertEq(IMorphoVaultLike(_vaults[2]).balanceOf(_accounts[5]), 5_000e6 * 1e12);

        /* ============ Complete Claims ============ */

        _claim(_accounts[0]);
        _claim(_accounts[1]);
        _claim(_accounts[2]);
        _claim(_accounts[3]);
        _claim(_accounts[4]);
        _claim(_accounts[5]);

        assertEq(_wrappedMToken.balanceOf(_accounts[0]), _balances[0] += _claimable[0][0]);
        assertEq(_wrappedMToken.balanceOf(_accounts[1]), _balances[1] += _claimable[1][1]);
        assertEq(_wrappedMToken.balanceOf(_accounts[2]), _balances[2] += _claimable[1][2]);
        assertEq(_wrappedMToken.balanceOf(_accounts[3]), _balances[3] += _claimable[2][3]);
        assertEq(_wrappedMToken.balanceOf(_accounts[4]), _balances[4] += _claimable[2][4]);
        assertEq(_wrappedMToken.balanceOf(_accounts[5]), _balances[5] += _claimable[2][5]);

        assertEq(
            _wrappedMToken.balanceOf(address(_distributor)),
            _distributorBalance -=
                _claimable[0][0] +
                _claimable[1][1] +
                _claimable[1][2] +
                _claimable[2][3] +
                _claimable[2][4] +
                _claimable[2][5]
        );

        assertEq(_distributor.getClaimable(_accounts[0]), _claimable[0][0] -= _claimable[0][0]);
        assertEq(_distributor.getClaimable(_accounts[1]), _claimable[1][1] -= _claimable[1][1]);
        assertEq(_distributor.getClaimable(_accounts[2]), _claimable[1][2] -= _claimable[1][2]);
        assertEq(_distributor.getClaimable(_accounts[3]), _claimable[2][3] -= _claimable[2][3]);
        assertEq(_distributor.getClaimable(_accounts[4]), _claimable[2][4] -= _claimable[2][4]);
        assertEq(_distributor.getClaimable(_accounts[5]), _claimable[2][5] -= _claimable[2][5]);
    }

    function _createVault(address owner_, string memory name_, bytes32 salt_) internal returns (address vault_) {
        vm.prank(owner_);
        vault_ = IMorphoVaultFactoryLike(_morphoVaultFactory).createMetaMorpho(
            owner_,
            1 days,
            address(_wrappedMToken),
            name_,
            name_,
            salt_
        );

        _vaults.push(vault_);
        _claimable.push(new uint256[](_accounts.length));
    }

    function _setVaultFee(address vault_, uint256 newFee_) internal {
        vm.prank(IMorphoVaultLike(vault_).owner());
        IMorphoVaultLike(vault_).setFee(newFee_);
    }

    function _setVaultFeeRecipient(address vault_, address newFeeRecipient_) internal {
        vm.prank(IMorphoVaultLike(vault_).owner());
        IMorphoVaultLike(vault_).setFeeRecipient(newFeeRecipient_);
    }

    function _submitVaultMarketCap(
        address vault_,
        address loanToken_,
        address collateralToken_,
        address oracle_,
        uint256 lltv_,
        uint256 newSupplyCap_
    ) internal {
        MarketParams memory marketParams = MarketParams({
            loanToken: loanToken_,
            collateralToken: collateralToken_,
            oracle: oracle_,
            irm: address(0),
            lltv: lltv_
        });

        vm.prank(IMorphoVaultLike(vault_).owner());
        IMorphoVaultLike(vault_).submitCap(marketParams, newSupplyCap_);
    }

    function _acceptVaultMarketCap(
        address vault_,
        address loanToken_,
        address collateralToken_,
        address oracle_,
        uint256 lltv_
    ) internal {
        MarketParams memory marketParams = MarketParams({
            loanToken: loanToken_,
            collateralToken: collateralToken_,
            oracle: oracle_,
            irm: address(0),
            lltv: lltv_
        });

        vm.prank(IMorphoVaultLike(vault_).owner());
        IMorphoVaultLike(vault_).acceptCap(marketParams);
    }

    function _setVaultSupplyQueue(address vault_, Id[] memory newSupplyQueue_) internal {
        vm.prank(IMorphoVaultLike(vault_).owner());
        IMorphoVaultLike(vault_).setSupplyQueue(newSupplyQueue_);
    }

    function _depositToVault(address account_, address vault_, uint256 assets_) internal returns (uint256 shares) {
        _approveWM(account_, vault_, assets_);

        vm.prank(account_);
        return IMorphoVaultLike(vault_).deposit(assets_, account_);
    }

    function _redeemFromVault(address account_, address vault_, uint256 shares_) internal returns (uint256 assets) {
        vm.prank(account_);
        return IMorphoVaultLike(vault_).redeem(shares_, account_, account_);
    }

    function _createIdleMarket(address account_) internal {
        MarketParams memory marketParams_ = MarketParams({
            loanToken: address(_wrappedMToken),
            collateralToken: address(0),
            oracle: address(0),
            irm: address(0),
            lltv: 0
        });

        vm.prank(account_);
        IMorphoBlueLike(_morpho).createMarket(marketParams_);
    }

    function _getMarketId(MarketParams memory marketParams_) internal pure returns (Id marketParamsId_) {
        assembly ("memory-safe") {
            marketParamsId_ := keccak256(marketParams_, _MARKET_PARAMS_BYTES_LENGTH)
        }
    }

    function _approve(address token_, address account_, address spender_, uint256 amount_) internal {
        vm.prank(account_);
        IERC20(token_).approve(spender_, amount_);
    }

    function _deposit(address vault_, address account_, uint256 shares) internal {
        _approve(vault_, account_, address(_distributor), shares);

        vm.prank(account_);
        _distributor.deposit(vault_, shares);
    }

    function _claim(address account_) internal {
        vm.prank(account_);
        _distributor.claim(account_);
    }

    function _withdraw(address vault_, address account_, uint256 shares) internal {
        vm.prank(account_);
        _distributor.withdraw(vault_, shares);
    }
}
