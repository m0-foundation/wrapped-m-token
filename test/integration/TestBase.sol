// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.26;

import { IERC20 } from "../../lib/common/src/interfaces/IERC20.sol";
import { IERC20Extended } from "../../lib/common/src/interfaces/IERC20Extended.sol";
import { IERC712 } from "../../lib/common/src/interfaces/IERC712.sol";

import { Test } from "../../lib/forge-std/src/Test.sol";
import { Proxy } from "../../lib/common/src/Proxy.sol";

import { IWrappedMToken } from "../../src/interfaces/IWrappedMToken.sol";

import { EarnerManager } from "../../src/EarnerManager.sol";
import { WrappedMToken } from "../../src/WrappedMToken.sol";
import { WrappedMTokenMigratorV1 } from "../../src/WrappedMTokenMigratorV1.sol";

import { IMTokenLike, IRegistrarLike } from "./vendor/protocol/Interfaces.sol";

contract TestBase is Test {
    IMTokenLike internal constant _mToken = IMTokenLike(0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b);

    address internal constant _minterGateway = 0xf7f9638cb444D65e5A40bF5ff98ebE4ff319F04E;
    address internal constant _registrar = 0x119FbeeDD4F4f4298Fb59B720d5654442b81ae2c;
    address internal constant _excessDestination = 0xd7298f620B0F752Cf41BD818a16C756d9dCAA34f; // vault
    address internal constant _standardGovernor = 0xB024aC5a7c6bC92fbACc8C3387E628a07e1Da016;
    address internal constant _mSource = 0x563AA56D0B627d1A734e04dF5762F5Eea1D56C2f;
    address internal constant _wmSource = 0xa969cFCd9e583edb8c8B270Dc8CaFB33d6Cf662D;

    IWrappedMToken internal constant _wrappedMToken = IWrappedMToken(0x437cc33344a0B27A429f795ff6B469C72698B291);

    bytes32 internal constant _EARNERS_LIST_NAME = "earners";
    bytes32 internal constant _MIGRATOR_V1_PREFIX = "wm_migrator_v1";
    bytes32 internal constant _CLAIM_OVERRIDE_RECIPIENT_PREFIX = "wm_claim_override_recipient";
    bytes32 internal constant _EARNER_STATUS_ADMIN_LIST = "wm_earner_status_admins";

    // USDC on Ethereum Mainnet
    address internal constant _USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Large USDC holder on Ethereum Mainnet
    address internal constant _USDC_SOURCE = 0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa;

    // DAI on Ethereum Mainnet
    address internal constant _DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Large DAI holder on Ethereum Mainnet
    address internal constant _DAI_SOURCE = 0xD1668fB5F690C59Ab4B0CAbAd0f8C1617895052B;

    address internal _migrationAdmin = 0x431169728D75bd02f4053435b87D15c8d1FB2C72;

    address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");
    address internal _carol = makeAddr("carol");
    address internal _dave = makeAddr("dave");
    address internal _eric = makeAddr("eric");
    address internal _frank = makeAddr("frank");
    address internal _grace = makeAddr("grace");
    address internal _henry = makeAddr("henry");
    address internal _ivan = makeAddr("ivan");
    address internal _judy = makeAddr("judy");

    uint256 internal _aliceKey = _makeKey("alice");

    address[] internal _accounts = [_alice, _bob, _carol, _dave, _eric, _frank, _grace, _henry, _ivan, _judy];

    address internal _earnerManagerImplementation;
    address internal _earnerManager;
    address internal _wrappedMTokenImplementationV2;
    address internal _wrappedMTokenMigratorV1;

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

    function _getSource(address token_) internal pure returns (address source_) {
        if (token_ == _USDC) return _USDC_SOURCE;

        if (token_ == _DAI) return _DAI_SOURCE;

        revert();
    }

    function _give(address token_, address account_, uint256 amount_) internal {
        vm.prank(_getSource(token_));
        IERC20(token_).transfer(account_, amount_);
    }

    function _addToList(bytes32 list_, address account_) internal {
        vm.prank(_standardGovernor);
        IRegistrarLike(_registrar).addToList(list_, account_);
    }

    function _removeFromList(bytes32 list_, address account_) internal {
        vm.prank(_standardGovernor);
        IRegistrarLike(_registrar).removeFromList(list_, account_);
    }

    function _giveM(address account_, uint256 amount_) internal {
        vm.prank(_mSource);
        _mToken.transfer(account_, amount_);
    }

    function _giveWM(address account_, uint256 amount_) internal {
        vm.prank(_wmSource);
        _wrappedMToken.transfer(account_, amount_);
    }

    function _giveEth(address account_, uint256 amount_) internal {
        vm.deal(account_, amount_);
    }

    function _wrap(address account_, address recipient_, uint256 amount_) internal {
        vm.prank(account_);
        _mToken.approve(address(_wrappedMToken), amount_);

        vm.prank(account_);
        _wrappedMToken.wrap(recipient_, amount_);
    }

    function _wrap(address account_, address recipient_) internal {
        vm.prank(account_);
        _mToken.approve(address(_wrappedMToken), type(uint256).max);

        vm.prank(account_);
        _wrappedMToken.wrap(recipient_);
    }

    function _wrapWithPermitVRS(
        address account_,
        uint256 signerPrivateKey_,
        address recipient_,
        uint256 amount_,
        uint256 nonce_,
        uint256 deadline_
    ) internal {
        (uint8 v_, bytes32 r_, bytes32 s_) = _getPermit(account_, signerPrivateKey_, amount_, nonce_, deadline_);

        vm.prank(account_);
        _wrappedMToken.wrapWithPermit(recipient_, amount_, deadline_, v_, r_, s_);
    }

    function _wrapWithPermitSignature(
        address account_,
        uint256 signerPrivateKey_,
        address recipient_,
        uint256 amount_,
        uint256 nonce_,
        uint256 deadline_
    ) internal {
        (uint8 v_, bytes32 r_, bytes32 s_) = _getPermit(account_, signerPrivateKey_, amount_, nonce_, deadline_);

        vm.prank(account_);
        _wrappedMToken.wrapWithPermit(recipient_, amount_, deadline_, abi.encodePacked(r_, s_, v_));
    }

    function _unwrap(address account_, address recipient_, uint256 amount_) internal {
        vm.prank(account_);
        _wrappedMToken.unwrap(recipient_, amount_);
    }

    function _unwrap(address account_, address recipient_) internal {
        vm.prank(account_);
        _wrappedMToken.unwrap(recipient_);
    }

    function _transferWM(address sender_, address recipient_, uint256 amount_) internal {
        vm.prank(sender_);
        _wrappedMToken.transfer(recipient_, amount_);
    }

    function _approveWM(address account_, address spender_, uint256 amount_) internal {
        vm.prank(account_);
        _wrappedMToken.approve(spender_, amount_);
    }

    function _set(bytes32 key_, bytes32 value_) internal {
        vm.prank(_standardGovernor);
        IRegistrarLike(_registrar).setKey(key_, value_);
    }

    function _setClaimOverrideRecipient(address account_, address recipient_) internal {
        _set(keccak256(abi.encode(_CLAIM_OVERRIDE_RECIPIENT_PREFIX, account_)), bytes32(uint256(uint160(recipient_))));
    }

    function _deployV2Components() internal {
        _earnerManagerImplementation = address(new EarnerManager(_registrar));
        _earnerManager = address(new Proxy(_earnerManagerImplementation));

        EarnerManager(_earnerManager).initialize(_migrationAdmin);

        _wrappedMTokenImplementationV2 = address(
            new WrappedMToken(address(_mToken), _registrar, _earnerManager, _excessDestination)
        );

        address[] memory earners_ = new address[](_earners.length);

        for (uint256 index_; index_ < _earners.length; ++index_) {
            earners_[index_] = _earners[index_];
        }

        _wrappedMTokenMigratorV1 = address(
            new WrappedMTokenMigratorV1(_wrappedMTokenImplementationV2, earners_, _migrationAdmin)
        );
    }

    function _migrate() internal {
        _set(
            keccak256(abi.encode(_MIGRATOR_V1_PREFIX, address(_wrappedMToken))),
            bytes32(uint256(uint160(_wrappedMTokenMigratorV1)))
        );

        _wrappedMToken.migrate();
    }

    function _migrateFromAdmin() internal {
        vm.prank(_migrationAdmin);
        _wrappedMToken.migrate(_wrappedMTokenMigratorV1);
    }

    /* ============ utils ============ */

    function _makeKey(string memory name_) internal returns (uint256 key_) {
        (, key_) = makeAddrAndKey(name_);
    }

    function _getPermit(
        address account_,
        uint256 signerPrivateKey_,
        uint256 amount_,
        uint256 nonce_,
        uint256 deadline_
    ) internal view returns (uint8 v_, bytes32 r_, bytes32 s_) {
        return
            vm.sign(
                signerPrivateKey_,
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        IERC712(address(_mToken)).DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                IERC20Extended(address(_mToken)).PERMIT_TYPEHASH(),
                                account_,
                                address(_wrappedMToken),
                                amount_,
                                nonce_,
                                deadline_
                            )
                        )
                    )
                )
            );
    }
}
