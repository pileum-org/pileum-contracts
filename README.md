# Pileum Smart Contracts

- **[ERC721](src/ERC721.sol)**: A modified version of the [OpenZeppelin ERC721 contract](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.1.0/contracts/token/ERC721/ERC721.sol) that implements an epoch mechanism.
- **[ERC721Votes](src/ERC721Votes.sol)**: A modified version of the [OpenZeppelin ERC721Votes contract](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.1.0/contracts/token/ERC721/extensions/ERC721Votes.sol) with epoch support.
- **[Votes](src/Votes.sol)**: A modified version of the [OpenZeppelin Votes contract](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.1.0/contracts/governance/utils/Votes.sol) that adds epoch functionality.
- **[Pileus](src/Pileus.sol)**: An `ERC721` token whose validity is limited to the epoch (e.g., year) of minting.
- **[WorldIDVerifier](src/verifiers/WorldIDVerifier.sol)**: Verifies [World ID proofs](https://docs.world.org/world-id/) and issues **Pileus** tokens.
- **[MockWorldID](src/MockWorldID.sol)**: A mock implementation of the [World ID Router](https://docs.world.org/world-id/id/on-chain) for development purposes. Implements the `IWorldID` interface.
- **[OCO](src/OCO.sol)**: An `ERC20` token with burn tracking functionality.
- **[TOTC](src/TOTC.sol)**: Manages **OCO** token allowances based on the supply of **Pileus** tokens.

---
