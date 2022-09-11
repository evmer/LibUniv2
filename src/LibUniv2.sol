// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IUniswapV2Pair.sol";

import "@openzeppelin/token/ERC20/ERC20.sol";

library LibUniv2 {

    /* @dev Encode the {_path} param to pass to the swap function.
    * @param _pairs the array of pairs where to route the swap.
    * @param _route the array of routes where true means that pair[n]'s tokenIn == token0, false otherwise.
    * @param _fees the array of fees for each pair[n], in base points (max 255).
    */
    function encodePath(address[] memory _pairs, bool[] memory _route, uint8[] memory _fees) internal pure returns (bytes32[] memory) {
        require(_pairs.length == _route.length && _route.length == _fees.length, "wrong input");

        bytes32[] memory _paths = new bytes32[](_pairs.length);

        for (uint i; i < _pairs.length; ++i) {
            uint data = uint(uint160(_pairs[i]));
            data = (data << 8) + (_route[i] ? 1 : 0); // shift by one and add the route byte
            data = (data << 8) + _fees[i]; // shift by one and add the fee byte
            _paths[i] = bytes32(data << 80);
        }
        return _paths;
    }

    /* @dev Perform gas-efficient swaps across an arbitrary number of Uniswap v2 pairs.
    * @param _tokenIn the initial ERC20 token to swap.
    * @param _amountIn the amount of {_tokenIn} to swap.
    * @param _path contains the encoded data about the fees and the route (see comments below).
    */
    function swap(
        IERC20 _tokenIn,
        uint _amountIn,
        bytes32[] calldata _path
    ) public returns (uint _amountOut) {

        address to = address(uint160(uint(_path[0] >> 96)));
        _tokenIn.transfer(to, _amountIn);

        for (uint i; i < _path.length; ++i) {
            address pair = to;
            (uint reserve0, uint reserve1,) = IUniswapV2Pair(pair).getReserves();

            // for each path index {i} we have a bytes32 where:
            // bytes 0-20, stored as address: the address of the pair
            // byte 20, stored as bool: 0x01 (true) if pair[i]'s token0 is also the tokenIn, 0x00 (false) otherwise
            // bytes 21, stored as uint: fee in bps (max 255 ie 2,55% - enough for the majority of cases)
            bool route = _path[i][20] != 0x00;
            uint fee = uint(uint8(_path[i][21]));

            to = i != (_path.length-1) ? address(uint160(uint(_path[i+1] >> 96))) : address(this);

            uint reserveIn = (route ? reserve0 : reserve1);
            uint reserveOut = (route ? reserve1 : reserve0);

            _amountOut = (
                (_amountIn * (10000 - fee)) * reserveOut) /
                (reserveIn * 10000 + (_amountIn * (10000 - fee))
            );

            IUniswapV2Pair(pair).swap(
                route ? 0 : _amountOut, // amount0Out
                route ? _amountOut : 0, // amount1Out
                to,
                new bytes(0)
            );

            // set amountIn for the next swap
            _amountIn = _amountOut;
        }
    }
}