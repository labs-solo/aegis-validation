// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AegisWhitelistValidationHook} from "../validationHooks/AegisWhitelistValidationHook.sol";
import {ContinuousClearingAuction} from "continuous-clearing-auction/src/ContinuousClearingAuction.sol";
import {AuctionParameters} from "continuous-clearing-auction/src/interfaces/IContinuousClearingAuction.sol";
import {ConstantsLib} from "continuous-clearing-auction/src/libraries/ConstantsLib.sol";
import {Create2} from "@openzeppelin-latest/contracts/utils/Create2.sol";

/// @title AegisHookedAuctionFactory
/// @notice Deploys a validation hook ahead of time, then later deploys the auction.
contract AegisHookedAuctionFactory {
    struct AuctionDeployConfig {
        address hook; // Validation hook that gates bids.
        address token; // Token being sold by the auction.
        uint128 amount; // Total token amount allocated to the auction.
        address currency; // Currency used for bids (address(0) for native).
        address tokensRecipient; // Recipient of any unsold tokens.
        address fundsRecipient; // Recipient of all raised funds.
        uint256 tickSpacing; // Price tick spacing for the auction book.
        uint256 floorPrice; // Minimum starting price for bids.
        uint128 requiredCurrencyRaised; // Graduation threshold for the auction.
        uint64 startBlock; // Block when the auction starts.
        uint40 auctionDurationBlocks; // Total number of blocks the auction runs.
        uint64 claimDelayBlocks; // Blocks after end before claims are allowed.
        bytes auctionStepsData; // Packed (mps, blockDelta) steps; empty to auto-build equal steps.
    }

    error InvalidHookAddress();
    error InvalidAuctionDuration(uint40 durationBlocks);

    event HookDeployed(address indexed hook, address indexed owner);
    event AuctionDeployed(address indexed hook, address indexed auction, address indexed caller, bytes32 salt);

    /// @notice Deploy a hook.
    /// @param v4PositionManager The v4 position manager used for tier-three gating.
    function deployHook(address v4PositionManager) external returns (address hook) {
        AegisWhitelistValidationHook hook_ = new AegisWhitelistValidationHook(v4PositionManager);
        hook_.transferOwnership(msg.sender);

        hook = address(hook_);
        emit HookDeployed(hook, msg.sender);
    }

    /// @notice Deploy an auction using CREATE2.
    /// @param cfg Deployment configuration for the auction.
    /// @param salt User-provided salt used with CREATE2.
    function deployAuction(AuctionDeployConfig calldata cfg, bytes32 salt) external returns (address auction) {
        if (cfg.hook == address(0)) revert InvalidHookAddress();

        bytes memory steps = cfg.auctionStepsData;
        if (steps.length == 0) {
            steps = _buildEqualSteps(cfg.auctionDurationBlocks);
        }

        uint64 endBlock = cfg.startBlock + uint64(cfg.auctionDurationBlocks);
        uint64 claimBlock = endBlock + cfg.claimDelayBlocks;

        AuctionParameters memory params = AuctionParameters({
            currency: cfg.currency,
            tokensRecipient: cfg.tokensRecipient,
            fundsRecipient: cfg.fundsRecipient,
            startBlock: cfg.startBlock,
            endBlock: endBlock,
            claimBlock: claimBlock,
            tickSpacing: cfg.tickSpacing,
            validationHook: cfg.hook,
            floorPrice: cfg.floorPrice,
            requiredCurrencyRaised: cfg.requiredCurrencyRaised,
            auctionStepsData: steps
        });

        ContinuousClearingAuction auction_ =
            new ContinuousClearingAuction{salt: salt}(cfg.token, cfg.amount, params);

        auction = address(auction_);
        emit AuctionDeployed(cfg.hook, auction, msg.sender, salt);
    }

    /// @notice Compute the CREATE2 address for an auction deployment.
    /// @param cfg Deployment configuration for the auction.
    /// @param salt User-provided salt used with CREATE2.
    function getAuctionAddress(AuctionDeployConfig calldata cfg, bytes32 salt)
        external
        view
        returns (address)
    {
        if (cfg.hook == address(0)) revert InvalidHookAddress();

        bytes memory steps = cfg.auctionStepsData;
        if (steps.length == 0) {
            steps = _buildEqualSteps(cfg.auctionDurationBlocks);
        }

        uint64 endBlock = cfg.startBlock + uint64(cfg.auctionDurationBlocks);
        uint64 claimBlock = endBlock + cfg.claimDelayBlocks;

        AuctionParameters memory params = AuctionParameters({
            currency: cfg.currency,
            tokensRecipient: cfg.tokensRecipient,
            fundsRecipient: cfg.fundsRecipient,
            startBlock: cfg.startBlock,
            endBlock: endBlock,
            claimBlock: claimBlock,
            tickSpacing: cfg.tickSpacing,
            validationHook: cfg.hook,
            floorPrice: cfg.floorPrice,
            requiredCurrencyRaised: cfg.requiredCurrencyRaised,
            auctionStepsData: steps
        });

        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(ContinuousClearingAuction).creationCode, abi.encode(cfg.token, cfg.amount, params)));
        return Create2.computeAddress(salt, initCodeHash, address(this));
    }

    function _buildEqualSteps(uint40 durationBlocks) private pure returns (bytes memory) {
        if (durationBlocks == 0 || durationBlocks > ConstantsLib.MPS) {
            revert InvalidAuctionDuration(durationBlocks);
        }

        uint24 base = uint24(ConstantsLib.MPS / durationBlocks);
        uint40 rem = uint40(ConstantsLib.MPS % durationBlocks);

        if (rem == 0) {
            return abi.encodePacked(base, durationBlocks);
        }

        return abi.encodePacked(uint24(base + 1), rem, base, durationBlocks - rem);
    }
}
