// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

interface VatLike {
    function ilks(bytes32) external view returns (
        uint256 Art,  // [wad]
        uint256 rate, // [ray]
        uint256 spot, // [ray]
        uint256 line, // [rad]
        uint256 dust  // [rad]
    );
    function urns(bytes32, address) external view returns (uint256, uint256);
    function hope(address usr) external;
    function nope(address usr) external;
    function frob (bytes32 i, address u, address v, address w, int dink, int dart) external;
    function dai(address) external view returns (uint256);
}