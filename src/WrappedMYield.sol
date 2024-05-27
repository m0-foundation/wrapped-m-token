// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.23;

import { UIntMath } from "../lib/common/src/libs/UIntMath.sol";

import { ERC721 } from "../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

import { IMTokenLike } from "./interfaces/IMTokenLike.sol";
import { IWrappedMYield } from "./interfaces/IWrappedMYield.sol";

contract WrappedMYield is IWrappedMYield, ERC721 {
    struct YieldBasis {
        uint112 amount;
        uint128 index;
    }

    /* ============ Variables ============ */

    uint56 internal constant _EXP_SCALED_ONE = 1e12;

    address public immutable mToken;
    address public immutable wrappedM;

    uint256 internal _tokenCount;

    mapping(uint256 tokenId => YieldBasis yieldBasis) internal _yieldBases;

    /* ============ Modifiers ============ */

    modifier onlyWrappedM() {
        if (msg.sender != wrappedM) revert NotWrappedM();

        _;
    }

    /* ============ Constructor ============ */

    constructor(address mToken_, address wrappedM_) ERC721("Wrapped M Yield by M^0", "wyM") {
        mToken = mToken_;
        wrappedM = wrappedM_;
    }

    /* ============ Interactive Functions ============ */

    function mint(address account_, uint256 amount_) external onlyWrappedM returns (uint256 tokenId_) {
        return _mint(account_, UIntMath.safe240(amount_), IMTokenLike(mToken).currentIndex());
    }

    function burn(
        address account_,
        uint256 tokenId_
    ) external onlyWrappedM returns (uint256 amount_, uint256 yield_) {
        return _burn(account_, tokenId_, IMTokenLike(mToken).currentIndex());
    }

    function reshape(
        address account_,
        uint256[] calldata tokenIds_,
        uint256[] calldata amounts_
    ) external returns (uint256[] memory newTokenIds_) {
        uint128 currentIndex_ = IMTokenLike(mToken).currentIndex();

        uint240 totalAmount_;
        uint240 totalYield_;

        for (uint256 index_; index_ < tokenIds_.length; ++index_) {
            (uint240 amount_, uint240 yield_) = _burn(msg.sender, tokenIds_[index_], currentIndex_);

            totalAmount_ += amount_;
            totalYield_ += yield_;
        }

        uint128 blendedIndex_ = _getIndex(totalAmount_, _getPrincipalAmount(totalAmount_ + totalYield_, currentIndex_));

        newTokenIds_ = new uint256[](amounts_.length + 1);

        for (uint256 index_; index_ < amounts_.length; ++index_) {
            uint240 amount_ = (index_ == amounts_.length - 1)
                ? totalAmount_
                : UIntMath.safe240(amounts_[index_]);

            newTokenIds_[index_] = _mint(account_, amount_, blendedIndex_);

            totalAmount_ -= amount_;
        }
    }

    /* ============ View/Pure Functions ============ */

    function getYieldBasis(uint256 tokenId_) public view returns (uint112 amount_, uint128 index_) {
        YieldBasis storage yieldBasis_ = _yieldBases[tokenId_];

        return (yieldBasis_.amount, yieldBasis_.index);
    }

    /* ============ Internal Interactive Functions ============ */

    function _mint(address account_, uint240 amount_, uint128 currentIndex_) internal returns (uint256 tokenId_) {
        _yieldBases[tokenId_ = ++_tokenCount] = YieldBasis({
            amount: _getPrincipalAmount(UIntMath.safe240(amount_), currentIndex_),
            index: currentIndex_
        });

        _mint(account_, tokenId_);
    }

    function _burn(
        address account_,
        uint256 tokenId_,
        uint128 currentIndex_
    ) internal returns (uint240 amount_, uint240 yield_) {
        _revertIfNotOwner(account_, tokenId_);

        _burn(tokenId_);

        (uint112 basisAmount_, uint128 basisIndex_) = getYieldBasis(tokenId_);

        amount_ = _getPresentAmount(basisAmount_, basisIndex_);
        yield_ = _getPresentAmount(basisAmount_, currentIndex_) - amount_;

        delete _yieldBases[tokenId_];
    }

    /* ============ Internal View/Pure Functions ============ */

    function _revertIfNotOwner(address account_, uint256 tokenId_) internal view {
        if (ownerOf(tokenId_) != account_) revert NotOwner();
    }

    function _multiplyDown(uint112 x_, uint128 y_) internal pure returns (uint240) {
        unchecked {
            return uint240((uint256(x_) * y_) / _EXP_SCALED_ONE);
        }
    }

    function _divideDown128(uint240 x_, uint128 y_) internal pure returns (uint112) {
        if (y_ == 0) revert DivisionByZero();

        unchecked {
            return UIntMath.safe112((uint256(x_) * _EXP_SCALED_ONE) / y_);
        }
    }

    function _divideDown112(uint240 x_, uint112 y_) internal pure returns (uint128) {
        if (y_ == 0) revert DivisionByZero();

        unchecked {
            return UIntMath.safe128((uint256(x_) * _EXP_SCALED_ONE) / y_);
        }
    }

    function _getIndex(uint240 presentAmount_, uint112 principalAmount) internal pure returns (uint128) {
        return _divideDown112(presentAmount_, principalAmount);
    }

    function _getPresentAmount(uint112 principalAmount_, uint128 index_) internal pure returns (uint240) {
        return _multiplyDown(principalAmount_, index_);
    }

    function _getPrincipalAmount(uint240 presentAmount_, uint128 index_) internal pure returns (uint112) {
        return _divideDown128(presentAmount_, index_);
    }
}
