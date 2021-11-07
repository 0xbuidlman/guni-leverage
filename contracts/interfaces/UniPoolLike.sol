// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

interface UniPoolLike {
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
    function swap(address, bool, int256, uint160, bytes calldata) external;
    function positions(bytes32) external view returns (uint128, uint256, uint256, uint128, uint128);
}