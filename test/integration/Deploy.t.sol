// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IEarnerManager } from "../../src/interfaces/IEarnerManager.sol";
import { ISmartMToken } from "../../src/interfaces/ISmartMToken.sol";

import { DeployBase } from "../../script/DeployBase.sol";

contract Deploy is Test, DeployBase {
    address internal constant _REGISTRAR = 0x119FbeeDD4F4f4298Fb59B720d5654442b81ae2c;
    address internal constant _M_TOKEN = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;
    address internal constant _MIGRATION_ADMIN = 0x431169728D75bd02f4053435b87D15c8d1FB2C72;
    address internal constant _EXCESS_DESTINATION = 0xd7298f620B0F752Cf41BD818a16C756d9dCAA34f; // Vault
    address internal constant _DEPLOYER = 0xF2f1ACbe0BA726fEE8d75f3E32900526874740BB;
    uint256 internal constant _DEPLOYER_NONCE = 50;

    function test_deploy() external {
        vm.setNonce(_DEPLOYER, uint64(_DEPLOYER_NONCE));

        vm.startPrank(_DEPLOYER);
        (
            address earnerManagerImplementation_,
            address earnerManagerProxy_,
            address smartMTokenImplementation_,
            address smartMTokenProxy_
        ) = deploy(_M_TOKEN, _REGISTRAR, _EXCESS_DESTINATION, _MIGRATION_ADMIN);
        vm.stopPrank();

        // Earner Manager Implementation assertions
        assertEq(IEarnerManager(earnerManagerImplementation_).registrar(), _REGISTRAR);

        // Earner Manager Proxy assertions
        assertEq(IEarnerManager(earnerManagerProxy_).registrar(), _REGISTRAR);
        assertEq(IEarnerManager(earnerManagerProxy_).implementation(), earnerManagerImplementation_);

        // Smart M Token Implementation assertions
        assertEq(smartMTokenImplementation_, getExpectedSmartMTokenImplementation(_DEPLOYER, _DEPLOYER_NONCE));
        assertEq(ISmartMToken(smartMTokenImplementation_).earnerManager(), earnerManagerProxy_);
        assertEq(ISmartMToken(smartMTokenImplementation_).migrationAdmin(), _MIGRATION_ADMIN);
        assertEq(ISmartMToken(smartMTokenImplementation_).mToken(), _M_TOKEN);
        assertEq(ISmartMToken(smartMTokenImplementation_).registrar(), _REGISTRAR);
        assertEq(ISmartMToken(smartMTokenImplementation_).excessDestination(), _EXCESS_DESTINATION);

        // Smart M Token Proxy assertions
        assertEq(smartMTokenProxy_, getExpectedSmartMTokenProxy(_DEPLOYER, _DEPLOYER_NONCE));
        assertEq(ISmartMToken(smartMTokenProxy_).earnerManager(), earnerManagerProxy_);
        assertEq(ISmartMToken(smartMTokenProxy_).migrationAdmin(), _MIGRATION_ADMIN);
        assertEq(ISmartMToken(smartMTokenProxy_).mToken(), _M_TOKEN);
        assertEq(ISmartMToken(smartMTokenProxy_).registrar(), _REGISTRAR);
        assertEq(ISmartMToken(smartMTokenProxy_).excessDestination(), _EXCESS_DESTINATION);
        assertEq(ISmartMToken(smartMTokenProxy_).implementation(), smartMTokenImplementation_);
    }
}
