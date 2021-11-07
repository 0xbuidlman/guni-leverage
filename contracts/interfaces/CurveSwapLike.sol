// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

interface CurveSwapLike {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
    function coins(uint256) external view returns (address);
}