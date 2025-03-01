// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IEarnerManager } from "../../src/interfaces/IEarnerManager.sol";
import { IWrappedMToken } from "../../src/interfaces/IWrappedMToken.sol";

import { DeployBase } from "../../script/DeployBase.sol";

contract UpgradeTests is Test, DeployBase {
    address internal constant _WRAPPED_M_TOKEN = 0x437cc33344a0B27A429f795ff6B469C72698B291;
    address internal constant _REGISTRAR = 0x119FbeeDD4F4f4298Fb59B720d5654442b81ae2c;
    address internal constant _M_TOKEN = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;
    address internal constant _WRAPPED_M_MIGRATION_ADMIN = 0x431169728D75bd02f4053435b87D15c8d1FB2C72;
    address internal constant _EARNER_MANAGER_MIGRATION_ADMIN = 0x431169728D75bd02f4053435b87D15c8d1FB2C72;
    address internal constant _EXCESS_DESTINATION = 0xd7298f620B0F752Cf41BD818a16C756d9dCAA34f; // Vault
    address internal constant _DEPLOYER = 0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB;

    uint64 internal constant _DEPLOYER_NONCE = 50;

    address[] internal _earners = [
        0x437cc33344a0B27A429f795ff6B469C72698B291,
        0x0502d65f26f45d17503E4d34441F5e73Ea143033,
        0x061110360ba50E19139a1Bf2EaF4004FB0dD31e8,
        0x9106CBf2C882340b23cC40985c05648173E359e7,
        0x846E7F810E08F1E2AF2c5AfD06847cc95F5CaE1B,
        0x967B10c27454CC5b1b1Eeb163034ACdE13Fe55e2,
        0xCF3166181848eEC4Fd3b9046aE7CB582F34d2e6c,
        0xea0C048c728578b1510EBDF9b692E8936D6Fbc90,
        0xdd82875f0840AAD58a455A70B88eEd9F59ceC7c7,
        0x184d597Be309e11650ca6c935B483DcC05551578,
        0xA259E266a43F3070CecD80F05C8947aB93c074Ba,
        0x0f71a8e95A918A4A984Ad3841414cD00D9C13e7d,
        0xf3CfA6e51b2B580AE6Ad71e2D719Ab09e4A0D7aa,
        0x56721131d21a170fBb084734DcC399A278234298,
        0xa969cFCd9e583edb8c8B270Dc8CaFB33d6Cf662D,
        0xDeD796De6a14E255487191963dEe436c45995813,
        0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb,
        0x8F9139Fe15E561De5fCe39DB30856924Dd67Af0e,
        0x970A7749EcAA4394C8B2Bf5F2471F41FD6b79288,
        0xB65a66621D7dE34afec9b9AC0755133051550dD7,
        0xcAD001c30E96765aC90307669d578219D4fb1DCe,
        0x9F6d1a62bf268Aa05a1218CFc89C69833D2d2a70,
        0x9c6e67fA86138Ab49359F595BfE4Fb163D0f16cc,
        0xABFD9948933b975Ee9a668a57C776eCf73F6D840,
        0x7FDA203f6F77545548E984133be62693bCD61497,
        0xa8687A15D4BE32CC8F0a8a7B9704a4C3993D9613,
        0x3f0376da3Ae4313E7a5F1dA184BAFC716252d759,
        0x569D7dccBF6923350521ecBC28A555A500c4f0Ec,
        0xcEa14C3e9Afc5822d44ADe8d006fCFBAb60f7a21,
        0x81ad394C0Fa87e99Ca46E1aca093BEe020f203f4,
        0x4Cbc25559DbBD1272EC5B64c7b5F48a2405e6470,
        0x13Ccb6E28F22E2f6783BaDedCe32cc74583A3647,
        0x985DE23260743c2c2f09BFdeC50b048C7a18c461,
        0xD925C84b55E4e44a53749fF5F2a5A13F63D128fd,
        0x20b3a4119eAB75ffA534aC8fC5e9160BdcaF442b
    ];

    function test_upgrade() external {
        vm.setNonce(_DEPLOYER, _DEPLOYER_NONCE);

        (
            address expectedEarnerManagerImplementation_,
            address expectedEarnerManagerProxy_,
            address expectedWrappedMTokenImplementation_,
            address expectedWrappedMTokenMigrator_
        ) = mockDeployUpgrade(_DEPLOYER, _DEPLOYER_NONCE);

        address[] memory earners_ = new address[](_earners.length);

        for (uint256 index_; index_ < _earners.length; ++index_) {
            earners_[index_] = _earners[index_];
        }

        vm.startPrank(_DEPLOYER);
        (
            address earnerManagerImplementation_,
            address earnerManagerProxy_,
            address wrappedMTokenImplementation_,
            address wrappedMTokenMigrator_
        ) = deployUpgrade(
                _M_TOKEN,
                _REGISTRAR,
                _EXCESS_DESTINATION,
                _WRAPPED_M_MIGRATION_ADMIN,
                _EARNER_MANAGER_MIGRATION_ADMIN,
                earners_
            );
        vm.stopPrank();

        // Earner Manager Implementation assertions
        assertEq(earnerManagerImplementation_, expectedEarnerManagerImplementation_);
        assertEq(IEarnerManager(earnerManagerImplementation_).registrar(), _REGISTRAR);

        // Earner Manager Proxy assertions
        assertEq(earnerManagerProxy_, expectedEarnerManagerProxy_);
        assertEq(IEarnerManager(earnerManagerProxy_).registrar(), _REGISTRAR);
        assertEq(IEarnerManager(earnerManagerProxy_).implementation(), earnerManagerImplementation_);

        // Wrapped M Token Implementation assertions
        assertEq(wrappedMTokenImplementation_, expectedWrappedMTokenImplementation_);
        assertEq(IWrappedMToken(wrappedMTokenImplementation_).earnerManager(), earnerManagerProxy_);
        assertEq(IWrappedMToken(wrappedMTokenImplementation_).migrationAdmin(), _WRAPPED_M_MIGRATION_ADMIN);
        assertEq(IWrappedMToken(wrappedMTokenImplementation_).mToken(), _M_TOKEN);
        assertEq(IWrappedMToken(wrappedMTokenImplementation_).registrar(), _REGISTRAR);
        assertEq(IWrappedMToken(wrappedMTokenImplementation_).excessDestination(), _EXCESS_DESTINATION);

        // Migrator assertions
        assertEq(wrappedMTokenMigrator_, expectedWrappedMTokenMigrator_);

        uint240 totalEarningSupply_ = IWrappedMToken(_WRAPPED_M_TOKEN).totalEarningSupply();
        uint256[] memory balancesWithYield_ = new uint256[](_earners.length);

        for (uint256 index_; index_ < _earners.length; ++index_) {
            balancesWithYield_[index_] = IWrappedMToken(_WRAPPED_M_TOKEN).balanceWithYieldOf(_earners[index_]);
        }

        vm.prank(IWrappedMToken(_WRAPPED_M_TOKEN).migrationAdmin());
        IWrappedMToken(_WRAPPED_M_TOKEN).migrate(wrappedMTokenMigrator_);

        // Wrapped M Token Proxy assertions
        assertEq(IWrappedMToken(_WRAPPED_M_TOKEN).earnerManager(), earnerManagerProxy_);
        assertEq(IWrappedMToken(_WRAPPED_M_TOKEN).migrationAdmin(), _WRAPPED_M_MIGRATION_ADMIN);
        assertEq(IWrappedMToken(_WRAPPED_M_TOKEN).mToken(), _M_TOKEN);
        assertEq(IWrappedMToken(_WRAPPED_M_TOKEN).registrar(), _REGISTRAR);
        assertEq(IWrappedMToken(_WRAPPED_M_TOKEN).excessDestination(), _EXCESS_DESTINATION);
        assertEq(IWrappedMToken(_WRAPPED_M_TOKEN).implementation(), wrappedMTokenImplementation_);

        // Relevant storage slots.
        assertEq(IWrappedMToken(_WRAPPED_M_TOKEN).totalEarningSupply(), totalEarningSupply_);

        for (uint256 index_; index_ < _earners.length; ++index_) {
            assertEq(IWrappedMToken(_WRAPPED_M_TOKEN).balanceWithYieldOf(_earners[index_]), balancesWithYield_[index_]);
        }
    }
}
