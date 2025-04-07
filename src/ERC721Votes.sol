// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC721/extensions/ERC721Votes.sol)
// Modified for pileum.org
pragma solidity ^0.8.20;

import {ERC721} from "./ERC721.sol";
import {Votes} from "./Votes.sol";

/**
 * @dev Extension of ERC-721 to support voting and delegation as implemented by {Votes}, where each individual NFT counts
 * as 1 vote unit.
 *
 * Tokens do not count as votes until they are delegated, because votes must be tracked which incurs an additional cost
 * on every transfer. Token holders can either delegate to a trusted representative who will decide how to make use of
 * the votes in governance decisions, or they can delegate to themselves to be their own representative.
 */
abstract contract ERC721Votes is ERC721, Votes {
    uint48 public immutable EPOCH_DURATION;

    constructor(uint48 epochDuration) {
        require(epochDuration > 1, "Invalid epoch duration");
        EPOCH_DURATION = epochDuration;
    }

    /**
     * @dev See {ERC721-_update}. Adjusts votes when tokens are transferred.
     *
     * Emits a {IVotes-DelegateVotesChanged} event.
     */
    function _update(address to, uint256 tokenId, address auth, uint48 timepoint)
        internal
        virtual
        override
        returns (address)
    {
        address previousOwner = super._update(to, tokenId, auth, timepoint);
        _transferVotingUnits(previousOwner, to, 1, epoch(timepoint));

        return previousOwner;
    }

    function balanceOf(address owner) public view returns (uint256) {
        return balanceOf(owner, currEpoch());
    }

    function epochRange(uint48 timepoint) public view returns (uint48, uint48) {
        uint48 start = (timepoint / EPOCH_DURATION) * EPOCH_DURATION;
        uint48 end = start + EPOCH_DURATION;
        return (start, end);
    }

    function epoch(uint48 timepoint) public view override returns (uint32) {
        return uint32(timepoint / EPOCH_DURATION);
    }

    function currEpoch() public view override returns (uint32) {
        return epoch(clock());
    }

    function nextEpoch() public view returns (uint32) {
        return epoch(clock() + EPOCH_DURATION);
    }

    function epochAddress(address account, uint48 timepoint) internal view override(ERC721, Votes) returns (uint256) {
        return (uint256(epoch(timepoint)) << 160) | uint256(uint160(account));
    }

    function epochIndexAddress(address account, uint32 epochIndex)
        internal
        pure
        override(ERC721, Votes)
        returns (uint256)
    {
        return (uint256(epochIndex) << 160) | uint256(uint160(account));
    }

    function getTotalSupply() public view returns (uint256) {
        return _getTotalSupply();
    }

    /**
     * @dev Returns the balance of `account`.
     *
     * WARNING: Overriding this function will likely result in incorrect vote tracking.
     */
    function _getVotingUnits(address account) internal view virtual override returns (uint256) {
        return balanceOf(account);
    }
}
