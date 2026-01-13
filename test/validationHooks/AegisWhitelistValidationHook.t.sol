// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {AegisWhitelistValidationHook} from "../../src/validationHooks/AegisWhitelistValidationHook.sol";
import {ContinuousClearingAuction} from "continuous-clearing-auction/src/ContinuousClearingAuction.sol";
import {AuctionParameters} from "continuous-clearing-auction/src/interfaces/IContinuousClearingAuction.sol";
import {AuctionStepsBuilder} from "continuous-clearing-auction/test/utils/AuctionStepsBuilder.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";

contract AegisWhitelistValidationHookTest is Test {
    using AuctionStepsBuilder for bytes;

    uint128 private constant TOTAL_SUPPLY = 1_000e18;
    uint256 private constant FLOOR_PRICE = 1000 << FixedPoint96.RESOLUTION;
    uint256 private constant TICK_SPACING = 100 << FixedPoint96.RESOLUTION;

    uint256 private constant MINT_PRICE = 0.001 ether;

    uint64 private constant PHASE_ONE_BLOCKS = 26;
    uint64 private constant PHASE_TWO_BLOCKS = 24;

    address private alice;
    address private bob;
    AegisWhitelistValidationHook private hook;
    ContinuousClearingAuction private auction;
    MockERC20 private token;

    function setUp() public {
        vm.deal(address(this), 100 ether);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        hook = new AegisWhitelistValidationHook();

        bytes memory steps = AuctionStepsBuilder.init().addStep(100e3, 50).addStep(100e3, 50);
        AuctionParameters memory params = AuctionParameters({
            currency: address(0),
            tokensRecipient: makeAddr("tokensRecipient"),
            fundsRecipient: makeAddr("fundsRecipient"),
            startBlock: uint64(block.number),
            endBlock: uint64(block.number + 100),
            claimBlock: uint64(block.number + 110),
            tickSpacing: TICK_SPACING,
            validationHook: address(hook),
            floorPrice: FLOOR_PRICE,
            requiredCurrencyRaised: 0,
            auctionStepsData: steps
        });

        token = new MockERC20("Test Token", "TEST", TOTAL_SUPPLY, address(this));
        auction = new ContinuousClearingAuction(address(token), TOTAL_SUPPLY, params);
        token.transfer(address(auction), TOTAL_SUPPLY);
        auction.onTokensReceived();
    }

    function test_submitBid_requiresAuctionStarted_reverts() public {
        hook.mintTierThree{value: MINT_PRICE}(alice);
        vm.deal(alice, 3 ether);
        vm.prank(alice);
        vm.expectRevert();
        auction.submitBid{value: 2 ether}(FLOOR_PRICE + TICK_SPACING, 2 ether, alice, bytes(""));
    }

    function test_submitBid_tierThreeOnlyWindow_allowsTierThree() public {
        _startAuction();
        _rollAfter(1);
        hook.mintTierThree{value: MINT_PRICE}(alice);
        vm.deal(alice, 3 ether);
        vm.prank(alice);
        uint256 bidId = auction.submitBid{value: 2 ether}(FLOOR_PRICE + TICK_SPACING, 2 ether, alice, bytes(""));

        assertEq(bidId, 0);
    }

    function test_submitBid_tierThreeOnlyWindow_rejectsTierTwo() public {
        _startAuction();
        _rollAfter(1);
        hook.mintTierTwo{value: MINT_PRICE}(bob);
        vm.deal(bob, 3 ether);
        vm.prank(bob);
        vm.expectRevert();
        auction.submitBid{value: 2 ether}(FLOOR_PRICE + TICK_SPACING, 2 ether, bob, bytes(""));
    }

    function test_submitBid_tierTwoWindow_allowsTierTwo() public {
        _startAuction();
        _rollAfter(uint256(PHASE_ONE_BLOCKS) + 1);
        hook.mintTierTwo{value: MINT_PRICE}(bob);
        vm.deal(bob, 6 ether);
        vm.prank(bob);
        uint256 bidId = auction.submitBid{value: 4 ether}(FLOOR_PRICE + TICK_SPACING, 4 ether, bob, bytes(""));

        assertEq(bidId, 0);
    }

    function test_submitBid_allTiersWindow_allowsTierOne() public {
        _startAuction();
        _rollAfter(uint256(PHASE_ONE_BLOCKS) + uint256(PHASE_TWO_BLOCKS) + 1);
        hook.mintTierOne{value: MINT_PRICE}(alice);
        vm.deal(alice, 3 ether);
        vm.prank(alice);
        uint256 bidId = auction.submitBid{value: 2 ether}(FLOOR_PRICE + TICK_SPACING, 2 ether, alice, bytes(""));

        assertEq(bidId, 0);
    }

    function test_submitBid_exceedsTierLimit_reverts() public {
        _startAuction();
        _rollAfter(uint256(PHASE_ONE_BLOCKS) + uint256(PHASE_TWO_BLOCKS) + 1);
        hook.mintTierOne{value: MINT_PRICE}(alice);
        vm.deal(alice, 3 ether);
        vm.prank(alice);
        vm.expectRevert();
        auction.submitBid{value: 3 ether}(FLOOR_PRICE + TICK_SPACING, 3 ether, alice, bytes(""));
    }

    function test_submitBid_ownerMustMatchSender_reverts() public {
        _startAuction();
        _rollAfter(uint256(PHASE_ONE_BLOCKS) + uint256(PHASE_TWO_BLOCKS) + 1);
        hook.mintTierOne{value: MINT_PRICE}(alice);
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert();
        auction.submitBid{value: 1 ether}(FLOOR_PRICE + TICK_SPACING, 1 ether, alice, bytes(""));
    }

    function test_submitBid_bidIdStartsAtZeroAndIncrements() public {
        _startAuction();
        _rollAfter(uint256(PHASE_ONE_BLOCKS) + uint256(PHASE_TWO_BLOCKS) + 1);
        hook.mintTierOne{value: MINT_PRICE}(alice);
        hook.mintTierTwo{value: MINT_PRICE}(bob);

        vm.deal(alice, 3 ether);
        vm.prank(alice);
        uint256 firstBidId = auction.submitBid{value: 1 ether}(FLOOR_PRICE + TICK_SPACING, 1 ether, alice, bytes(""));
        assertEq(firstBidId, 0);

        vm.deal(bob, 3 ether);
        vm.prank(bob);
        uint256 secondBidId = auction.submitBid{value: 1 ether}(FLOOR_PRICE + TICK_SPACING, 1 ether, bob, bytes(""));
        assertEq(secondBidId, 1);
    }

    function test_submitBid_requiresTierToken_reverts() public {
        _startAuction();
        _rollAfter(uint256(PHASE_ONE_BLOCKS) + uint256(PHASE_TWO_BLOCKS) + 1);
        vm.deal(alice, 2 ether);
        vm.prank(alice);
        vm.expectRevert();
        auction.submitBid{value: 1 ether}(FLOOR_PRICE + TICK_SPACING, 1 ether, alice, bytes(""));
    }

    function _startAuction() private {
        hook.startAuction(address(auction), PHASE_ONE_BLOCKS, PHASE_TWO_BLOCKS);
    }

    function _rollAfter(uint256 delta) private {
        vm.roll(uint256(hook.auctionStart()) + delta);
    }

}
