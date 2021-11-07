// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

interface GUNIResolverLike {
    function getRebalanceParams(
        address pool,
        uint256 amount0In,
        uint256 amount1In,
        uint256 price18Decimals
    ) external view returns (bool zeroForOne, uint256 swapAmount);
}
