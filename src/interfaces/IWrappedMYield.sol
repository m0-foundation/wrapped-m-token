// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { IERC721Metadata } from "../../lib/openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Metadata.sol";

interface IWrappedMYield is IERC721Metadata {
    /* ============ Events ============ */

    /* ============ Custom Errors ============ */

    error NotWrappedM();

    error NotOwner();

    error DivisionByZero();

    /* ============ Interactive Functions ============ */

    function mint(address account, uint256 amount) external returns (uint256 tokenId);

    function burn(address account, uint256 tokenId) external returns (uint256 amount, uint256 yield);

    function reshape(
        address account,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external returns (uint256[] memory newTokenIds);

    /* ============ View/Pure Functions ============ */

    function mToken() external returns (address mToken);

    function wrappedM() external returns (address wrappedM);

    function getYieldBasis(uint256 tokenId) external view returns (uint112 amount, uint128 index);
}
