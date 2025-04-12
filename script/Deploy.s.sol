// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Pileus} from "../src/Pileus.sol";
import {WorldIDVerifier} from "../src/verifiers/WorldIDVerifier.sol";
import {MockWorldID} from "../src/MockWorldID.sol";
import {IWorldID} from "../src/interfaces/IWorldID.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {TOTC} from "../src/TOTC.sol";
import {OCO} from "../src/OCO.sol";
import {IPileus} from "../src/interfaces/IPileus.sol";

contract DeployScript is Script {
    uint48 private constant BLOCK_TIME = 2; //unit: seconds
    uint48 private constant EPOCH_DURATION = 15_778_800; //unit: blocks
    uint128 private constant INITIAL_ALLOWANCE = 4_888_405 * 10 ** 18; //unit: tokens
    uint128 private constant TARGET_ALLOWANCE = 2_813_664 * 10 ** 18; //unit: tokens
    uint128 private constant TARGET_DATE = 10; //unit: epoch count
    bytes32 salt = keccak256("Servos ad pileum vocare");
    address initialOwner;
    IWorldID worldId;
    string worldAppId;

    function setUp() public {
        initialOwner = msg.sender; // use --sender
        worldAppId = vm.envString("WORLD_APP_ID");
        worldId = IWorldID(vm.envAddress("WORLD_ID_ROUTER_ADDR"));
    }

    function run() public {
        vm.startBroadcast();

        //Deploy Pileus contract
        Pileus pileus = new Pileus{salt: salt}(initialOwner, EPOCH_DURATION, BLOCK_TIME);

        //Deploy OCO contract
        OCO oco = new OCO{salt: salt}(initialOwner);

        //Deploy TOTC contract
        uint256 startEpoch = (block.number / EPOCH_DURATION);
        (int256 slope, int256 intercept) =
            getLinearParams(startEpoch, INITIAL_ALLOWANCE, startEpoch + TARGET_DATE, TARGET_ALLOWANCE);
        TOTC totc = new TOTC{salt: salt}(initialOwner, IPileus(address(pileus)), oco, slope, intercept);
        oco.grantRole(oco.MINTER_ROLE(), address(totc));

        //Deploy WorldIDVerifier contract
        WorldIDVerifier worldVerifier = new WorldIDVerifier{salt: salt}(worldId, worldAppId, pileus);
        pileus.grantRole(pileus.VERIFIER_ROLE(), address(worldVerifier));

        vm.stopBroadcast();
    }

    function getLinearParams(uint256 x1, uint256 y1, uint256 x2, uint256 y2)
        public
        pure
        returns (int256 slope, int256 intercept)
    {
        require(x1 < x2, "x1 must be lower than x2");
        uint256 Q128 = 1 << 128;
        uint256 absDy = (y1 < y2 ? y2 - y1 : y1 - y2);
        uint256 absSlope = Math.mulDiv(absDy, Q128, x2 - x1);
        slope = (y1 < y2 ? int256(absSlope) : -int256(absSlope));
        intercept = (int256(y1) * int256(Q128)) - (slope * int256(x1));
    }
}
