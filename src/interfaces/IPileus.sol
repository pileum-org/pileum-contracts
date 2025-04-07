// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IPileus {
    function EPOCH_DURATION() external view returns (uint48);
    function propsOf(uint256 tokenId) external view returns (address, uint48);
    function getApproved(uint256 tokenId) external view returns (address);
    function getPastTotalSupply(uint256 timepoint) external view returns (uint256);
    function getTotalSupply() external view returns (uint256);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}
