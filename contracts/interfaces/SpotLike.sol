// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

interface SpotLike {
    function ilks(bytes32) external view returns (address pip, uint256 mat);
}