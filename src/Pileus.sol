// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "./ERC721.sol";
import {ERC721Votes} from "./ERC721Votes.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title Pileus ERC721 token
/// @author pileum.org
/// @notice One Pileus token per person
/// @custom:security-contact security@pileum.org
contract Pileus is AccessControl, EIP712, ERC721Votes {
    using Strings for uint256;

    string private constant TOKEN_NAME = "Pileus";
    string private constant TOKEN_SYM = "PIL";
    string private constant TOKEN_VER = "1";
    string private constant TOKEN_DESC = "Servos ad pileum vocare";
    string private constant TOKEN_BASE_URI = "https://app.pileum.org/pileus";
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    /// @notice The average block production time in seconds.
    uint48 public immutable blockTime;

    /**
     * @notice Struct for minting parameters.
     * @param to Address of the token recipient.
     * @param tokenId Identifier of the token.
     * @param mintBlock Block number for minting.
     */
    struct MintParams {
        address to;
        uint256 tokenId;
        uint48 mintBlock;
    }

    /**
     * @notice Initializes the Pileus contract.
     * @dev Sets up ERC721Votes with the given epoch duration, initializes ERC721 and EIP712.
     * @param defaultAdmin Address granted the DEFAULT_ADMIN_ROLE.
     * @param epochDuration_ Duration of each epoch used by ERC721Votes.
     */
    constructor(address defaultAdmin, uint48 epochDuration_, uint48 blockTime_)
        ERC721Votes(epochDuration_)
        ERC721(TOKEN_NAME, TOKEN_SYM)
        EIP712(TOKEN_NAME, TOKEN_VER)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        blockTime = blockTime_;
    }

    // ==TOKEN ISSUANCE==

    /**
     * @notice Issues a token to a specified address.
     * @dev Only accounts with the VERIFIER_ROLE can call this function.
     *      If the token already exists and is owned by a different address, a safe transfer is performed.
     * @param to Address of the token recipient.
     * @param tokenId Identifier of the token to be issued.
     */
    function issueToken(address to, uint256 tokenId) external onlyRole(VERIFIER_ROLE) {
        _issueToken(to, tokenId, clock());
    }

    /**
     * @notice Issues a token to a specified address with a specific mint block.
     * @dev Only accounts with the VERIFIER_ROLE can call this function.
     *      Allows explicit specification of the mint block.
     * @param to Address of the token recipient.
     * @param tokenId Identifier of the token to be issued.
     * @param mintBlock Block number to record the minting time.
     */
    function issueToken(address to, uint256 tokenId, uint48 mintBlock) external onlyRole(VERIFIER_ROLE) {
        _issueToken(to, tokenId, mintBlock);
    }

    /**
     * @notice Batch issues multiple tokens.
     * @dev Only accounts with the VERIFIER_ROLE can call this function.
     *      Iterates over an array of MintParams and issues tokens accordingly.
     * @param tokens Array of MintParams containing recipient addresses, token IDs, and mint blocks.
     */
    function issueTokens(MintParams[] calldata tokens) external onlyRole(VERIFIER_ROLE) {
        for (uint256 i = 0; i < tokens.length; i++) {
            _issueToken(tokens[i].to, tokens[i].tokenId, tokens[i].mintBlock);
        }
    }

    /**
     * @notice Internal function to issue or transfer a token.
     * @dev If the token exists and is owned by a different address, performs a safe transfer.
     *      If the token does not exist, mints it and sets the delegation to the recipient.
     * @param to Address of the token recipient.
     * @param tokenId Identifier of the token.
     * @param mintBlock Block number to record the minting time.
     */
    function _issueToken(address to, uint256 tokenId, uint48 mintBlock) internal {
        (address from, uint48 prevMintBlock) = propsOf(tokenId);
        if (from != address(0)) {
            if (from != to) {
                _safeTransfer(from, to, tokenId, prevMintBlock);
            }
        } else {
            _safeMint(to, tokenId, mintBlock);
            if (delegates(to) == address(0)) {
                // Delegation persists across epochs
                _delegate(to, to);
            }
        }
    }

    // ==VIEWS==

    /**
     * @notice Returns the base URI for token metadata.
     * @dev Overrides the internal ERC721 _baseURI function.
     * @return Base URI string.
     */
    function _baseURI() internal pure override returns (string memory) {
        return TOKEN_BASE_URI;
    }

    /**
     * @notice Retrieves the token ID associated with an owner in the current epoch.
     * @param owner Address to query.
     * @return Token ID owned by the provided address.
     */
    function getToken(address owner) external view returns (uint256) {
        return super.getToken(owner, currEpoch());
    }

    /**
     * @notice Retrieves token attributes.
     * @dev Returns the mint block and epoch end block for a given token.
     * @param tokenId Identifier of the token.
     * @return mintBlock Block number when the token was minted.
     * @return end Block number when the current epoch ends.
     */
    function getAttributes(uint256 tokenId) public view returns (uint48, uint48) {
        (, uint48 mintBlock) = propsOf(tokenId);
        (, uint48 end) = epochRange(mintBlock);
        return (mintBlock, end);
    }

    /**
     * @notice Approximates a Unix timestamp for a given target block number.
     * @dev The function uses the current block number (`block.number`) and timestamp (`block.timestamp`)
     *      as the baseline. It calculates the difference between the target block and the current block,
     *      then adds or subtracts the product of this difference and the average block time.
     *      This method only provides an approximate result as block times can vary.
     * @param targetBlockNumber The block number for which to estimate the timestamp.
     * @return estimatedTimestamp The approximated Unix timestamp for the target block.
     */
    function approximateTimestamp(uint256 targetBlockNumber) public view returns (uint256 estimatedTimestamp) {
        uint256 currentBlock = block.number;
        uint256 currentTimestamp = block.timestamp;

        if (targetBlockNumber >= currentBlock) {
            estimatedTimestamp = currentTimestamp + ((targetBlockNumber - currentBlock) * uint256(blockTime));
        } else {
            estimatedTimestamp = currentTimestamp - ((currentBlock - targetBlockNumber) * uint256(blockTime));
        }
    }

    /**
     * @notice Generates the token URI with metadata for a given token ID.
     * @dev Constructs a data URI containing a base64 encoded JSON object with token metadata.
     * @param tokenId Identifier of the token.
     * @return Token URI string.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        (uint256 creationBlk, uint256 expirationBlk) = getAttributes(tokenId);
        uint256 creationTS = approximateTimestamp(creationBlk);
        uint256 expirationTS = approximateTimestamp(expirationBlk);
        bytes memory attributes = abi.encodePacked(
            '[{"display_type": "date",',
            '"trait_type": "creation", ',
            '"value": ',
            creationTS.toString(),
            "},{",
            '"display_type": "number",',
            '"trait_type": "creation_block", ',
            '"value": ',
            creationBlk.toString(),
            "},{",
            '"display_type": "date",',
            '"trait_type": "expiration", ',
            '"value": ',
            expirationTS.toString(),
            "},{",
            '"display_type": "number",',
            '"trait_type": "expiration_block", ',
            '"value": ',
            expirationBlk.toString(),
            "}]"
        );
        bytes memory dataURI = abi.encodePacked(
            "{",
            '"name": "',
            TOKEN_NAME,
            " #",
            tokenId.toString(),
            '", "description": "',
            TOKEN_DESC,
            '", "image": "',
            imageData(tokenId),
            '", "background_color": "424242',
            '", "external_url": "',
            externalUrl(tokenId),
            '", "attributes": ',
            attributes,
            "}"
        );
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(dataURI)));
    }

    /**
     * @notice Generates an external URL for a token.
     * @dev Constructs a URL with query parameters based on token attributes and the current block number.
     * @param tokenId Identifier of the token.
     * @return External URL string.
     */
    function externalUrl(uint256 tokenId) public view returns (string memory) {
        (uint256 creationBlk, uint256 expirationBlk) = getAttributes(tokenId);
        string memory baseURI = _baseURI();
        bytes memory url = abi.encodePacked(
            baseURI,
            "?id=",
            tokenId.toString(),
            "&c=",
            creationBlk.toString(),
            "&e=",
            expirationBlk.toString(),
            "&b=",
            block.number.toString(),
            "&ts=",
            block.timestamp.toString()
        );
        return bytes(baseURI).length > 0 ? string(url) : "";
    }

    /**
     * @notice Generates a base64 encoded SVG image for a token.
     * @dev Uses tokenId to determine the colors for the SVG polygons.
     * @param tokenId Identifier of the token.
     * @return Base64 encoded SVG image as a data URI.
     */
    function imageData(uint256 tokenId) private pure returns (string memory) {
        bytes7[16] memory palettes = [
            bytes7("#EAF0B5"),
            "#DDECBF",
            "#D0E7CA",
            "#B5DDD8",
            "#A8D8DC",
            "#81C4E7",
            "#7BBCE7",
            "#7EB2E4",
            "#88A5DD",
            "#9398D2",
            "#9B8AC4",
            "#9A709E",
            "#906388",
            "#805770",
            "#684957",
            "#46353A"
        ];
        string[16] memory points = [
            string("0 115.47 "),
            "16.67 86.6 ",
            "50 144.34 ",
            "50 28.87 ",
            "50 86.6 ",
            "83.33 86.6 ",
            "100 0 ",
            "100 115.47 ",
            "100 57.73 ",
            "116.67 144.34 ",
            "116.67 28.87 ",
            "150 144.34 ",
            "150 28.87 ",
            "150 86.6 ",
            "183.33 144.34 ",
            "200 115.47 "
        ];
        uint8[3][16] memory polygons = [
            [15, 13, 14],
            [14, 11, 13],
            [9, 13, 11],
            [13, 7, 9],
            [1, 0, 2],
            [1, 4, 2],
            [2, 5, 4],
            [2, 7, 5],
            [5, 13, 7],
            [5, 8, 13],
            [4, 5, 3],
            [8, 3, 5],
            [8, 10, 3],
            [13, 12, 10],
            [8, 10, 13],
            [3, 6, 10]
        ];
        bytes memory svg = abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" preserveAspectRatio="xMidYMid meet" viewBox="0 0 200 144.34">'
        );
        for (uint8 p = 0; p < polygons.length; p++) {
            svg = abi.encodePacked(
                svg,
                '<polygon fill="',
                palettes[((tokenId >> (p * 4)) & 15)],
                '" points="',
                points[polygons[p][0]],
                points[polygons[p][1]],
                points[polygons[p][2]],
                points[polygons[p][0]],
                '"/>'
            );
        }
        svg = abi.encodePacked(svg, "</svg>");
        return string(abi.encodePacked("data:image/svg+xml;base64,", Base64.encode(svg)));
    }

    /**
     * @notice Returns the contract-level metadata URI.
     * @dev Provides contract metadata as a data URI containing a base64 encoded JSON object.
     * @return Contract URI string.
     */
    function contractURI() public pure returns (string memory) {
        bytes memory json = abi.encodePacked(
            "data:application/json;utf8,",
            "{",
            '"name": "',
            TOKEN_NAME,
            '", "description": "',
            TOKEN_DESC,
            '", "image_data": "',
            imageData(0xB67A9854CDEF3210),
            '", "external_url": "',
            _baseURI(),
            '"}'
        );
        return string(json);
    }

    /**
     * @notice Checks if the contract supports a given interface.
     * @dev Implements ERC165 interface detection.
     * @param interfaceId The interface identifier.
     * @return True if the contract implements the requested interface, false otherwise.
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
