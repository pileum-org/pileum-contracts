// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IOCO {
    function mint(address to, uint256 amount) external;
    function trackBurn(address to, uint256 amount) external;
}
