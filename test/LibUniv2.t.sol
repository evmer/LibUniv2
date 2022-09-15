// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {LibUniv2} from "../src/LibUniv2.sol";

import "@openzeppelin/mocks/ERC20Mock.sol";

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function mint(address to) external returns (uint liquidity);
    function initialize(address, address) external;
}

contract ContractBTest is Test {

    // when we later create a mock univ2pair, we make this contract as the univ2factory.
    // so we need a callback for the feeTo() method when we call _mintFee() via the mint() function
    // see https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol#L90
    address public feeTo = address(0);

    function deployMockPair(ERC20Mock _token0, ERC20Mock _token1, uint _reserve0, uint _reserve1) internal returns (address pair) {

        // we use the deployCode cheatcode to avoid the conflict between different solidity version
        pair = deployCode("UniswapV2Pair.sol", new bytes(0));
        IUniswapV2Pair(pair).initialize(address(_token0), address(_token1));

        // supply the initial liquidity
        _token0.mint(pair, _reserve0);
        _token1.mint(pair, _reserve1);
        IUniswapV2Pair(pair).mint(address(this));
    }

    function setUp() public { }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    // adapted from https://github.com/Uniswap/v2-periphery/blob/master/contracts/libraries/UniswapV2Library.sol#L43
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut, uint fee) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn * (10000 - fee);
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = reserveIn * 10000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // Test path: tokenA -> {pairAB} -> tokenB -> {pairBC} -> tokenC
    function testDualHopSwap() public {

        // set tokens
        ERC20Mock tokenA = new ERC20Mock("", "", address(1), 0);
        ERC20Mock tokenB = new ERC20Mock("", "", address(1), 0);
        ERC20Mock tokenC = new ERC20Mock("", "", address(1), 0);

        // set reserve amounts (random)
        (uint pairABreserve0, uint pairABreserve1) = (62369023623623, 32623623626126266236326);
        (uint pairBCreserve0, uint pairBCreserve1) = (347134734734743, 778458485484554854852);

        // set pairs
        address[] memory pairs = new address[](2);
        pairs[0] = deployMockPair(tokenA, tokenB, pairABreserve0, pairABreserve1);
        pairs[1] = deployMockPair(tokenB, tokenC, pairBCreserve0, pairBCreserve1);

        // set routes
        bool[] memory route = new bool[](2);
        route[0] = address(tokenA) == IUniswapV2Pair(pairs[0]).token0(); // route = true if tokenA is also pairAB's token0, false otherwise
        route[1] = address(tokenB) == IUniswapV2Pair(pairs[1]).token0(); // route = true if tokenB is also pairBC's token0, false otherwise

        // set fees
        uint8[] memory fees = new uint8[](2);
        fees[0] = 30;
        fees[1] = 30;

        address tokenIn = address(tokenA);
        bytes32[] memory paths = LibUniv2.encodePath(pairs, route, fees);
        uint amountIn = 723623623623623;

        ERC20Mock(tokenIn).mint(address(this), amountIn);

        uint amountOut = LibUniv2.swap(tokenIn, amountIn, paths);

        // CHECK RESULT

        // calc the amountOut of first swap
        uint swap = getAmountOut(
            amountIn,
            route[0] ? pairABreserve0 : pairABreserve1, // reserveIn
            route[0] ? pairABreserve1 : pairABreserve0, // reserveOut
            fees[0] // fee
        );

        // calc the amountOut of second swap
        swap = getAmountOut(
            swap,
            route[1] ? pairBCreserve0 : pairBCreserve1, // reserveIn
            route[1] ? pairBCreserve1 : pairBCreserve0, // reserveOut
            fees[1] // fee
        );

        assertEq(amountOut, swap);
        assertEq(amountOut, tokenC.balanceOf(address(this)));
    }
}
