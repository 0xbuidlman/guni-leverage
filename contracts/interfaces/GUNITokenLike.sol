// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
interface GUNITokenLike is IERC20 {
    function mint(uint256 mintAmount, address receiver) external returns (
        uint256 amount0,
        uint256 amount1,
        uint128 liquidityMinted
    );
    function burn(uint256 burnAmount, address receiver) external returns (
        uint256 amount0,
        uint256 amount1,
        uint128 liquidityBurned
    );
    function getMintAmounts(uint256 amount0Max, uint256 amount1Max) external view returns (uint256 amount0, uint256 amount1, uint256 mintAmount);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function pool() external view returns (address);
    function getUnderlyingBalances() external view returns (uint256, uint256);
    function decimals() external view returns (uint8);
}