// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

interface GemJoinLike {
    function vat() external view returns (address);
    function ilk() external view returns (bytes32);
    function gem() external view returns (address);
    function dec() external view returns (uint256);
    function join(address, uint256) external;
    function exit(address, uint256) external;
}