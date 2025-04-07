// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Pileus} from "../Pileus.sol";
import {IWorldID} from "../interfaces/IWorldID.sol";
import {ByteHasher} from "../helpers/ByteHasher.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title World ID verifier for Pileus
/// @author pileum.org
/// @notice Verify World ID proofs to issue Pileus tokens
/// @custom:security-contact security@pileum.org
contract WorldIDVerifier {
    using ByteHasher for bytes;

    ///////////////////////////////////////////////////////////////////////////////
    ///                              CONFIG STORAGE                            ///
    //////////////////////////////////////////////////////////////////////////////

    /// @dev The World ID instance that will be used for verifying proofs
    IWorldID internal immutable worldId;

    /// @dev The World ID app ID
    uint256 internal immutable appIdHash;

    string internal constant actionIdPrefix = "claim-";

    /// @dev The World ID group ID (always 1)
    uint256 internal immutable groupId = 1;

    /// @dev The Pileus token distributed to participants
    Pileus public immutable token;

    /// @dev An event that is emitted when a user successfully verifies with World ID
    event Verified(address indexed account, uint256 indexed tokenId, uint32 epoch);

    /// @param _worldId The WorldID router that will verify the proof
    /// @param _appId The World ID app ID
    /// @param _token The Pileus token distributed to participants
    constructor(IWorldID _worldId, string memory _appId, Pileus _token) {
        worldId = _worldId;
        appIdHash = abi.encodePacked(_appId).hashToField();
        token = _token;
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                               CLAIM LOGIC                               ///
    //////////////////////////////////////////////////////////////////////////////

    /// @param signal user's wallet address
    /// @param root The root of the Merkle tree
    /// @param nullifierHash The nullifier hash for this proof, preventing double signaling
    /// @param proof The zero-knowledge proof that demonstrates the claimer is registered with World ID
    function claimToken(bool nextEpoch, address signal, uint256 root, uint256 nullifierHash, uint256[8] calldata proof)
        public
    {
        uint32 epoch;
        uint48 mintBlock;
        if (nextEpoch) {
            epoch = token.nextEpoch();
            mintBlock = uint48(epoch * token.EPOCH_DURATION()); // start block of next epoch
        } else {
            epoch = token.currEpoch();
            mintBlock = token.clock();
        }
        string memory actionId = string(abi.encodePacked(actionIdPrefix, Strings.toString(epoch)));
        uint256 externalNullifier = abi.encodePacked(appIdHash, actionId).hashToField();
        // We now verify the provided proof is valid and the user is verified by World ID
        worldId.verifyProof(
            root, groupId, abi.encodePacked(signal).hashToField(), nullifierHash, externalNullifier, proof
        );

        token.issueToken(signal, nullifierHash, mintBlock);

        emit Verified(signal, nullifierHash, epoch);
    }
}
