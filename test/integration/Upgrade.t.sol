// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Test } from "../../lib/forge-std/src/Test.sol";

import {
    IAccessControl
} from "../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import {
    Initializable
} from "../../lib/common/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import { IWrappedMToken } from "../../src/interfaces/IWrappedMToken.sol";

import { DeployBase } from "../../script/DeployBase.sol";

import { WrappedMToken } from "../../src/WrappedMToken.sol";

contract UpgradeTests is Test, DeployBase {
    WrappedMToken internal constant _WRAPPED_M_TOKEN = WrappedMToken(0x437cc33344a0B27A429f795ff6B469C72698B291);
    address internal constant _REGISTRAR = 0x119FbeeDD4F4f4298Fb59B720d5654442b81ae2c;
    address internal constant _M_TOKEN = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;
    address internal constant _WRAPPED_M_MIGRATION_ADMIN = 0x431169728D75bd02f4053435b87D15c8d1FB2C72;
    address internal constant _EXCESS_DESTINATION = 0xd7298f620B0F752Cf41BD818a16C756d9dCAA34f; // Vault
    address internal constant _SWAP_FACILITY = 0xB6807116b3B1B321a390594e31ECD6e0076f6278;

    address internal constant _DEPLOYER = 0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB;
    uint64 internal constant _DEPLOYER_NONCE = 195;

    address internal constant _ADMIN = 0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB;
    address internal constant _FREEZE_MANAGER = 0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB;
    address internal constant _PAUSER = 0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB;
    address internal constant _FORCED_TRANSFER_MANAGER = 0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB;

    address[] internal _earners = [
        0x4Cbc25559DbBD1272EC5B64c7b5F48a2405e6470,
        0xfF95c5f35F4ffB9d5f596F898ac1ae38D62749c2,
        0x0502d65f26f45d17503E4d34441F5e73Ea143033,
        0x970A7749EcAA4394C8B2Bf5F2471F41FD6b79288,
        0x81ad394C0Fa87e99Ca46E1aca093BEe020f203f4,
        0xfE940BFE535013a52e8e2DF9644f95E3C94fa14B,
        0xE0663f2372cAa1459b7ade90812Dc737CE587FA6,
        0xa969cFCd9e583edb8c8B270Dc8CaFB33d6Cf662D,
        0x9c6e67fA86138Ab49359F595BfE4Fb163D0f16cc,
        0xdd82875f0840AAD58a455A70B88eEd9F59ceC7c7,
        0xB65a66621D7dE34afec9b9AC0755133051550dD7,
        0xcAD001c30E96765aC90307669d578219D4fb1DCe,
        0xDeD796De6a14E255487191963dEe436c45995813,
        0xea0C048c728578b1510EBDF9b692E8936D6Fbc90,
        0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb,
        0x13Ccb6E28F22E2f6783BaDedCe32cc74583A3647,
        0x985DE23260743c2c2f09BFdeC50b048C7a18c461,
        0x7db685961F97c847A4C815D43E9cc0E5647328b9,
        0x48Afe17cB6363fD1aaeA50a8CB652C5978972c96,
        0xE72Fe64840F4EF80E3Ec73a1c749491b5c938CB9,
        0xCF3166181848eEC4Fd3b9046aE7CB582F34d2e6c,
        0xB50A1f651A5ACb2679c8f679D782c728f3702E53,
        0x9F6d1a62bf268Aa05a1218CFc89C69833D2d2a70,
        0x569D7dccBF6923350521ecBC28A555A500c4f0Ec
    ];

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 23_170_985);
    }

    function test_upgrade() external {
        vm.setNonce(_DEPLOYER, _DEPLOYER_NONCE);

        (address expectedWrappedMTokenImplementation_, address expectedWrappedMTokenMigrator_) = mockDeployUpgrade(
            _DEPLOYER,
            _DEPLOYER_NONCE
        );

        address[] memory earners_ = new address[](_earners.length);

        for (uint256 index_; index_ < _earners.length; ++index_) {
            earners_[index_] = _earners[index_];
        }

        vm.startPrank(_DEPLOYER);
        (address wrappedMTokenImplementation_, address wrappedMTokenMigrator_) = deployUpgrade(
            _M_TOKEN,
            _REGISTRAR,
            _EXCESS_DESTINATION,
            _SWAP_FACILITY,
            _WRAPPED_M_MIGRATION_ADMIN,
            earners_,
            _ADMIN,
            _FREEZE_MANAGER,
            _PAUSER,
            _FORCED_TRANSFER_MANAGER
        );
        vm.stopPrank();

        // Wrapped M Token Implementation assertions
        assertEq(wrappedMTokenImplementation_, expectedWrappedMTokenImplementation_);
        assertEq(IWrappedMToken(wrappedMTokenImplementation_).migrationAdmin(), _WRAPPED_M_MIGRATION_ADMIN);
        assertEq(IWrappedMToken(wrappedMTokenImplementation_).mToken(), _M_TOKEN);
        assertEq(IWrappedMToken(wrappedMTokenImplementation_).registrar(), _REGISTRAR);
        assertEq(IWrappedMToken(wrappedMTokenImplementation_).excessDestination(), _EXCESS_DESTINATION);
        assertEq(IWrappedMToken(wrappedMTokenImplementation_).swapFacility(), _SWAP_FACILITY);

        // Migrator assertions
        assertEq(wrappedMTokenMigrator_, expectedWrappedMTokenMigrator_);

        uint240 totalEarningSupply_ = IWrappedMToken(_WRAPPED_M_TOKEN).totalEarningSupply();
        uint256[] memory balancesWithYield_ = new uint256[](_earners.length);

        for (uint256 index_; index_ < _earners.length; ++index_) {
            balancesWithYield_[index_] = IWrappedMToken(_WRAPPED_M_TOKEN).balanceWithYieldOf(_earners[index_]);
        }

        vm.prank(_WRAPPED_M_TOKEN.migrationAdmin());
        _WRAPPED_M_TOKEN.migrate(wrappedMTokenMigrator_);

        // Wrapped M Token Proxy assertions
        assertEq(_WRAPPED_M_TOKEN.migrationAdmin(), _WRAPPED_M_MIGRATION_ADMIN);
        assertEq(_WRAPPED_M_TOKEN.mToken(), _M_TOKEN);
        assertEq(_WRAPPED_M_TOKEN.registrar(), _REGISTRAR);
        assertEq(_WRAPPED_M_TOKEN.excessDestination(), _EXCESS_DESTINATION);
        assertEq(_WRAPPED_M_TOKEN.swapFacility(), _SWAP_FACILITY);
        assertEq(_WRAPPED_M_TOKEN.implementation(), wrappedMTokenImplementation_);

        assertTrue(IAccessControl(address(_WRAPPED_M_TOKEN)).hasRole(bytes32(0x00), _ADMIN));
        assertTrue(IAccessControl(address(_WRAPPED_M_TOKEN)).hasRole(keccak256("PAUSER_ROLE"), _PAUSER));
        assertTrue(
            IAccessControl(address(_WRAPPED_M_TOKEN)).hasRole(keccak256("FREEZE_MANAGER_ROLE"), _FREEZE_MANAGER)
        );
        assertTrue(
            IAccessControl(address(_WRAPPED_M_TOKEN)).hasRole(
                keccak256("FORCED_TRANSFER_MANAGER_ROLE"),
                _FORCED_TRANSFER_MANAGER
            )
        );

        // Should not be able to call initialize again.
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        _WRAPPED_M_TOKEN.initialize(_ADMIN, _FREEZE_MANAGER, _PAUSER, _FORCED_TRANSFER_MANAGER);

        // Relevant storage slots.
        assertEq(_WRAPPED_M_TOKEN.totalEarningSupply(), totalEarningSupply_);

        for (uint256 index_; index_ < _earners.length; ++index_) {
            assertEq(_WRAPPED_M_TOKEN.balanceWithYieldOf(_earners[index_]), balancesWithYield_[index_]);
        }
    }
}
