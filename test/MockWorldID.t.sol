// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockWorldID} from "../src/MockWorldID.sol";

contract WorldIDVerifierTest is Test {
    MockWorldID private worldId;

    function setUp() public {
        worldId = new MockWorldID();
    }

    function test_verifyProof() public view {
        worldId.verifyProof(0, 0, 0, 0, 0, [uint256(0), 0, 0, 0, 0, 0, 0, 0]);
    }
}
