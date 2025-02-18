// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { Proxy } from "../lib/common/src/Proxy.sol";

import { IInitializable } from "./interfaces/IInitializable.sol";

contract Factory {
    error NotAdmin();
    error CodeHashDenied(bytes32 codeHash);
    error CodeHashNotApproved(bytes32 codeHash);
    error ImplementationNotDeployed();

    event ProxyDeployed(address indexed proxy, address indexed implementation, address indexed sender, bytes32 salt);
    event ImplementationApproved(bytes32 indexed codeHash);
    event ImplementationDenied(bytes32 indexed codeHash);
    event ImplementationDeployed(bytes32 indexed codeHash, address indexed implementation);

    address internal constant _APPROVED_CODE_HASH = address(1);
    address internal constant _DENIED_CODE_HASH = address(0);

    address public immutable initializableImplementation;

    address public admin;

    mapping(bytes32 codeHash => address implementation) internal _implementations;

    modifier onlyAdmin() {
        _revertIfNotAdmin();
        _;
    }

    constructor(address admin_, address initializableImplementation_) {
        admin = admin_;
        initializableImplementation = initializableImplementation_;
    }

    function approveImplementation(bytes32 codeHash_) external onlyAdmin {
        _implementations[codeHash_] = _APPROVED_CODE_HASH;
        emit ImplementationApproved(codeHash_);
    }

    function denyImplementation(bytes32 codeHash_) external onlyAdmin {
        _implementations[codeHash_] = _DENIED_CODE_HASH;
        emit ImplementationDenied(codeHash_);
    }

    function deployImplementation(bytes memory bytecode_) public returns (bytes32 codeHash_, address implementation_) {
        // Deploy an implementation contract.
        // TODO: Consider create2 for more deterministic addresses, maybe having the salt be the code hash?
        //       But keep in mind the address of the implementation does not matter at all.
        assembly {
            implementation_ := create(0, add(bytecode_, 0x20), mload(bytecode_))
        }

        codeHash_ = implementation_.codehash;

        // Only allow setting the implementation for the codeHash if the code is approved and not already deployed.
        if (_implementations[codeHash_] != _APPROVED_CODE_HASH) revert CodeHashNotApproved(codeHash_);

        _implementations[codeHash_] = implementation_;

        emit ImplementationDeployed(codeHash_, implementation_);
    }

    function deployProxy(
        bytes32 codeHash_,
        bytes32 salt_,
        bytes calldata initializationArguments_
    ) public returns (address proxy_) {
        // Get the implementation address based on the code hash.
        address implementation_ = _implementations[codeHash_];

        if (implementation_ == _DENIED_CODE_HASH) revert CodeHashDenied(codeHash_);
        if (implementation_ == _APPROVED_CODE_HASH) revert ImplementationNotDeployed();

        return _deployProxy(implementation_, salt_, initializationArguments_);
    }

    function deployProxy(
        bytes memory bytecode_,
        bytes32 salt_,
        bytes calldata initializationArguments_
    ) external returns (address proxy_) {
        (, address implementation_) = deployImplementation(bytecode_);

        return _deployProxy(implementation_, salt_, initializationArguments_);
    }

    function _deployProxy(
        address implementation_,
        bytes32 salt_,
        bytes calldata initializationArguments_
    ) internal returns (address proxy_) {
        // Deploy a proxy to an implementation that only allows initialization.
        // NOTE: The address of the deployed proxy is deterministic based on the sender and their chosen salt.
        proxy_ = address(new Proxy{ salt: keccak256(abi.encode(msg.sender, salt_)) }(initializableImplementation));

        // Initialize the proxy, which will set its implementation slot and delegatecall the initializer.
        IInitializable(proxy_).initialize(implementation_, initializationArguments_);

        emit ProxyDeployed(proxy_, implementation_, msg.sender, salt_);
    }

    function _revertIfNotAdmin() internal view {
        if (msg.sender != admin) revert NotAdmin();
    }
}
