// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IAegisWhitelistValidationHook} from "../interfaces/IAegisWhitelistValidationHook.sol";
import {IContinuousClearingAuction} from "continuous-clearing-auction/src/interfaces/IContinuousClearingAuction.sol";

contract AegisWhitelistValidationHook is IAegisWhitelistValidationHook, Ownable, ERC1155 {
    uint8 public constant TIER_ONE = 0;
    uint8 public constant TIER_TWO = 1;
    uint8 public constant TIER_THREE = 2;
    uint256 public constant MINT_PRICE = 0.001 ether;

    bool public validationBypassed = false;
    bool public mintingEnabled = true;

    mapping(address => address) public referrerOf;
    mapping(uint8 => uint128) public maxBidByTier;
    address public auction;
    uint64 public auctionStart;
    uint64 public phaseOneDuration;
    uint64 public phaseTwoDuration;
    string public tokenURI;

    constructor()
        Ownable()
        ERC1155("")
    {
        maxBidByTier[TIER_ONE] = 2 ether;
        maxBidByTier[TIER_TWO] = 10 ether;
        maxBidByTier[TIER_THREE] = 50 ether;
    }

    function startAuction(address auctionAddress, uint64 phaseOneBlocks, uint64 phaseTwoBlocks) external onlyOwner {
        if (auctionStart != 0) revert AuctionAlreadyStarted(auctionStart);
        if (auctionAddress == address(0)) revert AuctionNotSet();
        auction = auctionAddress;
        auctionStart = IContinuousClearingAuction(auctionAddress).startBlock();
        if (auctionStart == 0) revert AuctionNotStarted();
        phaseOneDuration = phaseOneBlocks;
        phaseTwoDuration = phaseTwoBlocks;
    }

    function removeValidation(bool bypass) external onlyOwner {
        validationBypassed = bypass;
    }

    function setMintingEnabled(bool enabled) external onlyOwner {
        mintingEnabled = enabled;
    }

    function mintTierOne(address referrer) external payable {
        if (!mintingEnabled) revert MintingDisabled();
        _assertMintPrice();
        _setReferrer(msg.sender, referrer);
        if (balanceOf(msg.sender, TIER_ONE) != 0) revert AlreadyHasTier(TIER_ONE, msg.sender);
        _mint(msg.sender, TIER_ONE, 1, "");
    }

    function mintTierTwo(address referrer) external payable {
        if (!mintingEnabled) revert MintingDisabled();
        _assertMintPrice();
        _setReferrer(msg.sender, referrer);
        if (balanceOf(msg.sender, TIER_TWO) != 0) revert AlreadyHasTier(TIER_TWO, msg.sender);
        _mint(msg.sender, TIER_TWO, 1, "");
    }

    function mintTierThree(address referrer) external payable {
        if (!mintingEnabled) revert MintingDisabled();
        _assertMintPrice();
        _setReferrer(msg.sender, referrer);
        if (balanceOf(msg.sender, TIER_THREE) != 0) revert AlreadyHasTier(TIER_THREE, msg.sender);
        _mint(msg.sender, TIER_THREE, 1, "");
    }

    function uri(uint256) public view override returns (string memory) {
        return tokenURI;
    }

    function setTokenURI(string memory _uri) external onlyOwner {
        tokenURI = _uri;
    }

    function validate(uint256, uint128 amount, address owner, address sender, bytes calldata) external override {
        if (validationBypassed) return;
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

    function withdraw(address to) external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) return;
        (bool success, ) = to.call{value: balance}("");
        require(success, "WITHDRAW_FAILED");
    }

    function _assertMintPrice() private view {
        if (msg.value < MINT_PRICE) revert InvalidMintPrice(msg.value, MINT_PRICE);
    }

    function _setReferrer(address to, address referrer) private {
        if (referrerOf[to] != address(0)) return;
        referrerOf[to] = referrer;
        emit ReferrerSet(to, referrer);
    }

    function currentPhase() public view returns (uint8) {
        uint64 start = auctionStart;
        if (start == 0 || block.number < start) return 0;
        uint256 elapsed = block.number - uint256(start);
        if (elapsed < phaseOneDuration) return 1;
        if (elapsed < uint256(phaseOneDuration) + uint256(phaseTwoDuration)) return 2;
        return 3;
    }

    function blocksUntilPhaseTwo() public view returns (uint256) {
        uint64 start = auctionStart;
        if (start == 0 || block.number < start) return type(uint256).max;
        uint256 phaseTwoStart = uint256(start) + uint256(phaseOneDuration);
        if (block.number >= phaseTwoStart) return 0;
        return phaseTwoStart - block.number;
    }

    function blocksUntilPhaseThree() public view returns (uint256) {
        uint64 start = auctionStart;
        if (start == 0 || block.number < start) return type(uint256).max;
        uint256 phaseThreeStart = uint256(start) + uint256(phaseOneDuration) + uint256(phaseTwoDuration);
        if (block.number >= phaseThreeStart) return 0;
        return phaseThreeStart - block.number;
    }
}
