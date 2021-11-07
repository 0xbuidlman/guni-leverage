// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract LeverageProxy is TransparentUpgradeableProxy {
    constructor(address _logic, address admin_) TransparentUpgradeableProxy(_logic, admin_, "") {}
}
