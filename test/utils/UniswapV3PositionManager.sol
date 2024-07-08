// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.23;

import { INonfungiblePositionManager } from "../vendor/uniswap-v3/interfaces/INonfungiblePositionManager.sol";
import { IUniswapV3Factory } from "../vendor/uniswap-v3/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "../vendor/uniswap-v3/interfaces/IUniswapV3Pool.sol";
import { ISwapRouter } from "../vendor/uniswap-v3/interfaces/ISwapRouter.sol";

import { TransferHelper } from "../vendor/uniswap-v3/libraries/TransferHelper.sol";

import { TickMath } from "../vendor/uniswap-v3/utils/TickMath.sol";
import { encodePriceSqrt } from "../vendor/uniswap-v3/utils/Math.sol";

contract UniswapV3PositionManager {
    /// @dev Uniswap V3 Position Manager on Ethereum Mainnet
    INonfungiblePositionManager public nonfungiblePositionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    /// @dev Uniswap V3 Factory on Ethereum Mainnet
    IUniswapV3Factory public factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    /// @dev Uniswap V3 Router on Ethereum Mainnet
    ISwapRouter public immutable swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    /// @notice Represents the deposit of an NFT
    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    /// @dev deposits[tokenId] => Deposit
    mapping(uint256 => Deposit) public deposits;

    function createPool(address token0_, address token1__, uint24 fee_) external returns (address pool_) {
        pool_ = factory.createPool(token0_, token1__, fee_);
        IUniswapV3Pool(pool_).initialize(encodePriceSqrt(1, 1));
    }

    function _createDeposit(address owner_, uint256 tokenId_) internal {
        (, , address token0_, address token1_, , , , uint128 liquidity_, , , , ) = nonfungiblePositionManager.positions(
            tokenId_
        );

        deposits[tokenId_] = Deposit({ owner: owner_, liquidity: liquidity_, token0: token0_, token1: token1_ });
    }

    function mintNewPosition(
        uint24 poolFee_,
        address token0_,
        address token1_,
        uint256 mintAmount_
    ) external returns (uint256 tokenId_, uint128 liquidity_, uint256 amount0_, uint256 amount1_) {
        // Transfer tokens to contract
        TransferHelper.safeTransferFrom(token0_, msg.sender, address(this), mintAmount_);
        TransferHelper.safeTransferFrom(token1_, msg.sender, address(this), mintAmount_);

        TransferHelper.safeApprove(token0_, address(nonfungiblePositionManager), mintAmount_);
        TransferHelper.safeApprove(token1_, address(nonfungiblePositionManager), mintAmount_);

        // Note that the pool defined by token0_/token1_ and poolFee_ must already be created and initialized in order to mint
        (tokenId_, liquidity_, amount0_, amount1_) = nonfungiblePositionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0_,
                token1: token1_,
                fee: poolFee_,
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                amount0Desired: mintAmount_,
                amount1Desired: mintAmount_,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        // Store deposit in `deposits` mapping
        _createDeposit(msg.sender, tokenId_);

        // Remove allowance and refund in both assets
        if (amount0_ < mintAmount_) {
            TransferHelper.safeApprove(token0_, address(nonfungiblePositionManager), 0);
            TransferHelper.safeTransfer(token0_, msg.sender, mintAmount_ - amount0_);
        }

        if (amount1_ < mintAmount_) {
            TransferHelper.safeApprove(token1_, address(nonfungiblePositionManager), 0);
            TransferHelper.safeTransfer(token1_, msg.sender, mintAmount_ - amount1_);
        }
    }

    // Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
    function onERC721Received(address operator, address, uint256 tokenId, bytes calldata) external returns (bytes4) {
        _createDeposit(operator, tokenId);
        return this.onERC721Received.selector;
    }

    /// @notice Transfers the NFT to the owner
    /// @param tokenId The id of the erc721
    function retrieveNFT(uint256 tokenId) external {
        // must be the owner of the NFT
        require(msg.sender == deposits[tokenId].owner, "Not the owner");

        // transfer ownership to original owner
        nonfungiblePositionManager.safeTransferFrom(address(this), msg.sender, tokenId);

        //remove information related to tokenId
        delete deposits[tokenId];
    }

    /// @notice swapExactInputSingle swaps a fixed amount of tokenIn for a maximum possible amount of tokenOut
    /// using the tokenIn/tokenOut pool by calling `exactInputSingle` in the swap router.
    /// @dev The calling address must approve this contract to spend at least `amountIn` worth of its tokenIn for this function to succeed.
    /// @param amountIn The exact amount of tokenIn that will be swapped for tokenOut.
    /// @return amountOut The amount of tokenOut received.
    function swapExactInputSingle(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint24 poolFee
    ) external returns (uint256 amountOut) {
        // msg.sender must approve this contract

        // Transfer the specified amount of tokenIn to this contract.
        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);

        // Approve the router to spend tokenIn.
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountIn);

        // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
        // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: poolFee,
            recipient: msg.sender,
            deadline: block.timestamp + 30 minutes,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        // The call to `exactInputSingle` executes the swap.
        amountOut = swapRouter.exactInputSingle(params);
    }
}
