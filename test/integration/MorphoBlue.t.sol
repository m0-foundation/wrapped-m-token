// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { TestBase } from "./TestBase.sol";

import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";

import { IMorphoBlueFactory, IMorphoChainlinkOracleV2Factory } from "./vendor/morpho-blue/Interfaces.sol";

contract MorphoBlueTests is TestBase {
    // Morpho Blue factory on Ethereum Mainnet
    address internal constant _morphoFactory = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    // Oracle factory on Ethereum Mainnet
    address internal constant _oracleFactory = 0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766;

    // Morpho Blue market Liquidation Loan-To-Value ratio
    uint256 internal constant _LLTV = 94_5000000000000000; // 94.5%

    address internal _oracle;

    uint256 internal _wrapperBalanceOfM;

    uint256 internal _morphoBalanceOfUSDC;
    uint256 internal _aliceBalanceOfUSDC;
    uint256 internal _bobBalanceOfUSDC;
    uint256 internal _carolBalanceOfUSDC;
    uint256 internal _daveBalanceOfUSDC;

    uint256 internal _morphoBalanceOfWM;
    uint256 internal _aliceBalanceOfWM;
    uint256 internal _bobBalanceOfWM;
    uint256 internal _carolBalanceOfWM;
    uint256 internal _daveBalanceOfWM;

    uint256 internal _morphoAccruedYield;

    function setUp() public override {
        super.setUp();

        _addToList(_EARNERS_LIST, address(_wrappedMToken));

        _wrappedMToken.enableEarning();

        _oracle = _createOracle();

        _morphoBalanceOfUSDC = IERC20(_USDC).balanceOf(_morphoFactory);
    }

    function test_initialState() external view {
        assertTrue(_mToken.isEarning(address(_wrappedMToken)));
        assertEq(_wrappedMToken.isEarningEnabled(), true);
        assertFalse(_wrappedMToken.isEarning(_morphoFactory));
    }

    function test_morphoBlue_nonEarning_wM_as_collateralToken() external {
        /* ============ Alice Creates Market ============ */

        _giveM(_alice, 1_000_100e6);
        _wrap(_alice, _alice, 1_000_100e6);

        assertEq(_mToken.balanceOf(_alice), 0);
        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM += 1_000_099_999999);
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 1_000_099_999999);

        deal(_USDC, _alice, 1_000_100e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC += 1_000_100e6);

        // NOTE: Creating a market also result in `_alice` supplying 1.00 USDC as supply, 1.00 wM as collateral, and
        //       borrowing 0.90 USDC.
        _createMarket(_alice, _USDC, address(_wrappedMToken));

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM -= 1e6);
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM += 1e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC -= 100000);
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC += 100000);

        /* ============ Alice Supplies Seed USDC For Loans ============ */

        _supply(_alice, _USDC, 1_000_000e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC -= 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC += 1_000_000e6);

        /* ============ Bob Takes Out USDC Loan Against wM Collateral ============ */

        _giveM(_bob, 1_000_100e6);
        _wrap(_bob, _bob, 1_000_100e6);

        assertEq(_mToken.balanceOf(_bob), 0);
        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM += 1_000_099_999999);
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 1_000_099_999999);

        _supplyCollateral(_bob, address(_wrappedMToken), 1_000_000e6);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM -= 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM += 1_000_000e6);

        _borrow(_bob, _USDC, 900_000e6, _bob);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC += 900_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC -= 900_000e6);

        /* ============ First 1-Year Time Warp ============ */

        // Move 1 year forward and check that no yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 82_462_608992);

        // `startEarningFor` hasn't been called so no wM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoFactory), _morphoAccruedYield);

        // But excess yield has accrued in the wrapped M contract.
        assertEq(_wrappedMToken.excess(), 82_462_608991);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC);

        /* ============ Bob Repays USDC Loan And Withdraws wM Collateral ============ */

        _repay(_bob, _USDC, 900_000e6);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC -= 900_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC += 900_000e6);

        _withdrawCollateral(_bob, address(_wrappedMToken), 1_000_000e6, _bob);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM += 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM -= 1_000_000e6);

        /* ============ Alice Withdraws Seed USDC For Loans ============ */

        _withdraw(_alice, _USDC, 1_000_000e6, _alice);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC += 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC -= 1_000_000e6);

        /* ============ Second 1-Year Time Warp ============ */

        // Move 1 year forward and check that no yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 85_862_309962);

        // `startEarningFor` hasn't been called so no wM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoFactory), _morphoAccruedYield);

        // But excess yield has accrued in the wrapped M contract.
        assertEq(_wrappedMToken.excess(), 168_324_918953);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC);
    }

    function test_morphoBlue_nonEarning_wM_as_loanToken() external {
        /* ============ Alice Creates Market ============ */

        _giveM(_alice, 1_000_100e6);
        _wrap(_alice, _alice, 1_000_100e6);

        assertEq(_mToken.balanceOf(_alice), 0);
        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM += 1_000_099_999999);
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 1_000_099_999999);

        deal(_USDC, _alice, 1_000_100e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC += 1_000_100e6);

        // NOTE: Creating a market also result in `_alice` supplying 1.00 wM as supply, 1.00 USDC as collateral, and
        //       borrowing 0.90 wM.
        _createMarket(_alice, address(_wrappedMToken), _USDC);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM -= 100000);
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM += 100000);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC -= 1e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC += 1e6);

        /* ============ Alice Supplies Seed wM For Loans ============ */

        _supply(_alice, address(_wrappedMToken), 1_000_000e6);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM -= 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM += 1_000_000e6);

        /* ============ Bob Takes Out wM Loan Against USDC Collateral ============ */

        deal(_USDC, _bob, 1_000_000e6);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC += 1_000_000e6);

        _supplyCollateral(_bob, _USDC, 1_000_000e6);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC -= 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC += 1_000_000e6);

        _borrow(_bob, address(_wrappedMToken), 900_000e6, _bob);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM += 900_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM -= 900_000e6);

        /* ============ First 1-Year Time Warp ============ */

        // Move 1 year forward and check that no yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 51_276_223485);

        // `startEarningFor` hasn't been called so no wM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoFactory), _morphoAccruedYield);

        // But excess yield has accrued in the wrapped M contract.
        assertEq(_wrappedMToken.excess(), 51_276_223483);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC);

        /* ============ Bob Repays wM Loan And Withdraws USDC Collateral ============ */

        _repay(_bob, address(_wrappedMToken), 900_000e6);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM -= 900_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM += 900_000e6);

        _withdrawCollateral(_bob, _USDC, 1_000_000e6, _bob);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC += 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC -= 1_000_000e6);

        /* ============ Alice Withdraws Seed wM For Loans ============ */

        _withdraw(_alice, address(_wrappedMToken), 1_000_000e6, _alice);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM += 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM -= 1_000_000e6);

        /* ============ Second 1-Year Time Warp ============ */

        // Move 1 year forward and check that no yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 53_905_211681);

        // `startEarningFor` hasn't been called so no wM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoFactory), _morphoAccruedYield);

        // But excess yield has accrued in the wrapped M contract.
        assertEq(_wrappedMToken.excess(), 105_181_435164);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC);
    }

    function test_morphoBlue_earning_wM_as_collateralToken() public {
        /* ============ Alice Creates Market ============ */

        _giveM(_alice, 1_000_100e6);
        _wrap(_alice, _alice, 1_000_100e6);

        assertEq(_mToken.balanceOf(_alice), 0);
        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM += 1_000_099_999999);
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 1_000_099_999999);

        deal(_USDC, _alice, 1_000_100e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC += 1_000_100e6);

        // NOTE: Creating a market also result in `_alice` supplying 1.00 USDC as supply, 1.00 wM as collateral, and
        //       borrowing 0.90 USDC.
        _createMarket(_alice, _USDC, address(_wrappedMToken));

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM -= 1e6);
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM += 1e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC -= 100000);
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC += 100000);

        /* ============ Alice Supplies Seed USDC For Loans ============ */

        _supply(_alice, _USDC, 1_000_000e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC -= 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC += 1_000_000e6);

        /* ============ Bob Takes Out USDC Loan Against wM Collateral ============ */

        _giveM(_bob, 1_000_100e6);
        _wrap(_bob, _bob, 1_000_100e6);

        assertEq(_mToken.balanceOf(_bob), 0);
        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM += 1_000_099_999999);
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 1_000_099_999999);

        _supplyCollateral(_bob, address(_wrappedMToken), 1_000_000e6);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM -= 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM += 1_000_000e6);

        _borrow(_bob, _USDC, 900_000e6, _bob);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC += 900_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC -= 900_000e6);

        /* ============ Morpho Becomes An Earner ============ */

        _setClaimOverrideRecipient(_morphoFactory, _carol);

        _addToList(_EARNERS_LIST, _morphoFactory);
        _wrappedMToken.startEarningFor(_morphoFactory);

        // Check that the pool is earning wM.
        assertTrue(_wrappedMToken.isEarning(_morphoFactory));

        assertEq(_wrappedMToken.claimOverrideRecipientFor(_morphoFactory), _carol);

        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoFactory), _morphoAccruedYield);

        /* ============ First 1-Year Time Warp ============ */

        // Move 1 year forward and check that yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 82_462_608992);

        // `startEarningFor` has been called so wM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoFactory), _morphoAccruedYield += 41_227_223004);

        // But excess yield has accrued in the wrapped M contract.
        assertEq(_wrappedMToken.excess(), 41_235_385986);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC);

        /* ============ Bob Repays USDC Loan And Withdraws wM Collateral ============ */

        _repay(_bob, _USDC, 900_000e6);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC -= 900_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC += 900_000e6);

        _withdrawCollateral(_bob, address(_wrappedMToken), 1_000_000e6, _bob);

        // The collateral withdrawal has triggered a wM transfer and the yield has been claimed to carol for the pool.
        assertEq(_wrappedMToken.balanceOf(_carol), _carolBalanceOfWM += _morphoAccruedYield);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM += 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM -= 1_000_000e6);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoFactory), _morphoAccruedYield -= _morphoAccruedYield);

        /* ============ Alice Withdraws Seed USDC For Loans ============ */

        _withdraw(_alice, _USDC, 1_000_000e6, _alice);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC += 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC -= 1_000_000e6);

        // /* ============ Second 1-Year Time Warp ============ */

        // Move 1 year forward and check that yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 85_862_309962);

        // `startEarningFor` has been called so wM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoFactory), _morphoAccruedYield += 41226);

        // But excess yield has accrued in the wrapped M contract.
        assertEq(_wrappedMToken.excess(), 127_097_654719);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC);
    }

    function test_morphoBlue_earning_wM_as_loanToken() public {
        /* ============ Alice Creates Market ============ */

        _giveM(_alice, 1_000_100e6);
        _wrap(_alice, _alice, 1_000_100e6);

        assertEq(_mToken.balanceOf(_alice), 0);
        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM += 1_000_099_999999);
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 1_000_099_999999);

        deal(_USDC, _alice, 1_000_100e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC += 1_000_100e6);

        // NOTE: Creating a market also result in `_alice` supplying 1.00 wM as supply, 1.00 USDC as collateral, and
        //       borrowing 0.90 wM.
        _createMarket(_alice, address(_wrappedMToken), _USDC);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM -= 100000);
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM += 100000);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC -= 1e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC += 1e6);

        /* ============ Alice Supplies Seed wM For Loans ============ */

        _supply(_alice, address(_wrappedMToken), 1_000_000e6);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM -= 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM += 1_000_000e6);

        /* ============ Bob Takes Out wM Loan Against USDC Collateral ============ */

        deal(_USDC, _bob, 1_000_000e6);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC += 1_000_000e6);

        _supplyCollateral(_bob, _USDC, 1_000_000e6);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC -= 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC += 1_000_000e6);

        _borrow(_bob, address(_wrappedMToken), 900_000e6, _bob);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM += 900_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM -= 900_000e6);

        /* ============ Morpho Becomes An Earner ============ */

        _setClaimOverrideRecipient(_morphoFactory, _carol);

        _addToList(_EARNERS_LIST, _morphoFactory);
        _wrappedMToken.startEarningFor(_morphoFactory);

        // Check that the pool is earning wM.
        assertTrue(_wrappedMToken.isEarning(_morphoFactory));

        assertEq(_wrappedMToken.claimOverrideRecipientFor(_morphoFactory), _carol);

        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoFactory), _morphoAccruedYield);

        /* ============ First 1-Year Time Warp ============ */

        // Move 1 year forward and check that yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 51_276_223485);

        // `startEarningFor` has been called so wM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoFactory), _morphoAccruedYield += 5_127_114764);

        // But excess yield has accrued in the wrapped M contract.
        assertEq(_wrappedMToken.excess(), 46_149_108719);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC);

        /* ============ Bob Repays wM Loan And Withdraws USDC Collateral ============ */

        _repay(_bob, address(_wrappedMToken), 900_000e6);

        // The repay has triggered a wM transfer and the yield has been claimed to carol for the pool.
        assertEq(_wrappedMToken.balanceOf(_carol), _carolBalanceOfWM += _morphoAccruedYield);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM -= 900_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM += 900_000e6);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoFactory), _morphoAccruedYield -= _morphoAccruedYield);

        _withdrawCollateral(_bob, _USDC, 1_000_000e6, _bob);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC += 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC -= 1_000_000e6);

        /* ============ Alice Withdraws Seed wM For Loans ============ */

        _withdraw(_alice, address(_wrappedMToken), 1_000_000e6, _alice);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM += 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM -= 1_000_000e6);

        /* ============ Second 1-Year Time Warp ============ */

        // Move 1 year forward and check that yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 53_905_211681);

        // `startEarningFor` has been called so wM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_morphoFactory), _morphoBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoFactory), _morphoAccruedYield += 5126);

        // But excess yield has accrued in the wrapped M contract.
        assertEq(_wrappedMToken.excess(), 100_054_315272);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_morphoFactory), _morphoBalanceOfUSDC);
    }

    function _createOracle() internal returns (address oracle_) {
        return
            IMorphoChainlinkOracleV2Factory(_oracleFactory).createMorphoChainlinkOracleV2(
                address(0),
                1,
                address(0),
                address(0),
                6,
                address(0),
                1,
                address(0),
                address(0),
                6,
                bytes32(0)
            );
    }

    function _createMarket(address account_, address loanToken_, address collateralToken_) internal {
        IMorphoBlueFactory.MarketParams memory marketParams_ = IMorphoBlueFactory.MarketParams({
            loanToken: loanToken_,
            collateralToken: collateralToken_,
            oracle: _oracle,
            irm: address(0),
            lltv: _LLTV
        });

        vm.prank(account_);
        IMorphoBlueFactory(_morphoFactory).createMarket(marketParams_);

        _supply(account_, loanToken_, 1_000000);

        // NOTE: Put up arbitrarily more than necessary as collateral because Morpho contract seems to lack critical
        //       getter to determine additional collateral needed for some additional borrow amount.
        _supplyCollateral(account_, collateralToken_, 1_000000);

        _borrow(account_, loanToken_, 900000, account_);
    }

    function _approve(address token_, address account_, address spender_, uint256 amount_) internal {
        vm.prank(account_);
        IERC20(token_).approve(spender_, amount_);
    }

    function _transfer(address token_, address sender_, address recipient_, uint256 amount_) internal {
        vm.prank(sender_);
        IERC20(token_).transfer(recipient_, amount_);
    }

    function _supplyCollateral(address account_, address collateralToken_, uint256 amount_) internal {
        _approve(collateralToken_, account_, _morphoFactory, amount_);

        IMorphoBlueFactory.MarketParams memory marketParams_ = IMorphoBlueFactory.MarketParams({
            loanToken: collateralToken_ == address(_wrappedMToken) ? _USDC : address(_wrappedMToken),
            collateralToken: collateralToken_,
            oracle: _oracle,
            irm: address(0),
            lltv: _LLTV
        });

        vm.prank(account_);
        IMorphoBlueFactory(_morphoFactory).supplyCollateral(marketParams_, amount_, account_, hex"");
    }

    function _withdrawCollateral(
        address account_,
        address collateralToken_,
        uint256 amount_,
        address receiver_
    ) internal {
        IMorphoBlueFactory.MarketParams memory marketParams_ = IMorphoBlueFactory.MarketParams({
            loanToken: collateralToken_ == address(_wrappedMToken) ? _USDC : address(_wrappedMToken),
            collateralToken: collateralToken_,
            oracle: _oracle,
            irm: address(0),
            lltv: _LLTV
        });

        vm.prank(account_);
        IMorphoBlueFactory(_morphoFactory).withdrawCollateral(marketParams_, amount_, account_, receiver_);
    }

    function _supply(
        address account_,
        address loanToken_,
        uint256 amount_
    ) internal returns (uint256 assetsSupplied_, uint256 sharesSupplied_) {
        _approve(loanToken_, account_, _morphoFactory, amount_);

        IMorphoBlueFactory.MarketParams memory marketParams_ = IMorphoBlueFactory.MarketParams({
            loanToken: loanToken_,
            collateralToken: loanToken_ == address(_wrappedMToken) ? _USDC : address(_wrappedMToken),
            oracle: _oracle,
            irm: address(0),
            lltv: _LLTV
        });

        vm.prank(account_);
        return IMorphoBlueFactory(_morphoFactory).supply(marketParams_, amount_, 0, account_, hex"");
    }

    function _withdraw(
        address account_,
        address loanToken_,
        uint256 amount_,
        address receiver_
    ) internal returns (uint256 assetsWithdrawn_, uint256 sharesWithdrawn_) {
        IMorphoBlueFactory.MarketParams memory marketParams_ = IMorphoBlueFactory.MarketParams({
            loanToken: loanToken_,
            collateralToken: loanToken_ == address(_wrappedMToken) ? _USDC : address(_wrappedMToken),
            oracle: _oracle,
            irm: address(0),
            lltv: _LLTV
        });

        vm.prank(account_);
        return IMorphoBlueFactory(_morphoFactory).withdraw(marketParams_, amount_, 0, account_, receiver_);
    }

    function _borrow(
        address account_,
        address loanToken_,
        uint256 amount_,
        address receiver_
    ) internal returns (uint256 assetsBorrowed_, uint256 sharesBorrowed_) {
        IMorphoBlueFactory.MarketParams memory marketParams_ = IMorphoBlueFactory.MarketParams({
            loanToken: loanToken_,
            collateralToken: loanToken_ == address(_wrappedMToken) ? _USDC : address(_wrappedMToken),
            oracle: _oracle,
            irm: address(0),
            lltv: _LLTV
        });

        vm.prank(account_);
        return IMorphoBlueFactory(_morphoFactory).borrow(marketParams_, amount_, 0, account_, receiver_);
    }

    function _repay(
        address account_,
        address loanToken_,
        uint256 amount_
    ) internal returns (uint256 assetsRepaid_, uint256 sharesRepaid_) {
        _approve(loanToken_, account_, _morphoFactory, amount_);

        IMorphoBlueFactory.MarketParams memory marketParams_ = IMorphoBlueFactory.MarketParams({
            loanToken: loanToken_,
            collateralToken: loanToken_ == address(_wrappedMToken) ? _USDC : address(_wrappedMToken),
            oracle: _oracle,
            irm: address(0),
            lltv: _LLTV
        });

        vm.prank(account_);
        return IMorphoBlueFactory(_morphoFactory).repay(marketParams_, amount_, 0, account_, hex"");
    }
}
