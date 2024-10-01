// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { console2 } from "../../../../lib/forge-std/src/Test.sol";

import { Id, MarketParams, IMorphoVaultFactoryLike, IMorphoVaultLike } from "../../vendor/morpho-blue/Interfaces.sol";

import { MorphoTestBase } from "../../vendor/morpho-blue/MorphoTestBase.sol";

import { Distributor } from "../../../../src/redistributors/morpho/Distributor.sol";

contract DistributorTests is MorphoTestBase {
    address internal constant _DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address[] internal _vaults;

    Distributor internal _distributor;

    uint256 internal _morphoBalance;
    uint256 internal _distributorBalance;

    uint256 internal _morphoYield;

    uint256[] internal _balances;

    uint256[][] internal _claimable;

    Id internal _usdcMarketId;
    Id internal _daiMarketId;

    function setUp() external {
        _oracle = _createOracle();
        _distributor = new Distributor(address(_wrappedMToken), _MORPHO, _MORPHO_VAULT_FACTORY);

        _createMarket(_alice, address(_wrappedMToken), _USDC, _oracle, _LLTV);
        _createMarket(_alice, address(_wrappedMToken), _DAI, _oracle, _LLTV);

        _usdcMarketId = _getMarketId(
            MarketParams({
                loanToken: address(_wrappedMToken),
                collateralToken: _USDC,
                oracle: _oracle,
                irm: address(0),
                lltv: _LLTV
            })
        );

        _daiMarketId = _getMarketId(
            MarketParams({
                loanToken: address(_wrappedMToken),
                collateralToken: _DAI,
                oracle: _oracle,
                irm: address(0),
                lltv: _LLTV
            })
        );

        _createVault(_judy, "V0", bytes32(0));
        _createVault(_judy, "V1", bytes32(0));
        _createVault(_judy, "V2", bytes32(0));
        _createVault(_judy, "V3", bytes32(0));

        _submitVaultMarketCap(_vaults[0], address(_wrappedMToken), address(0), address(0), 0, type(uint184).max);
        _submitVaultMarketCap(_vaults[1], address(_wrappedMToken), address(0), address(0), 0, type(uint184).max);
        _submitVaultMarketCap(_vaults[2], address(_wrappedMToken), address(0), address(0), 0, type(uint184).max);
        _submitVaultMarketCap(_vaults[3], address(_wrappedMToken), address(0), address(0), 0, type(uint184).max);

        _submitVaultMarketCap(_vaults[0], address(_wrappedMToken), _USDC, _oracle, _LLTV, type(uint184).max);
        _submitVaultMarketCap(_vaults[1], address(_wrappedMToken), _USDC, _oracle, _LLTV, type(uint184).max);
        _submitVaultMarketCap(_vaults[2], address(_wrappedMToken), _USDC, _oracle, _LLTV, type(uint184).max);
        _submitVaultMarketCap(_vaults[3], address(_wrappedMToken), _USDC, _oracle, _LLTV, type(uint184).max);

        _submitVaultMarketCap(_vaults[0], address(_wrappedMToken), _DAI, _oracle, _LLTV, type(uint184).max);
        _submitVaultMarketCap(_vaults[1], address(_wrappedMToken), _DAI, _oracle, _LLTV, type(uint184).max);
        _submitVaultMarketCap(_vaults[2], address(_wrappedMToken), _DAI, _oracle, _LLTV, type(uint184).max);
        _submitVaultMarketCap(_vaults[3], address(_wrappedMToken), _DAI, _oracle, _LLTV, type(uint184).max);

        vm.warp(vm.getBlockTimestamp() + 1 days);

        _acceptVaultMarketCap(_vaults[0], address(_wrappedMToken), address(0), address(0), 0);
        _acceptVaultMarketCap(_vaults[1], address(_wrappedMToken), address(0), address(0), 0);
        _acceptVaultMarketCap(_vaults[2], address(_wrappedMToken), address(0), address(0), 0);
        _acceptVaultMarketCap(_vaults[3], address(_wrappedMToken), address(0), address(0), 0);

        _acceptVaultMarketCap(_vaults[0], address(_wrappedMToken), _USDC, _oracle, _LLTV);
        _acceptVaultMarketCap(_vaults[1], address(_wrappedMToken), _USDC, _oracle, _LLTV);
        _acceptVaultMarketCap(_vaults[2], address(_wrappedMToken), _USDC, _oracle, _LLTV);
        _acceptVaultMarketCap(_vaults[3], address(_wrappedMToken), _USDC, _oracle, _LLTV);

        _acceptVaultMarketCap(_vaults[0], address(_wrappedMToken), _DAI, _oracle, _LLTV);
        _acceptVaultMarketCap(_vaults[1], address(_wrappedMToken), _DAI, _oracle, _LLTV);
        _acceptVaultMarketCap(_vaults[2], address(_wrappedMToken), _DAI, _oracle, _LLTV);
        _acceptVaultMarketCap(_vaults[3], address(_wrappedMToken), _DAI, _oracle, _LLTV);

        for (uint256 i_; i_ < _accounts.length; ++i_) {
            _giveWM(_accounts[i_], 100_000e6);
            _balances.push(100_000e6);
        }

        _addToList(_EARNERS_LIST, _MORPHO);
        _wrappedMToken.startEarningFor(_MORPHO);

        _setClaimOverrideRecipient(_MORPHO, address(_distributor));

        _morphoBalance = _wrappedMToken.balanceOf(_MORPHO);
        _distributorBalance = _wrappedMToken.balanceOf(address(_distributor));
        _morphoYield = _wrappedMToken.accruedYieldOf(_MORPHO);
    }

    function test_equalSharePrices() external {
        /* ============ Setup Supply Queues ============ */

        Id[] memory newSupplyQueue_ = new Id[](1);
        newSupplyQueue_[0] = _IDLE_MARKET_ID;

        _setVaultSupplyQueue(_vaults[0], newSupplyQueue_);
        _setVaultSupplyQueue(_vaults[1], newSupplyQueue_);
        _setVaultSupplyQueue(_vaults[2], newSupplyQueue_);
        _setVaultSupplyQueue(_vaults[3], newSupplyQueue_);

        /* ============ First Round Of Deposits ============ */

        _deposit(_vaults[0], _accounts[0], _depositToVault(_accounts[0], _vaults[0], 30_000e6));

        _deposit(_vaults[1], _accounts[1], _depositToVault(_accounts[1], _vaults[1], 20_000e6));
        _deposit(_vaults[1], _accounts[2], _depositToVault(_accounts[2], _vaults[1], 10_000e6));

        _deposit(_vaults[2], _accounts[3], _depositToVault(_accounts[3], _vaults[2], 5_000e6));
        _deposit(_vaults[2], _accounts[4], _depositToVault(_accounts[4], _vaults[2], 5_000e6));
        _deposit(_vaults[2], _accounts[5], _depositToVault(_accounts[5], _vaults[2], 5_000e6));

        // This is to test that non-participants do not affect the distribution math.
        _depositToVault(_judy, _vaults[0], 5_000e6);
        _depositToVault(_judy, _vaults[1], 5_000e6);
        _depositToVault(_judy, _vaults[2], 5_000e6);
        _depositToVault(_judy, _vaults[3], 15_000e6);

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

        assertEq(_wrappedMToken.balanceOf(_MORPHO), _morphoBalance += 105_000e6);
        assertEq(_wrappedMToken.accruedYieldOf(_MORPHO), _morphoYield);

        /* ============ 180 Days Elapse ============ */

        vm.warp(vm.getBlockTimestamp() + 180 days);

        assertEq(_wrappedMToken.balanceOf(_MORPHO), _morphoBalance += 0);
        assertEq(_wrappedMToken.accruedYieldOf(_MORPHO), _morphoYield += 1_056_442073);

        _wrappedMToken.claimFor(_MORPHO);

        _distributor.distribute(_vaults[0]);
        _distributor.distribute(_vaults[1]);
        _distributor.distribute(_vaults[2]);

        assertEq(_distributor.getClaimable(_vaults[0], _accounts[0]), _claimable[0][0] += (30 * _morphoYield) / 75 - 1);
        assertEq(_distributor.getClaimable(_vaults[1], _accounts[1]), _claimable[1][1] += (20 * _morphoYield) / 75 - 1);
        assertEq(_distributor.getClaimable(_vaults[1], _accounts[2]), _claimable[1][2] += (10 * _morphoYield) / 75 - 1);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[3]), _claimable[2][3] += (5 * _morphoYield) / 75);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[4]), _claimable[2][4] += (5 * _morphoYield) / 75);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[5]), _claimable[2][5] += (5 * _morphoYield) / 75);

        assertEq(_wrappedMToken.balanceOf(address(_distributor)), _distributorBalance += _morphoYield);

        assertEq(_wrappedMToken.balanceOf(_MORPHO), _morphoBalance += 0);
        assertEq(_wrappedMToken.accruedYieldOf(_MORPHO), _morphoYield -= _morphoYield);

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

        assertEq(_wrappedMToken.balanceOf(_MORPHO), _morphoBalance += 30_000e6);
        assertEq(_wrappedMToken.accruedYieldOf(_MORPHO), _morphoYield);

        /* ============ 180 Days Elapse ============ */

        vm.warp(vm.getBlockTimestamp() + 180 days);

        assertEq(_wrappedMToken.balanceOf(_MORPHO), _morphoBalance += 0);
        assertEq(_wrappedMToken.accruedYieldOf(_MORPHO), _morphoYield += 1_358_279159);

        _wrappedMToken.claimFor(_MORPHO);

        _distributor.distribute(_vaults[0]);
        _distributor.distribute(_vaults[1]);
        _distributor.distribute(_vaults[2]);

        assertEq(_distributor.getClaimable(_vaults[0], _accounts[0]), _claimable[0][0] += (40 * _morphoYield) / 105);

        assertEq(
            _distributor.getClaimable(_vaults[1], _accounts[1]),
            _claimable[1][1] += (30 * _morphoYield) / 105 + 1
        );

        assertEq(
            _distributor.getClaimable(_vaults[1], _accounts[2]),
            _claimable[1][2] += (10 * _morphoYield) / 105 + 1
        );

        assertEq(
            _distributor.getClaimable(_vaults[2], _accounts[3]),
            _claimable[2][3] += (15 * _morphoYield) / 105 + 1
        );

        assertEq(_distributor.getClaimable(_vaults[2], _accounts[4]), _claimable[2][4] += (5 * _morphoYield) / 105 + 1);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[5]), _claimable[2][5] += (5 * _morphoYield) / 105 + 1);

        assertEq(_wrappedMToken.balanceOf(address(_distributor)), _distributorBalance += _morphoYield);

        assertEq(_wrappedMToken.balanceOf(_MORPHO), _morphoBalance += 0);
        assertEq(_wrappedMToken.accruedYieldOf(_MORPHO), _morphoYield -= _morphoYield);

        /* ============ Some Claims ============ */

        _claim(_vaults[0], _accounts[0]);
        _claim(_vaults[1], _accounts[2]);
        _claim(_vaults[2], _accounts[5]);

        assertEq(_wrappedMToken.balanceOf(_accounts[0]), _balances[0] += _claimable[0][0]);
        assertEq(_wrappedMToken.balanceOf(_accounts[2]), _balances[2] += _claimable[1][2]);
        assertEq(_wrappedMToken.balanceOf(_accounts[5]), _balances[5] += _claimable[2][5]);

        assertEq(
            _wrappedMToken.balanceOf(address(_distributor)),
            _distributorBalance -= _claimable[0][0] + _claimable[1][2] + _claimable[2][5]
        );

        assertEq(_distributor.getClaimable(_vaults[0], _accounts[0]), _claimable[0][0] -= _claimable[0][0]);
        assertEq(_distributor.getClaimable(_vaults[1], _accounts[2]), _claimable[1][2] -= _claimable[1][2]);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[5]), _claimable[2][5] -= _claimable[2][5]);

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

        assertEq(_wrappedMToken.balanceOf(_MORPHO), _morphoBalance += 0);
        assertEq(_wrappedMToken.accruedYieldOf(_MORPHO), _morphoYield += 1_358_279159);

        _wrappedMToken.claimFor(_MORPHO);

        _distributor.distribute(_vaults[0]);
        _distributor.distribute(_vaults[1]);
        _distributor.distribute(_vaults[2]);

        assertEq(_distributor.getClaimable(_vaults[0], _accounts[0]), _claimable[0][0] += (30 * _morphoYield) / 87 + 1);
        assertEq(_distributor.getClaimable(_vaults[1], _accounts[1]), _claimable[1][1] += (24 * _morphoYield) / 87);
        assertEq(_distributor.getClaimable(_vaults[1], _accounts[2]), _claimable[1][2] += (10 * _morphoYield) / 87 + 1);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[3]), _claimable[2][3] += (15 * _morphoYield) / 87 + 1);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[4]), _claimable[2][4] += (3 * _morphoYield) / 87);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[5]), _claimable[2][5] += (5 * _morphoYield) / 87);

        assertEq(_wrappedMToken.balanceOf(address(_distributor)), _distributorBalance += _morphoYield);

        assertEq(_wrappedMToken.balanceOf(_MORPHO), _morphoBalance += 0);
        assertEq(_wrappedMToken.accruedYieldOf(_MORPHO), _morphoYield -= _morphoYield);

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

        _claim(_vaults[0], _accounts[0]);
        _claim(_vaults[1], _accounts[1]);
        _claim(_vaults[1], _accounts[2]);
        _claim(_vaults[2], _accounts[3]);
        _claim(_vaults[2], _accounts[4]);
        _claim(_vaults[2], _accounts[5]);

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

        assertEq(_distributor.getClaimable(_vaults[0], _accounts[0]), _claimable[0][0] -= _claimable[0][0]);
        assertEq(_distributor.getClaimable(_vaults[1], _accounts[1]), _claimable[1][1] -= _claimable[1][1]);
        assertEq(_distributor.getClaimable(_vaults[1], _accounts[2]), _claimable[1][2] -= _claimable[1][2]);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[3]), _claimable[2][3] -= _claimable[2][3]);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[4]), _claimable[2][4] -= _claimable[2][4]);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[5]), _claimable[2][5] -= _claimable[2][5]);
    }

    function test_variedSharePrices() external {
        /* ============ Setup Supply Queues ============ */

        Id[] memory supplyQueue_ = new Id[](1);
        supplyQueue_[0] = _usdcMarketId;

        _setVaultSupplyQueue(_vaults[0], supplyQueue_);

        supplyQueue_[0] = _daiMarketId;

        _setVaultSupplyQueue(_vaults[1], supplyQueue_);

        supplyQueue_[0] = _IDLE_MARKET_ID;

        _setVaultSupplyQueue(_vaults[2], supplyQueue_);
        _setVaultSupplyQueue(_vaults[3], supplyQueue_);

        /* ============ First Round Of Deposits ============ */

        _deposit(_vaults[0], _accounts[0], _depositToVault(_accounts[0], _vaults[0], 30_000e6));

        _deposit(_vaults[1], _accounts[1], _depositToVault(_accounts[1], _vaults[1], 20_000e6));
        _deposit(_vaults[1], _accounts[2], _depositToVault(_accounts[2], _vaults[1], 10_000e6));

        _deposit(_vaults[2], _accounts[3], _depositToVault(_accounts[3], _vaults[2], 5_000e6));
        _deposit(_vaults[2], _accounts[4], _depositToVault(_accounts[4], _vaults[2], 5_000e6));
        _deposit(_vaults[2], _accounts[5], _depositToVault(_accounts[5], _vaults[2], 5_000e6));

        // This is to test that non-participants do not affect the distribution math.
        _depositToVault(_judy, _vaults[0], 5_000e6);
        _depositToVault(_judy, _vaults[1], 5_000e6);
        _depositToVault(_judy, _vaults[2], 5_000e6);
        _depositToVault(_judy, _vaults[3], 15_000e6);

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

        assertEq(_wrappedMToken.balanceOf(_MORPHO), _morphoBalance += 105_000e6);
        assertEq(_wrappedMToken.accruedYieldOf(_MORPHO), _morphoYield);

        /* ============ Half of USDC Market Emptied via Borrow ============ */

        deal(_USDC, _judy, 60_000e6);
        _supplyCollateral(_judy, _USDC, 60_000e6, address(_wrappedMToken));
        _borrow(_judy, address(_wrappedMToken), 17_500e6, _judy, _USDC);

        assertEq(_wrappedMToken.balanceOf(_MORPHO), _morphoBalance -= 17_500e6);

        _distributor.distribute(_vaults[0]);

        /* ============ 180 Days Elapse ============ */

        vm.warp(vm.getBlockTimestamp() + 180 days);

        assertEq(_wrappedMToken.balanceOf(_MORPHO), _morphoBalance += 0);
        assertEq(_wrappedMToken.accruedYieldOf(_MORPHO), _morphoYield += 880_370440);

        _wrappedMToken.claimFor(_MORPHO);

        _distributor.distribute(_vaults[0]);
        _distributor.distribute(_vaults[1]);
        _distributor.distribute(_vaults[2]);

        assertEq(
            _distributor.getClaimable(_vaults[0], _accounts[0]),
            _claimable[0][0] += ((30 / 2) * _morphoYield) / 60 - 2
        );

        assertEq(_distributor.getClaimable(_vaults[1], _accounts[1]), _claimable[1][1] += (20 * _morphoYield) / 60 - 1);
        assertEq(_distributor.getClaimable(_vaults[1], _accounts[2]), _claimable[1][2] += (10 * _morphoYield) / 60);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[3]), _claimable[2][3] += (5 * _morphoYield) / 60 - 1);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[4]), _claimable[2][4] += (5 * _morphoYield) / 60 - 1);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[5]), _claimable[2][5] += (5 * _morphoYield) / 60 - 1);

        assertEq(_wrappedMToken.balanceOf(address(_distributor)), _distributorBalance += _morphoYield);

        assertEq(_wrappedMToken.balanceOf(_MORPHO), _morphoBalance += 0);
        assertEq(_wrappedMToken.accruedYieldOf(_MORPHO), _morphoYield -= _morphoYield);

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

        assertEq(_wrappedMToken.balanceOf(_MORPHO), _morphoBalance += 30_000e6);
        assertEq(_wrappedMToken.accruedYieldOf(_MORPHO), _morphoYield);

        /* ============ Rest of USDC Market Emptied via Borrow ============ */

        _borrow(_judy, address(_wrappedMToken), 27_500e6, _judy, _USDC);

        assertEq(_wrappedMToken.balanceOf(_MORPHO), _morphoBalance -= 27_500e6);

        _distributor.distribute(_vaults[0]);

        /* ============ 180 Days Elapse ============ */

        vm.warp(vm.getBlockTimestamp() + 180 days);

        assertEq(_wrappedMToken.balanceOf(_MORPHO), _morphoBalance += 0);
        assertEq(_wrappedMToken.accruedYieldOf(_MORPHO), _morphoYield += 905_523531);

        _wrappedMToken.claimFor(_MORPHO);

        _distributor.distribute(_vaults[0]);
        _distributor.distribute(_vaults[1]);
        _distributor.distribute(_vaults[2]);

        assertEq(_distributor.getClaimable(_vaults[0], _accounts[0]), _claimable[0][0] += 0);
        assertEq(_distributor.getClaimable(_vaults[1], _accounts[1]), _claimable[1][1] += (30 * _morphoYield) / 65 + 1);
        assertEq(_distributor.getClaimable(_vaults[1], _accounts[2]), _claimable[1][2] += (10 * _morphoYield) / 65);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[3]), _claimable[2][3] += (15 * _morphoYield) / 65 + 2);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[4]), _claimable[2][4] += (5 * _morphoYield) / 65 + 1);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[5]), _claimable[2][5] += (5 * _morphoYield) / 65 + 1);

        assertEq(_wrappedMToken.balanceOf(address(_distributor)), _distributorBalance += _morphoYield);

        assertEq(_wrappedMToken.balanceOf(_MORPHO), _morphoBalance += 0);
        assertEq(_wrappedMToken.accruedYieldOf(_MORPHO), _morphoYield -= _morphoYield);

        /* ============ Some Claims ============ */

        _claim(_vaults[0], _accounts[0]);
        _claim(_vaults[1], _accounts[2]);
        _claim(_vaults[2], _accounts[5]);

        assertEq(_wrappedMToken.balanceOf(_accounts[0]), _balances[0] += _claimable[0][0]);
        assertEq(_wrappedMToken.balanceOf(_accounts[2]), _balances[2] += _claimable[1][2]);
        assertEq(_wrappedMToken.balanceOf(_accounts[5]), _balances[5] += _claimable[2][5]);

        assertEq(
            _wrappedMToken.balanceOf(address(_distributor)),
            _distributorBalance -= _claimable[0][0] + _claimable[1][2] + _claimable[2][5]
        );

        assertEq(_distributor.getClaimable(_vaults[0], _accounts[0]), _claimable[0][0] -= _claimable[0][0]);
        assertEq(_distributor.getClaimable(_vaults[1], _accounts[2]), _claimable[1][2] -= _claimable[1][2]);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[5]), _claimable[2][5] -= _claimable[2][5]);

        /* ============ Some Withdrawals ============ */

        _withdraw(_vaults[0], _accounts[0], 10_000e6 * 1e12);
        _withdraw(_vaults[1], _accounts[1], 6_000e6 * 1e12);
        _withdraw(_vaults[2], _accounts[4], 2_000e6 * 1e12);

        // NOTE: vault shares decimals are `18 - underlyingDecimals`, so 12 since wM is 6.
        assertEq(IMorphoVaultLike(_vaults[0]).balanceOf(_accounts[0]), 10_000e6 * 1e12);
        assertEq(IMorphoVaultLike(_vaults[1]).balanceOf(_accounts[1]), 6_000e6 * 1e12);
        assertEq(IMorphoVaultLike(_vaults[2]).balanceOf(_accounts[4]), 2_000e6 * 1e12);

        /* ============ Half of DAI Market Emptied via Borrow ============ */

        deal(_DAI, _judy, 60_000e6);
        _supplyCollateral(_judy, _DAI, 60_000e6, address(_wrappedMToken));
        _borrow(_judy, address(_wrappedMToken), 22_500e6, _judy, _DAI);

        assertEq(_wrappedMToken.balanceOf(_MORPHO), _morphoBalance -= 22_500e6);

        _distributor.distribute(_vaults[1]);

        /* ============ 180 Days Elapse ============ */

        vm.warp(vm.getBlockTimestamp() + 180 days);

        assertEq(_wrappedMToken.balanceOf(_MORPHO), _morphoBalance += 0);
        assertEq(_wrappedMToken.accruedYieldOf(_MORPHO), _morphoYield += 679_145716);

        _wrappedMToken.claimFor(_MORPHO);

        _distributor.distribute(_vaults[0]);
        _distributor.distribute(_vaults[1]);
        _distributor.distribute(_vaults[2]);

        assertEq(_distributor.getClaimable(_vaults[0], _accounts[0]), _claimable[0][0] += 0);

        assertEq(
            _distributor.getClaimable(_vaults[1], _accounts[1]),
            _claimable[1][1] += ((24 / 2) * _morphoYield) / 40 + 1
        );

        assertEq(
            _distributor.getClaimable(_vaults[1], _accounts[2]),
            _claimable[1][2] += ((10 / 2) * _morphoYield) / 40 + 1
        );

        assertEq(_distributor.getClaimable(_vaults[2], _accounts[3]), _claimable[2][3] += (15 * _morphoYield) / 40);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[4]), _claimable[2][4] += (3 * _morphoYield) / 40 + 1);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[5]), _claimable[2][5] += (5 * _morphoYield) / 40);

        assertEq(_wrappedMToken.balanceOf(address(_distributor)), _distributorBalance += _morphoYield);

        assertEq(_wrappedMToken.balanceOf(_MORPHO), _morphoBalance += 0);
        assertEq(_wrappedMToken.accruedYieldOf(_MORPHO), _morphoYield -= _morphoYield);

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

        _claim(_vaults[0], _accounts[0]);
        _claim(_vaults[1], _accounts[1]);
        _claim(_vaults[1], _accounts[2]);
        _claim(_vaults[2], _accounts[3]);
        _claim(_vaults[2], _accounts[4]);
        _claim(_vaults[2], _accounts[5]);

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

        assertEq(_distributor.getClaimable(_vaults[0], _accounts[0]), _claimable[0][0] -= _claimable[0][0]);
        assertEq(_distributor.getClaimable(_vaults[1], _accounts[1]), _claimable[1][1] -= _claimable[1][1]);
        assertEq(_distributor.getClaimable(_vaults[1], _accounts[2]), _claimable[1][2] -= _claimable[1][2]);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[3]), _claimable[2][3] -= _claimable[2][3]);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[4]), _claimable[2][4] -= _claimable[2][4]);
        assertEq(_distributor.getClaimable(_vaults[2], _accounts[5]), _claimable[2][5] -= _claimable[2][5]);
    }

    function _createVault(address owner_, string memory name_, bytes32 salt_) internal returns (address vault_) {
        vm.prank(owner_);
        vault_ = IMorphoVaultFactoryLike(_MORPHO_VAULT_FACTORY).createMetaMorpho(
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

    function _deposit(address vault_, address account_, uint256 shares) internal {
        _approve(vault_, account_, address(_distributor), shares);

        vm.prank(account_);
        _distributor.deposit(vault_, shares);
    }

    function _claim(address vault_, address account_) internal {
        vm.prank(account_);
        _distributor.claim(vault_, account_);
    }

    function _withdraw(address vault_, address account_, uint256 shares) internal {
        vm.prank(account_);
        _distributor.withdraw(vault_, shares);
    }
}
