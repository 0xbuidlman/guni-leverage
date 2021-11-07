// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

interface DaiJoinLike {
    function vat() external view returns (address);
    function dai() external view returns (address);
    function join(address, uint256) external;
    function exit(address, uint256) external;
}