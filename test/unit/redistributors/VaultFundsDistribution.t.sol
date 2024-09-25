// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { Test } from "../../../lib/forge-std/src/Test.sol";

import { VaultFundsDistribution } from "../../../src/redistributors/morpho-dc-c/VaultFundsDistribution.sol";

contract Distributor is VaultFundsDistribution {
    function distribute(uint256 amount_) external {
        _distribute(amount_);
    }

    function addShares(uint256 distributable_, address vault_, uint256 amount_) external {
        _addShares(distributable_, vault_, amount_);
    }

    function removeShares(uint256 distributable_, address vault_, uint256 amount_) external {
        _removeShares(distributable_, vault_, amount_);
    }

    function getCumulativeDistribution(address vault_) external view returns (uint256 distributions_) {
        return _getCumulativeDistribution(vault_);
    }
}

contract WrappedMTokenTests is Test {
    address internal _vault0 = makeAddr("vault0");
    address internal _vault1 = makeAddr("vault1");
    address internal _vault2 = makeAddr("vault2");

    Distributor internal _distributor;

    function setUp() external {
        _distributor = new Distributor();
    }

    function test_basic() external {
        /* ============ Vault0 Adds 1000 Shares ============ */

        _distributor.addShares(0, _vault0, 1_000);

        assertEq(_distributor.getCumulativeDistribution(_vault0), 0);

        /* ============ Vault0 Adds 1000 Shares ============ */

        _distributor.addShares(0, _vault0, 1_000);

        assertEq(_distributor.getCumulativeDistribution(_vault0), 0);

        /* ============ 100 Funds Distributed ============ */

        _distributor.distribute(100);

        assertEq(_distributor.getCumulativeDistribution(_vault0), 99); // All funds distributed to vault 0.

        /* ============ Vault1 Adds 1000 Shares ============ */

        _distributor.addShares(0, _vault1, 1_000);

        assertEq(_distributor.getCumulativeDistribution(_vault1), 0);

        /* ============ 100 Funds Distributed ============ */

        _distributor.distribute(100);

        assertEq(_distributor.getCumulativeDistribution(_vault0), 166); // 66% of new funds to vault 0.
        assertEq(_distributor.getCumulativeDistribution(_vault1), 33); // 33% of new funds to vault 1.

        /* ============ Vault2 Adds 500 Shares ============ */

        _distributor.addShares(0, _vault2, 500);

        assertEq(_distributor.getCumulativeDistribution(_vault2), 0);

        /* ============ 100 Funds Distributed ============ */

        _distributor.distribute(100);

        assertEq(_distributor.getCumulativeDistribution(_vault0), 223); // 2000/3500 of new funds to vault 0.
        assertEq(_distributor.getCumulativeDistribution(_vault1), 61); // 1000/3500 of new funds to vault 1.
        assertEq(_distributor.getCumulativeDistribution(_vault2), 14); // 500/3500 of new funds to vault 2.

        /* ============ Vault0 Adds 1000 Shares ============ */

        _distributor.addShares(0, _vault0, 1_000);

        assertEq(_distributor.getCumulativeDistribution(_vault0), 223);

        /* ============ Vault0 Removes 3000 Shares ============ */

        _distributor.removeShares(0, _vault0, 3_000);

        assertEq(_distributor.getCumulativeDistribution(_vault0), 223);

        /* ============ 100 Funds Distributed and Vault2 Removes 500 Shares ============ */

        _distributor.removeShares(100, _vault2, 500);

        assertEq(_distributor.getCumulativeDistribution(_vault0), 223); // 0% of new funds to vault 0.
        assertEq(_distributor.getCumulativeDistribution(_vault1), 128); // 66% of new funds to vault 1.
        assertEq(_distributor.getCumulativeDistribution(_vault2), 47); // 33% of new funds to vault 2.

        /* ============ 100 Funds Distributed and Vault1 Removes 1000 Shares ============ */

        _distributor.removeShares(100, _vault1, 1_000);

        assertEq(_distributor.getCumulativeDistribution(_vault0), 223); // 0% of new funds to vault 0.
        assertEq(_distributor.getCumulativeDistribution(_vault1), 228); // 100% of new funds to vault 1.
        assertEq(_distributor.getCumulativeDistribution(_vault2), 47); // 0% of new funds to vault 2.
    }
}
