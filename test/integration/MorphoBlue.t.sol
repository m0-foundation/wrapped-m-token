// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { TestBase } from "./TestBase.sol";

import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";

import { MarketParams, IMorphoBlueLike, IMorphoChainlinkOracleV2Factory } from "./vendor/morpho-blue/Interfaces.sol";

contract MorphoBlueTests is TestBase {
    // Morpho Blue factory on Ethereum Mainnet
    address internal constant _morphoBlue = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    // Oracle factory on Ethereum Mainnet
    address internal constant _oracleFactory = 0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766;

    // USDC on Ethereum Mainnet
    address internal constant _USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

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

    uint240 internal _excess;

    function setUp() external {
        _oracle = _createOracle();

        _wrapperBalanceOfM = _mToken.balanceOf(address(_wrappedMToken));

        _morphoBalanceOfUSDC = IERC20(_USDC).balanceOf(_morphoBlue);
        _morphoBalanceOfWM = _wrappedMToken.balanceOf(_morphoBlue);

        _excess = _wrappedMToken.excess();
    }

    function test_state() external view {
        assertTrue(_mToken.isEarning(address(_wrappedMToken)));
        assertTrue(_wrappedMToken.isEarningEnabled());
        assertFalse(_wrappedMToken.isEarning(_morphoBlue));
    }

    function test_morphoBlue_nonEarning_wM_as_collateralToken() external {
        /* ============ Alice Creates Market ============ */

        _giveWM(_alice, 1_000_100e6);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM += 1_000_100e6);

        deal(_USDC, _alice, 1_000_100e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC += 1_000_100e6);

        // NOTE: Creating a market also result in `_alice` supplying 1.00 USDC as supply, 1.00 wM as collateral, and
        //       borrowing 0.90 USDC.
        _createMarket(_alice, _USDC, address(_wrappedMToken));

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM -= 1e6);
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM += 1e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC -= 100000);
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC += 100000);

        /* ============ Alice Supplies Seed USDC For Loans ============ */

        _supply(_alice, _USDC, 1_000_000e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC -= 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC += 1_000_000e6);

        /* ============ Bob Takes Out USDC Loan Against wM Collateral ============ */

        _giveWM(_bob, 1_000_100e6);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM += 1_000_100e6);

        _supplyCollateral(_bob, address(_wrappedMToken), 1_000_000e6);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM -= 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM += 1_000_000e6);

        _borrow(_bob, _USDC, 900_000e6, _bob);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC += 900_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC -= 900_000e6);

        /* ============ First 1-Year Time Warp ============ */

        // Move 1 year forward and check that no yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 383_154_367021);

        // `startEarningFor` hasn't been called so no wM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoBlue), _morphoAccruedYield);

        // But excess yield has accrued in the wrapped M contract.
        assertEq(_wrappedMToken.excess(), _excess += 383_154_367021);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC);

        /* ============ Bob Repays USDC Loan And Withdraws wM Collateral ============ */

        _repay(_bob, _USDC, 900_000e6);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC -= 900_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC += 900_000e6);

        _withdrawCollateral(_bob, address(_wrappedMToken), 1_000_000e6, _bob);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM += 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM -= 1_000_000e6);

        /* ============ Alice Withdraws Seed USDC For Loans ============ */

        _withdraw(_alice, _USDC, 1_000_000e6, _alice);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC += 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC -= 1_000_000e6);

        /* ============ Second 1-Year Time Warp ============ */

        // Move 1 year forward and check that no yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 391_011_884644);

        // `startEarningFor` hasn't been called so no wM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoBlue), _morphoAccruedYield);

        // But excess yield has accrued in the wrapped M contract.
        assertEq(_wrappedMToken.excess(), _excess += 391_011_884644);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC);
    }

    function test_morphoBlue_nonEarning_wM_as_loanToken() external {
        /* ============ Alice Creates Market ============ */

        _giveWM(_alice, 1_000_100e6);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM += 1_000_100e6);

        deal(_USDC, _alice, 1_000_100e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC += 1_000_100e6);

        // NOTE: Creating a market also result in `_alice` supplying 1.00 wM as supply, 1.00 USDC as collateral, and
        //       borrowing 0.90 wM.
        _createMarket(_alice, address(_wrappedMToken), _USDC);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM -= 100000);
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM += 100000);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC -= 1e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC += 1e6);

        /* ============ Alice Supplies Seed wM For Loans ============ */

        _supply(_alice, address(_wrappedMToken), 1_000_000e6);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM -= 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM += 1_000_000e6);

        /* ============ Bob Takes Out wM Loan Against USDC Collateral ============ */

        deal(_USDC, _bob, 1_000_000e6);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC += 1_000_000e6);

        _supplyCollateral(_bob, _USDC, 1_000_000e6);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC -= 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC += 1_000_000e6);

        _borrow(_bob, address(_wrappedMToken), 900_000e6, _bob);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM += 900_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM -= 900_000e6);

        /* ============ First 1-Year Time Warp ============ */

        // Move 1 year forward and check that no yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 383_154_367021);

        // `startEarningFor` hasn't been called so no wM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoBlue), _morphoAccruedYield);

        // But excess yield has accrued in the wrapped M contract.
        assertEq(_wrappedMToken.excess(), _excess += 383_154_367021);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC);

        /* ============ Bob Repays wM Loan And Withdraws USDC Collateral ============ */

        _repay(_bob, address(_wrappedMToken), 900_000e6);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM -= 900_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM += 900_000e6);

        _withdrawCollateral(_bob, _USDC, 1_000_000e6, _bob);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC += 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC -= 1_000_000e6);

        /* ============ Alice Withdraws Seed wM For Loans ============ */

        _withdraw(_alice, address(_wrappedMToken), 1_000_000e6, _alice);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM += 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM -= 1_000_000e6);

        /* ============ Second 1-Year Time Warp ============ */

        // Move 1 year forward and check that no yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 391_011_884644);

        // `startEarningFor` hasn't been called so no wM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoBlue), _morphoAccruedYield);

        // But excess yield has accrued in the wrapped M contract.
        assertEq(_wrappedMToken.excess(), _excess += 391_011_884644);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC);
    }

    function test_morphoBlue_earning_wM_as_collateralToken() public {
        /* ============ Alice Creates Market ============ */

        _giveWM(_alice, 1_000_100e6);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM += 1_000_100e6);

        deal(_USDC, _alice, 1_000_100e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC += 1_000_100e6);

        // NOTE: Creating a market also result in `_alice` supplying 1.00 USDC as supply, 1.00 wM as collateral, and
        //       borrowing 0.90 USDC.
        _createMarket(_alice, _USDC, address(_wrappedMToken));

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM -= 1e6);
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM += 1e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC -= 100000);
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC += 100000);

        /* ============ Alice Supplies Seed USDC For Loans ============ */

        _supply(_alice, _USDC, 1_000_000e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC -= 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC += 1_000_000e6);

        /* ============ Bob Takes Out USDC Loan Against wM Collateral ============ */

        _giveWM(_bob, 1_000_100e6);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM += 1_000_100e6);

        _supplyCollateral(_bob, address(_wrappedMToken), 1_000_000e6);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM -= 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM += 1_000_000e6);

        _borrow(_bob, _USDC, 900_000e6, _bob);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC += 900_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC -= 900_000e6);

        /* ============ Morpho Becomes An Earner ============ */

        _setClaimOverrideRecipient(_morphoBlue, _carol);

        _addToList(_EARNERS_LIST, _morphoBlue);
        _wrappedMToken.startEarningFor(_morphoBlue);

        // Check that the pool is earning wM.
        assertTrue(_wrappedMToken.isEarning(_morphoBlue));

        assertEq(_wrappedMToken.claimOverrideRecipientFor(_morphoBlue), _carol);

        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoBlue), _morphoAccruedYield);

        /* ============ First 1-Year Time Warp ============ */

        // Move 1 year forward and check that yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 383_154_367021);

        // `startEarningFor` has been called so wM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoBlue), _morphoAccruedYield += 20_507_491868);

        // But excess yield has accrued in the wrapped M contract.
        assertEq(_wrappedMToken.excess(), _excess += 362_646_875152);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC);

        /* ============ Bob Repays USDC Loan And Withdraws wM Collateral ============ */

        _repay(_bob, _USDC, 900_000e6);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC -= 900_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC += 900_000e6);

        _withdrawCollateral(_bob, address(_wrappedMToken), 1_000_000e6, _bob);

        // The collateral withdrawal has triggered a wM transfer and the yield has been claimed to carol for the pool.
        assertEq(_wrappedMToken.balanceOf(_carol), _carolBalanceOfWM += _morphoAccruedYield);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM += 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM -= 1_000_000e6);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoBlue), _morphoAccruedYield -= _morphoAccruedYield);

        /* ============ Alice Withdraws Seed USDC For Loans ============ */

        _withdraw(_alice, _USDC, 1_000_000e6, _alice);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC += 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC -= 1_000_000e6);

        // /* ============ Second 1-Year Time Warp ============ */

        // Move 1 year forward and check that yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 391_011_884644);

        // `startEarningFor` has been called so wM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoBlue), _morphoAccruedYield += 45526);

        // But excess yield has accrued in the wrapped M contract.
        assertEq(_wrappedMToken.excess(), _excess += 391_011_839116);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC);
    }

    function test_morphoBlue_earning_wM_as_loanToken() public {
        /* ============ Alice Creates Market ============ */

        _giveWM(_alice, 1_000_100e6);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM += 1_000_100e6);

        deal(_USDC, _alice, 1_000_100e6);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC += 1_000_100e6);

        // NOTE: Creating a market also result in `_alice` supplying 1.00 wM as supply, 1.00 USDC as collateral, and
        //       borrowing 0.90 wM.
        _createMarket(_alice, address(_wrappedMToken), _USDC);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM -= 100000);
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM += 100000);

        assertEq(IERC20(_USDC).balanceOf(_alice), _aliceBalanceOfUSDC -= 1e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC += 1e6);

        /* ============ Alice Supplies Seed wM For Loans ============ */

        _supply(_alice, address(_wrappedMToken), 1_000_000e6);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM -= 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM += 1_000_000e6);

        /* ============ Bob Takes Out wM Loan Against USDC Collateral ============ */

        deal(_USDC, _bob, 1_000_000e6);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC += 1_000_000e6);

        _supplyCollateral(_bob, _USDC, 1_000_000e6);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC -= 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC += 1_000_000e6);

        _borrow(_bob, address(_wrappedMToken), 900_000e6, _bob);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM += 900_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM -= 900_000e6);

        /* ============ Morpho Becomes An Earner ============ */

        _setClaimOverrideRecipient(_morphoBlue, _carol);

        _addToList(_EARNERS_LIST, _morphoBlue);
        _wrappedMToken.startEarningFor(_morphoBlue);

        // Check that the pool is earning wM.
        assertTrue(_wrappedMToken.isEarning(_morphoBlue));

        assertEq(_wrappedMToken.claimOverrideRecipientFor(_morphoBlue), _carol);

        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoBlue), _morphoAccruedYield);

        /* ============ First 1-Year Time Warp ============ */

        // Move 1 year forward and check that yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 383_154_367021);

        // `startEarningFor` has been called so wM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoBlue), _morphoAccruedYield += 2_050_771703);

        // But excess yield has accrued in the wrapped M contract.
        assertEq(_wrappedMToken.excess(), _excess += 381_103_595317);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC);

        /* ============ Bob Repays wM Loan And Withdraws USDC Collateral ============ */

        _repay(_bob, address(_wrappedMToken), 900_000e6);

        // The repay has triggered a wM transfer and the yield has been claimed to carol for the pool.
        assertEq(_wrappedMToken.balanceOf(_carol), _carolBalanceOfWM += _morphoAccruedYield);

        assertEq(_wrappedMToken.balanceOf(_bob), _bobBalanceOfWM -= 900_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM += 900_000e6);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoBlue), _morphoAccruedYield -= _morphoAccruedYield);

        _withdrawCollateral(_bob, _USDC, 1_000_000e6, _bob);

        assertEq(IERC20(_USDC).balanceOf(_bob), _bobBalanceOfUSDC += 1_000_000e6);
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC -= 1_000_000e6);

        /* ============ Alice Withdraws Seed wM For Loans ============ */

        _withdraw(_alice, address(_wrappedMToken), 1_000_000e6, _alice);

        assertEq(_wrappedMToken.balanceOf(_alice), _aliceBalanceOfWM += 1_000_000e6);
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM -= 1_000_000e6);

        /* ============ Second 1-Year Time Warp ============ */

        // Move 1 year forward and check that yield has accrued.
        vm.warp(vm.getBlockTimestamp() + 365 days);

        // Wrapped M is earning M and has accrued yield.
        assertEq(_mToken.balanceOf(address(_wrappedMToken)), _wrapperBalanceOfM += 391_011_884644);

        // `startEarningFor` has been called so wM yield has accrued in the pool.
        assertEq(_wrappedMToken.balanceOf(_morphoBlue), _morphoBalanceOfWM);
        assertEq(_wrappedMToken.accruedYieldOf(_morphoBlue), _morphoAccruedYield += 27069);

        // But excess yield has accrued in the wrapped M contract.
        assertEq(_wrappedMToken.excess(), _excess += 391_011_857572);

        // USDC balance is unchanged.
        assertEq(IERC20(_USDC).balanceOf(_morphoBlue), _morphoBalanceOfUSDC);
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
        MarketParams memory marketParams_ = MarketParams({
            loanToken: loanToken_,
            collateralToken: collateralToken_,
            oracle: _oracle,
            irm: address(0),
            lltv: _LLTV
        });

        vm.prank(account_);
        IMorphoBlueLike(_morphoBlue).createMarket(marketParams_);

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
        _approve(collateralToken_, account_, _morphoBlue, amount_);

        MarketParams memory marketParams_ = MarketParams({
            loanToken: collateralToken_ == address(_wrappedMToken) ? _USDC : address(_wrappedMToken),
            collateralToken: collateralToken_,
            oracle: _oracle,
            irm: address(0),
            lltv: _LLTV
        });

        vm.prank(account_);
        IMorphoBlueLike(_morphoBlue).supplyCollateral(marketParams_, amount_, account_, hex"");
    }

    function _withdrawCollateral(
        address account_,
        address collateralToken_,
        uint256 amount_,
        address receiver_
    ) internal {
        MarketParams memory marketParams_ = MarketParams({
            loanToken: collateralToken_ == address(_wrappedMToken) ? _USDC : address(_wrappedMToken),
            collateralToken: collateralToken_,
            oracle: _oracle,
            irm: address(0),
            lltv: _LLTV
        });

        vm.prank(account_);
        IMorphoBlueLike(_morphoBlue).withdrawCollateral(marketParams_, amount_, account_, receiver_);
    }

    function _supply(
        address account_,
        address loanToken_,
        uint256 amount_
    ) internal returns (uint256 assetsSupplied_, uint256 sharesSupplied_) {
        _approve(loanToken_, account_, _morphoBlue, amount_);

        MarketParams memory marketParams_ = MarketParams({
            loanToken: loanToken_,
            collateralToken: loanToken_ == address(_wrappedMToken) ? _USDC : address(_wrappedMToken),
            oracle: _oracle,
            irm: address(0),
            lltv: _LLTV
        });

        vm.prank(account_);
        return IMorphoBlueLike(_morphoBlue).supply(marketParams_, amount_, 0, account_, hex"");
    }

    function _withdraw(
        address account_,
        address loanToken_,
        uint256 amount_,
        address receiver_
    ) internal returns (uint256 assetsWithdrawn_, uint256 sharesWithdrawn_) {
        MarketParams memory marketParams_ = MarketParams({
            loanToken: loanToken_,
            collateralToken: loanToken_ == address(_wrappedMToken) ? _USDC : address(_wrappedMToken),
            oracle: _oracle,
            irm: address(0),
            lltv: _LLTV
        });

        vm.prank(account_);
        return IMorphoBlueLike(_morphoBlue).withdraw(marketParams_, amount_, 0, account_, receiver_);
    }

    function _borrow(
        address account_,
        address loanToken_,
        uint256 amount_,
        address receiver_
    ) internal returns (uint256 assetsBorrowed_, uint256 sharesBorrowed_) {
        MarketParams memory marketParams_ = MarketParams({
            loanToken: loanToken_,
            collateralToken: loanToken_ == address(_wrappedMToken) ? _USDC : address(_wrappedMToken),
            oracle: _oracle,
            irm: address(0),
            lltv: _LLTV
        });

        vm.prank(account_);
        return IMorphoBlueLike(_morphoBlue).borrow(marketParams_, amount_, 0, account_, receiver_);
    }

    function _repay(
        address account_,
        address loanToken_,
        uint256 amount_
    ) internal returns (uint256 assetsRepaid_, uint256 sharesRepaid_) {
        _approve(loanToken_, account_, _morphoBlue, amount_);

        MarketParams memory marketParams_ = MarketParams({
            loanToken: loanToken_,
            collateralToken: loanToken_ == address(_wrappedMToken) ? _USDC : address(_wrappedMToken),
            oracle: _oracle,
            irm: address(0),
            lltv: _LLTV
        });

        vm.prank(account_);
        return IMorphoBlueLike(_morphoBlue).repay(marketParams_, amount_, 0, account_, hex"");
    }
}
