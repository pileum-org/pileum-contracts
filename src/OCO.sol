// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IOCO} from "./interfaces/IOCO.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Bridgeable} from "@openzeppelin/community-contracts/token/ERC20/extensions/ERC20Bridgeable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title O=C=O ERC20 token
/// @author pileum.org
/// @notice O=C=O tokens represent CO2e emissions.
/// @dev This contract uses AccessControl for role-based permissions allowing flexible administrative control,
///      as well as ERC20 and ERC20Bridgeable for token and bridge functionality.
/// @custom:security-contact security@pileum.org
contract OCO is IOCO, ERC20, ERC20Bridgeable, AccessControl {
    /// @notice Predeployed Superchain Token Bridge address.
    address internal constant SUPERCHAIN_TOKEN_BRIDGE = 0x4200000000000000000000000000000000000028;

    /// @notice Role identifier for accounts that are allowed to mint tokens and track burns.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Error thrown when an unauthorized address attempts to call a restricted function.
    error Unauthorized();

    /// @notice Mapping that tracks the cumulative burned token amounts for each account.
    mapping(address account => uint256) private _burned;

    /// @notice Emitted when tokens are burned.
    /// @param account The address from which tokens were burned.
    /// @param total The cumulative total of tokens burned by the account.
    /// @param value The amount of tokens burned in this operation.
    event Burn(address indexed account, uint256 total, uint256 value);

    /// @notice Constructor that initializes the token with a name, symbol, and sets the initial admin.
    /// @dev Grants DEFAULT_ADMIN_ROLE to the provided defaultAdmin.
    /// @param defaultAdmin The address to be set as the initial admin with full access control privileges.
    constructor(address defaultAdmin) ERC20("O=C=O", "OCO") {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    /// @notice Mints new tokens to a specified address.
    /// @dev Only callable by accounts with the MINTER_ROLE. Uses ERC20 _mint internally.
    /// @param to The address receiving the minted tokens.
    /// @param amount The number of tokens to mint.
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @notice Manually tracks burned tokens for an account.
    /// @dev Updates the internal burn record and emits a Burn event. Only callable by accounts with the MINTER_ROLE.
    /// @param to The account whose burn record will be updated.
    /// @param amount The number of tokens to add to the burn record.
    function trackBurn(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _trackBurn(to, amount);
    }

    /// @notice Burns a specified amount of tokens from the caller's account.
    /// @dev Reduces the caller's balance and updates the burn tracking. See {ERC20-_burn}.
    /// @param value The amount of tokens to burn.
    function burn(uint256 value) public {
        _burn(_msgSender(), value);
        _trackBurn(_msgSender(), value);
    }

    /// @notice Burns a specified amount of tokens from a target account using the caller's allowance.
    /// @dev Reduces the target account's balance and the caller's allowance accordingly.
    ///      See {ERC20-_burn} and {ERC20-allowance}.
    /// @param account The account from which tokens will be burned.
    /// @param value The amount of tokens to burn.
    function burnFrom(address account, uint256 value) public {
        _spendAllowance(account, _msgSender(), value);
        _burn(account, value);
        _trackBurn(account, value);
    }

    /// @notice Internal function to update the burn record for an account.
    /// @dev Increments the burned token count for the account and emits a Burn event.
    /// @param account The account whose burn record is being updated.
    /// @param value The amount of tokens that were burned.
    function _trackBurn(address account, uint256 value) internal {
        _burned[account] += value;
        emit Burn(account, _burned[account], value);
    }

    /// @notice Retrieves the total burned tokens recorded for a specific account.
    /// @param account The address for which the burned token total is queried.
    /// @return The cumulative burned token count for the account.
    function burnedBalanceOf(address account) public view returns (uint256) {
        return _burned[account];
    }

    /// @notice Verifies that the caller is the designated Superchain Token Bridge.
    /// @dev Reverts with {Unauthorized} if the caller is not the predeployed Superchain Token Bridge.
    ///      This function is part of the ERC20Bridgeable interface.
    /// @param caller The address to be validated as the token bridge.
    function _checkTokenBridge(address caller) internal pure override {
        if (caller != SUPERCHAIN_TOKEN_BRIDGE) revert Unauthorized();
    }

    /// @notice Indicates which interfaces are supported by this contract.
    /// @dev Combines support for both ERC20Bridgeable and AccessControl interfaces.
    /// @param interfaceId The interface identifier, as specified in ERC165.
    /// @return A boolean indicating whether the interface is supported.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC20Bridgeable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
