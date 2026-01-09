// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IAegisWhitelistValidationHook} from "../interfaces/IAegisWhitelistValidationHook.sol";

contract AegisWhitelistValidationHook is IAegisWhitelistValidationHook, Ownable, ERC1155 {
    uint8 public constant TIER_ONE = 0;
    uint8 public constant TIER_TWO = 1;
    uint8 public constant TIER_THREE = 2;

    mapping(uint8 => uint128) public maxBidByTier;
    uint64 public auctionStart;
    uint64 public phaseOneDuration;
    uint64 public phaseTwoDuration;
    string public tokenURI;

    // Initialize tier max bids for each membership tier.
    constructor(uint128 maxBidTierOne, uint128 maxBidTierTwo, uint128 maxBidTierThree)
        Ownable()
        ERC1155("Aegis Auction Pass")
    {
        maxBidByTier[TIER_ONE] = maxBidTierOne;
        maxBidByTier[TIER_TWO] = maxBidTierTwo;
        maxBidByTier[TIER_THREE] = maxBidTierThree;
    }

    // Owner-only start for the tiered access windows.
    function startAuction(uint64 phaseOneBlocks, uint64 phaseTwoBlocks) external onlyOwner {
        if (auctionStart != 0) revert AuctionAlreadyStarted(auctionStart);
        auctionStart = uint64(block.number);
        phaseOneDuration = phaseOneBlocks;
        phaseTwoDuration = phaseTwoBlocks;
    }

    // Owner-only minting for each tier membership token.
    function mintTierOne(address to) external onlyOwner {
        if (balanceOf(to, TIER_ONE) != 0) revert AlreadyHasTier(TIER_ONE, to);
        _mint(to, TIER_ONE, 1, "");
    }

    function mintTierTwo(address to) external onlyOwner {
        if (balanceOf(to, TIER_TWO) != 0) revert AlreadyHasTier(TIER_TWO, to);
        _mint(to, TIER_TWO, 1, "");
    }

    function mintTierThree(address to) external onlyOwner {
        if (balanceOf(to, TIER_THREE) != 0) revert AlreadyHasTier(TIER_THREE, to);
        _mint(to, TIER_THREE, 1, "");
    }

    function uri(uint256) public view override returns (string memory) {
        return tokenURI;
    }

    function setTokenURI(string memory _uri) external onlyOwner {
        tokenURI = _uri;
    }

    // Validate bids using tier membership and time-window gating.
    function validate(uint256, uint128 amount, address owner, address sender, bytes calldata) external override {
        if (owner != sender) revert OwnerSenderMismatch(owner, sender);

        uint64 start = auctionStart;
        if (start == 0) revert AuctionNotStarted();

        uint256 elapsed = block.number - uint256(start);
        uint128 maxBid = 0;

        if (elapsed < phaseOneDuration) {
            if (balanceOf(owner, TIER_THREE) > 0) {
                maxBid = maxBidByTier[TIER_THREE];
            }
        } else if (elapsed < uint256(phaseOneDuration) + uint256(phaseTwoDuration)) {
            if (balanceOf(owner, TIER_THREE) > 0) {
                maxBid = maxBidByTier[TIER_THREE];
            }
            if (balanceOf(owner, TIER_TWO) > 0 && maxBidByTier[TIER_TWO] > maxBid) {
                maxBid = maxBidByTier[TIER_TWO];
            }
        } else {
            if (balanceOf(owner, TIER_THREE) > 0) {
                maxBid = maxBidByTier[TIER_THREE];
            }
            if (balanceOf(owner, TIER_TWO) > 0 && maxBidByTier[TIER_TWO] > maxBid) {
                maxBid = maxBidByTier[TIER_TWO];
            }
            if (balanceOf(owner, TIER_ONE) > 0 && maxBidByTier[TIER_ONE] > maxBid) {
                maxBid = maxBidByTier[TIER_ONE];
            }
        }

        if (maxBid == 0) revert NoEligibleTier();
        if (amount > maxBid) revert ExceedsTierMaxBid(amount, maxBid);
    }

    function currentPhase() public view returns (uint8) {
        uint64 start = auctionStart;
        if (start == 0) return 0;
        uint256 elapsed = block.number - uint256(start);
        if (elapsed < phaseOneDuration) return 1;
        if (elapsed < uint256(phaseOneDuration) + uint256(phaseTwoDuration)) return 2;
        return 3;
    }

    function blocksUntilPhaseTwo() public view returns (uint256) {
        uint64 start = auctionStart;
        if (start == 0) return 0;
        uint256 phaseTwoStart = uint256(start) + uint256(phaseOneDuration);
        if (block.number >= phaseTwoStart) return 0;
        return phaseTwoStart - block.number;
    }

    function blocksUntilPhaseThree() public view returns (uint256) {
        uint64 start = auctionStart;
        if (start == 0) return 0;
        uint256 phaseThreeStart = uint256(start) + uint256(phaseOneDuration) + uint256(phaseTwoDuration);
        if (block.number >= phaseThreeStart) return 0;
        return phaseThreeStart - block.number;
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override {
        if (from != address(0) && to != address(0)) revert TransfersDisabled();
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}
