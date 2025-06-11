// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPileus} from "./interfaces/IPileus.sol";
import {IOCO} from "./interfaces/IOCO.sol";

/// @title TOTC Contract
/// @author pileum.org
/// @notice Manages the OCO allowance and trading mechanisms for Pileus owners.
/// @dev OCO tokens can be minted only by this contract. It supports claiming, buying,
/// settling, and withdrawing based on per-epoch rules.
/// @custom:security-contact security@pileum.org
contract TOTC is Ownable, ReentrancyGuard {
    // =============================================================
    //                           EVENTS
    // =============================================================

    /// @notice Emitted when the allowance parameters are updated.
    /// @param allowanceSlope The new slope used in allowance calculations.
    /// @param allowanceIntercept The new intercept used in allowance calculations.
    event AllowanceUpdate(int256 allowanceSlope, int256 allowanceIntercept);

    /// @notice Emitted when a user buys OCO tokens by investing ETH.
    /// @param operator The address performing the buy operation.
    /// @param epoch The epoch in which the buy is executed.
    /// @param valuePerBlock The computed ETH value allocated per block.
    /// @param remainder The remaining ETH returned to the user.
    event Buy(address indexed operator, uint32 indexed epoch, uint128 valuePerBlock, uint128 remainder);

    /// @notice Emitted when a Pileus owner claims their OCO allowance.
    /// @param operator The address initiating the claim.
    /// @param tokenId The Pileus token id used for the claim.
    /// @param to The recipient address of the minted OCO tokens (or burn indicator if address(0)).
    /// @param amount The amount of OCO tokens claimed.
    /// @param used The updated claim index after the claim.
    event Claim(address indexed operator, uint256 indexed tokenId, address indexed to, uint128 amount, uint128 used);

    /// @notice Emitted when an account settles their invested ETH into OCO tokens.
    /// @param operator The address that settled the account.
    /// @param value The invested ETH value that was settled.
    /// @param amountQ128 The settled OCO token amount in fixed-point Q128.
    /// @param duration The number of blocks over which settlement was calculated.
    event Settle(address indexed operator, uint128 value, uint256 amountQ128, uint48 duration);

    /// @notice Emitted when a Pileus token owner withdraws proceeds from unclaimed allowance.
    /// @param operator The address withdrawing the proceeds.
    /// @param amount The amount of OCO allowance withdrawn.
    /// @param valueQ128 The corresponding ETH value in fixed-point Q128.
    event Withdraw(address indexed operator, uint128 amount, uint256 valueQ128);

    /// @notice Emitted when total balances are updated for an epoch.
    /// @param totalSupply Total OCO supply that could be invested.
    /// @param supplyClaimed Total OCO supply that has been claimed.
    /// @param supplyWithdrawn Total OCO supply that has been withdrawn.
    /// @param supplySettled Total OCO supply that has been settled (in Q128 fixed-point).
    /// @param valueInvested Total ETH invested.
    /// @param valueSettled Total ETH settled.
    /// @param valueWithdrawn Total ETH withdrawn (in Q128 fixed-point).
    event TotalBalancesUpdate(
        uint128 totalSupply,
        uint128 supplyClaimed,
        uint128 supplyWithdrawn,
        uint256 supplySettled,
        uint128 valueInvested,
        uint128 valueSettled,
        uint256 valueWithdrawn
    );

    // =============================================================
    //                        STORAGE VARIABLES
    // =============================================================

    uint256 internal constant Q128 = 1 << 128;
    uint48 private immutable _epochDuration;
    IPileus public immutable pileus;
    IOCO public immutable oco;
    int256 private _allowanceSlope;
    int256 private _allowanceIntercept;

    /// @notice Information for an account's buy order.
    /// @param valuePerBlk ETH invested per block (in wei).
    /// @param lastSettle Last block index at which settlement was executed.
    struct AccountInfo {
        uint128 valuePerBlk;
        uint48 lastSettle;
    }

    /// @notice Mapping for account information per epoch.
    /// @dev The key is generated via balancesKey(epoch, account).
    mapping(uint256 balancesKey => AccountInfo) private _balances;

    /// @notice Tracks the last claimed or withdrawn allowance (in blocks) per Pileus token.
    mapping(uint256 tokenId => uint48) private _allowances;

    /// @notice Aggregated totals for allowance and ETH values per epoch.
    /// @param supplyClaimed Total claimed OCO tokens.
    /// @param supplyWithdrawn Total OCO tokens withdrawn.
    /// @param supplySettled Total settled OCO tokens (fixed-point Q128).
    /// @param valueInvested Total ETH invested (in wei).
    /// @param valueSettled Total ETH settled (in wei).
    /// @param valueWithdrawn Total ETH withdrawn (fixed-point Q128).
    struct TotalBalances {
        uint128 supplyClaimed;
        uint128 supplyWithdrawn;
        uint256 supplySettled;
        uint128 valueInvested;
        uint128 valueSettled;
        uint256 valueWithdrawn;
    }

    /// @notice Mapping of total balances by epoch.
    mapping(uint32 epoch => TotalBalances) private _totals;

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    /// @notice Initializes the TOTC contract.
    /// @param initialOwner The address of the initial contract owner.
    /// @param _pileus The address of the Pileus ERC721 contract.
    /// @param _oco The address of the OCO ERC20 contract.
    /// @param allowanceSlope The initial slope for allowance calculation.
    /// @param allowanceIntercept The initial intercept for allowance calculation.
    constructor(address initialOwner, IPileus _pileus, IOCO _oco, int256 allowanceSlope, int256 allowanceIntercept)
        Ownable(initialOwner)
    {
        pileus = _pileus;
        oco = _oco;
        _epochDuration = pileus.EPOCH_DURATION();
        _allowanceSlope = allowanceSlope;
        _allowanceIntercept = allowanceIntercept;
    }

    // =============================================================
    //                         MUTATING FUNCTIONS
    // =============================================================

    /// @notice Updates the allowance calculation parameters.
    /// @param allowanceSlope The new slope for allowance calculation.
    /// @param allowanceIntercept The new intercept for allowance calculation.
    /// @param blockNumber If non-zero, requires execution at the specified block number.
    /// @dev Only the owner can call this function.
    function setAllowance(int256 allowanceSlope, int256 allowanceIntercept, uint48 blockNumber) public onlyOwner {
        if (blockNumber > 0) {
            require(blockNumber == block.number, "Can only be executed at specified block");
        }
        _allowanceSlope = allowanceSlope;
        _allowanceIntercept = allowanceIntercept;
        emit AllowanceUpdate(allowanceSlope, allowanceIntercept);
    }

    /// @notice Claims an OCO allowance for a given Pileus token.
    /// @param tokenId The Pileus token id.
    /// @param to The recipient address to receive OCO tokens (or zero address to track burn).
    /// @param duration The duration (in blocks) to claim.
    /// @return amount The amount of OCO tokens minted as a result of the claim.
    /// @dev Caller must be the token owner or approved. If the token was minted in the current epoch,
    /// any pending withdrawal is processed before claiming.
    function claim(uint256 tokenId, address to, uint48 duration) public nonReentrant returns (uint128 amount) {
        require(duration > 0, "Null claimed duration");
        (address owner, uint48 mintBlock) = pileus.propsOf(tokenId);
        require(
            msg.sender == owner || pileus.getApproved(tokenId) == msg.sender
                || pileus.isApprovedForAll(owner, msg.sender),
            "Caller is not token owner nor approved"
        );
        uint32 mintEpoch = SafeCast.toUint32(mintBlock / _epochDuration);
        require(mintEpoch >= currEpoch(), "Cannot claim past epoch");
        if (mintEpoch == currEpoch()) {
            _withdraw(tokenId, mintEpoch);
        }
        uint48 claimIndex = _allowances[tokenId] + duration;
        require(claimIndex <= _epochDuration, "Duration exceeds available allowance");
        amount = getAllowanceAtEpoch(mintEpoch, duration);
        _totals[mintEpoch].supplyClaimed += amount;
        _allowances[tokenId] += duration;

        if (to == address(0)) {
            oco.trackBurn(msg.sender, amount);
        } else {
            oco.mint(to, amount);
        }

        emit Claim(msg.sender, tokenId, to, amount, claimIndex);
        if (mintEpoch == currEpoch()) {
            _emitTotalBalancesUpdate(mintEpoch);
        }
    }

    /// @notice Invests ETH to buy OCO tokens for a specified epoch.
    /// @param epoch The epoch in which to buy tokens.
    /// @return remainder The remainder of ETH returned to the buyer if not fully utilized.
    /// @dev When buying in the current epoch, the settlement is triggered and the duration is adjusted.
    /// The ETH value is divided equally over the remaining blocks.
    function buy(uint32 epoch) public payable nonReentrant returns (uint128) {
        uint48 duration = _epochDuration;
        uint128 value = SafeCast.toUint128(msg.value);
        require(value > 0, "Value must be higher than zero");
        require(epoch >= currEpoch(), "Cannot buy past epoch");
        if (epoch == currEpoch()) {
            _settle(epoch);
            duration -= blockIndex();
        }
        require(getAllowanceAtEpoch(epoch, duration) > 0, "Nothing to buy");

        uint128 remainder = value % duration;
        uint128 valuePerBlock = value / duration;
        require(valuePerBlock > 0, "Invalid valuePerBlock");

        _balances[balancesKey(epoch, msg.sender)].valuePerBlk += valuePerBlock;
        _totals[epoch].valueInvested += (value - remainder);

        if (remainder > 0) {
            (bool sent,) = payable(msg.sender).call{value: remainder}("");
            require(sent, "Return of remainder failed");
        }

        emit Buy(msg.sender, epoch, valuePerBlock, remainder);
        if (epoch == currEpoch()) {
            _emitTotalBalancesUpdate(epoch);
        }
        return remainder;
    }

    /// @notice Settles invested ETH into OCO tokens for the specified epoch.
    /// @param epoch The epoch to settle.
    /// @return amount The amount of OCO tokens minted as a result of settling.
    /// @dev Can only settle for the current or past epochs.
    function settle(uint32 epoch) public nonReentrant returns (uint128 amount) {
        require(epoch <= currEpoch(), "Cannot settle future epoch");
        return _settle(epoch);
    }

    function _settle(uint32 epoch) internal returns (uint128 amount) {
        AccountInfo storage acc = _balances[balancesKey(epoch, msg.sender)];
        uint48 settleIndex = epoch == currEpoch() ? blockIndex() : _epochDuration;
        if (acc.lastSettle < settleIndex) {
            uint48 duration = settleIndex - acc.lastSettle;
            uint128 value = acc.valuePerBlk * duration;
            uint256 amountQ128 = settlePrice(epoch, value);
            amount = uint128(amountQ128 / Q128);
            if (amount > 0) {
                oco.mint(msg.sender, amount);
                TotalBalances storage t = _totals[epoch];
                t.valueSettled += value;
                t.supplySettled += amountQ128;
                emit Settle(msg.sender, value, amountQ128, duration);
                if (epoch == currEpoch()) {
                    _emitTotalBalancesUpdate(epoch);
                }
            }
            acc.lastSettle = settleIndex;
        }
    }

    /// @notice Withdraws ETH proceeds from unclaimed allowance for a given Pileus token.
    /// @param tokenId The Pileus token id.
    /// @return value The amount of ETH withdrawn (in wei).
    /// @dev Caller must be the token owner or approved. Withdrawal can only occur for current or past epochs.
    function withdraw(uint256 tokenId) public nonReentrant returns (uint128 value) {
        (address owner, uint48 mintBlock) = pileus.propsOf(tokenId);
        require(
            msg.sender == owner || pileus.getApproved(tokenId) == msg.sender
                || pileus.isApprovedForAll(owner, msg.sender),
            "Caller is not token owner nor approved"
        );
        uint32 mintEpoch = SafeCast.toUint32(mintBlock / _epochDuration);
        require(mintEpoch <= currEpoch(), "Cannot withdraw future epoch");
        return _withdraw(tokenId, mintEpoch);
    }

    /// @notice Internal function that processes the withdrawal of ETH proceeds.
    /// @param tokenId The Pileus token id.
    /// @param mintEpoch The epoch in which the token was minted.
    /// @return value The computed ETH value withdrawn (in wei).
    /// @dev Updates the token's allowance index and emits a Withdraw event.
    function _withdraw(uint256 tokenId, uint32 mintEpoch) internal returns (uint128 value) {
        uint48 withdrawIndex = mintEpoch == currEpoch() ? blockIndex() : _epochDuration;
        uint48 lastWithdraw = _allowances[tokenId];
        if (lastWithdraw < withdrawIndex) {
            uint128 amount = getAllowanceAtEpoch(mintEpoch, withdrawIndex - lastWithdraw);
            uint256 valueQ128 = withdrawPrice(mintEpoch, amount);
            value = uint128(valueQ128 / Q128);
            TotalBalances storage t = _totals[mintEpoch];
            t.valueWithdrawn += valueQ128;
            t.supplyWithdrawn += amount;
            _allowances[tokenId] = withdrawIndex;
            if (value > 0) {
                (bool sent,) = payable(msg.sender).call{value: value}("");
                require(sent, "Withdrawal transfer failed");
            }
            emit Withdraw(msg.sender, amount, valueQ128);
            if (mintEpoch == currEpoch()) {
                _emitTotalBalancesUpdate(mintEpoch);
            }
        }
    }

    function _emitTotalBalancesUpdate(uint32 epoch) internal {
        TotalBalances memory t = _totals[epoch];
        uint128 totalSupply = uint128(getTotalAllowanceSupply(epoch));
        emit TotalBalancesUpdate(
            totalSupply,
            t.supplyClaimed,
            t.supplyWithdrawn,
            t.supplySettled,
            t.valueInvested,
            t.valueSettled,
            t.valueWithdrawn
        );
    }

    // =============================================================
    //                          VIEW FUNCTIONS
    // =============================================================

    /// @notice Returns the current block index within the active epoch.
    /// @return The block index relative to the epoch duration.
    function blockIndex() public view returns (uint48) {
        return uint48(block.number) % _epochDuration;
    }

    /// @notice Returns the current epoch number.
    /// @return The current epoch computed from the block number.
    function currEpoch() public view returns (uint32) {
        return SafeCast.toUint32(block.number / _epochDuration);
    }

    /// @notice Generates a unique key for an account's balance information.
    /// @param epoch The epoch for which the key is generated.
    /// @param account The account address.
    /// @return A unique uint256 key composed of the epoch and account.
    function balancesKey(uint32 epoch, address account) public pure returns (uint256) {
        return (uint256(epoch) << 160) | uint256(uint160(account));
    }

    /// @notice Retrieves the account's investment information for a given epoch.
    /// @param epoch The epoch number.
    /// @param account The address of the account.
    /// @return valuePerBlk The ETH value invested per block.
    /// @return lastSettle The last block index when settlement occurred.
    function getAccountInfo(uint32 epoch, address account) external view returns (uint128, uint48) {
        AccountInfo memory acc = _balances[balancesKey(epoch, account)];
        return (acc.valuePerBlk, acc.lastSettle);
    }

    /// @notice Returns the current allowance (in blocks) already claimed or withdrawn for a token.
    /// @param tokenId The Pileus token id.
    /// @return The current allowance index.
    function getAllowance(uint256 tokenId) external view returns (uint48) {
        return _allowances[tokenId];
    }

    /// @notice Calculates the OCO token allowance for a given epoch and duration.
    /// @param epoch The epoch for which the allowance is computed.
    /// @param duration The duration (in blocks) to calculate allowance for.
    /// @return amount The computed OCO token amount for the specified duration.
    /// @dev Uses the allowanceSlope and allowanceIntercept parameters.
    function getAllowanceAtEpoch(uint32 epoch, uint48 duration) public view returns (uint128 amount) {
        if (duration > 0 && duration <= _epochDuration) {
            int256 allowancePerEpoch = (_allowanceSlope * int256(uint256(epoch))) + _allowanceIntercept;
            if (allowancePerEpoch > 0) {
                amount = SafeCast.toUint128(Math.mulDiv(uint256(allowancePerEpoch), duration, _epochDuration * Q128));
            }
        }
    }

    /// @notice Retrieves the current allowance calculation parameters.
    /// @return allowanceSlope The current allowance slope.
    /// @return allowanceIntercept The current allowance intercept.
    function getAllowanceParams() external view returns (int256, int256) {
        return (_allowanceSlope, _allowanceIntercept);
    }

    /// @notice Computes the total OCO allowance supply for an epoch.
    /// @param epoch The epoch number.
    /// @return totalSupply The total supply of OCO tokens available for allowance,
    /// calculated as the Pileus total supply multiplied by the allowance per epoch.
    /// @dev Uses current supply or past supply depending on the epoch.
    function getTotalAllowanceSupply(uint32 epoch) public view returns (uint256 totalSupply) {
        if (epoch == currEpoch()) {
            totalSupply = pileus.getTotalSupply();
        } else {
            uint48 epochEnd = (epoch + 1) * _epochDuration;
            require(epochEnd > 0, "Epoch end must be greater than zero");
            totalSupply = pileus.getPastTotalSupply(epochEnd - 1);
        }
        totalSupply *= getAllowanceAtEpoch(epoch, _epochDuration);
    }

    /// @notice Returns the aggregated totals for a given epoch.
    /// @param epoch The epoch number.
    /// @return supplyClaimed Total claimed OCO tokens.
    /// @return supplySettled Total settled OCO tokens (fixed-point Q128).
    /// @return supplyWithdrawn Total withdrawn OCO tokens.
    /// @return valueInvested Total ETH invested (in wei).
    /// @return valueSettled Total ETH settled (in wei).
    /// @return valueWithdrawn Total ETH withdrawn (fixed-point Q128).
    function getTotals(uint32 epoch) external view returns (uint128, uint256, uint128, uint128, uint128, uint256) {
        TotalBalances memory t = _totals[epoch];
        return (t.supplyClaimed, t.supplySettled, t.supplyWithdrawn, t.valueInvested, t.valueSettled, t.valueWithdrawn);
    }

    /// @notice Calculates the settlement price for a given invested ETH value.
    /// @param epoch The epoch number.
    /// @param value The invested ETH value (in wei) to be settled.
    /// @return amount The amount of OCO tokens (in Q128 fixed-point) computed for settlement.
    /// @dev The calculation is based on the remaining available allowance and the difference
    /// between invested and settled values.
    function settlePrice(uint32 epoch, uint128 value) public view returns (uint256 amount) {
        if (value > 0) {
            TotalBalances memory t = _totals[epoch];
            uint256 supplyInvestedQ128 = (getTotalAllowanceSupply(epoch) - t.supplyClaimed) * Q128;
            if (t.valueSettled < t.valueInvested && t.supplySettled < supplyInvestedQ128) {
                amount = Math.mulDiv((supplyInvestedQ128 - t.supplySettled), value, (t.valueInvested - t.valueSettled));
            }
        }
    }

    /// @notice Calculates the withdrawal price for a given amount of allowance.
    /// @param epoch The epoch number.
    /// @param amount The amount of OCO tokens for which to compute the ETH value.
    /// @return value The ETH value (in Q128 fixed-point) corresponding to the withdrawal.
    /// @dev The computation considers the remaining invested ETH and allowance that has not yet been withdrawn.
    function withdrawPrice(uint32 epoch, uint128 amount) public view returns (uint256 value) {
        if (amount > 0) {
            TotalBalances memory t = _totals[epoch];
            uint256 valueInvestedQ128 = t.valueInvested * Q128;
            uint256 supplyInvested = getTotalAllowanceSupply(epoch) - t.supplyClaimed;
            if (t.supplyWithdrawn < supplyInvested && t.valueWithdrawn < valueInvestedQ128) {
                value =
                    Math.mulDiv((valueInvestedQ128 - t.valueWithdrawn), amount, (supplyInvested - t.supplyWithdrawn));
            }
        }
    }
}
