// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IValidationHook} from "continuous-clearing-auction/src/interfaces/IValidationHook.sol";

/// @title IAegisWhitelistValidationHook
/// @notice Interface for the tiered membership validation hook used by the auction.
interface IAegisWhitelistValidationHook is IValidationHook {
    /// @notice Emitted when a minter sets their referrer for the first time.
    /// @param minter The minter address.
    /// @param referrer The referrer address.
    event ReferrerSet(address indexed minter, address indexed referrer);
    /// @notice Thrown when the auction start has not been initialized.
    error AuctionNotStarted();

    /// @notice Thrown when the auction address has not been configured.
    error AuctionNotSet();

    /// @notice Thrown when attempting to start the auction twice.
    /// @param startedAt The block number of the existing start.
    error AuctionAlreadyStarted(uint64 startedAt);

    /// @notice Thrown when a bid exceeds the tier max bid for the current window.
    /// @param attempted The bid amount.
    /// @param maxBid The maximum allowed bid for the current window.
    error ExceedsTierMaxBid(uint256 attempted, uint256 maxBid);

    /// @notice Thrown when the bidder does not hold any eligible tier token.
    error NoEligibleTier();

    /// @notice Thrown when the bid owner does not match the sender.
    /// @param owner The bid owner address.
    /// @param sender The caller address.
    error OwnerSenderMismatch(address owner, address sender);

    /// @notice Thrown when attempting to transfer a non-transferable tier token.
    error TransfersDisabled();

    /// @notice Thrown when minting a tier token to an account that already has it.
    /// @param tier The tier id.
    /// @param account The account that already holds the tier token.
    error AlreadyHasTier(uint8 tier, address account);

    /// @notice Thrown when minting is disabled.
    error MintingDisabled();

    /// @notice Thrown when the mint price is incorrect.
    /// @param sent The amount of ether sent.
    /// @param expected The expected mint price.
    error InvalidMintPrice(uint256 sent, uint256 expected);

    /// @notice Returns the max bid amount for a tier.
    /// @param tier The tier id.
    /// @return maxBid The max bid amount in wei.
    function maxBidByTier(uint8 tier) external view returns (uint128 maxBid);

    /// @notice Returns the auction start block.
    /// @return startBlock The start block number.
    function auctionStart() external view returns (uint64 startBlock);

    /// @notice Returns the configured auction address.
    function auction() external view returns (address);

    /// @notice Returns the phase one duration in blocks.
    /// @return duration The phase one duration in blocks.
    function phaseOneDuration() external view returns (uint64 duration);

    /// @notice Returns the phase two duration in blocks.
    /// @return duration The phase two duration in blocks.
    function phaseTwoDuration() external view returns (uint64 duration);

    /// @notice Returns the current metadata URI.
    /// @return uri The token URI string.
    function tokenURI() external view returns (string memory uri);

    /// @notice Start the tiered access windows using the auction's configured start block.
    /// @param auctionAddress The auction contract address.
    /// @param phaseOneBlocks The number of blocks for the tier-three-only phase.
    /// @param phaseTwoBlocks The number of blocks for the tier-two-and-three phase.
    function startAuction(address auctionAddress, uint64 phaseOneBlocks, uint64 phaseTwoBlocks) external;

    /// @notice Toggle whether minting is enabled.
    /// @param enabled Set true to enable minting.
    function setMintingEnabled(bool enabled) external;

    /// @notice Returns whether minting is enabled.
    function mintingEnabled() external view returns (bool);

    /// @notice Returns the referrer set for a minter.
    /// @param minter The minter address.
    function referrerOf(address minter) external view returns (address);

    /// @notice Toggle validation checks for bids.
    /// @param bypass Set true to bypass validation.
    function removeValidation(bool bypass) external;

    /// @notice Returns whether validation is currently bypassed.
    function validationBypassed() external view returns (bool);

    /// @notice Returns the current phase (0 = not started, 1 = tier three, 2 = tier two/three, 3 = all tiers).
    function currentPhase() external view returns (uint8);

    /// @notice Returns remaining blocks until phase two begins (max uint256 if not started yet).
    function blocksUntilPhaseTwo() external view returns (uint256);

    /// @notice Returns remaining blocks until phase three begins (max uint256 if not started yet).
    function blocksUntilPhaseThree() external view returns (uint256);

    /// @notice Mint a tier-one membership token.
    /// @param referrer The referrer address for this minter.
    function mintTierOne(address referrer) external payable;

    /// @notice Mint a tier-two membership token.
    /// @param referrer The referrer address for this minter.
    function mintTierTwo(address referrer) external payable;

    /// @notice Mint a tier-three membership token.
    /// @param referrer The referrer address for this minter.
    function mintTierThree(address referrer) external payable;

    /// @notice Withdraw accumulated mint proceeds.
    /// @param to The recipient of the funds.
    function withdraw(address to) external;

    /// @notice Update the metadata URI used for all tier tokens.
    /// @param _uri The new metadata URI.
    function setTokenURI(string memory _uri) external;
}
