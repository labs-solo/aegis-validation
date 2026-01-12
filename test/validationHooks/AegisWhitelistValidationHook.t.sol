// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {AegisWhitelistValidationHook} from "../../src/validationHooks/AegisWhitelistValidationHook.sol";
import {ContinuousClearingAuction} from "continuous-clearing-auction/src/ContinuousClearingAuction.sol";
import {AuctionParameters} from "continuous-clearing-auction/src/interfaces/IContinuousClearingAuction.sol";
import {AuctionStepsBuilder} from "continuous-clearing-auction/test/utils/AuctionStepsBuilder.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC721} from "../mocks/MockERC721.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";

contract AegisWhitelistValidationHookTest is Test {
    using AuctionStepsBuilder for bytes;

    uint128 private constant TOTAL_SUPPLY = 1_000e18;
    uint256 private constant FLOOR_PRICE = 1000 << FixedPoint96.RESOLUTION;
    uint256 private constant TICK_SPACING = 100 << FixedPoint96.RESOLUTION;

    uint8 private constant TIER_ONE_ID = 0;
    uint8 private constant TIER_TWO_ID = 1;
    uint8 private constant TIER_THREE_ID = 2;

    uint64 private constant SIGNATURE_DEADLINE = type(uint64).max;
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant MINT_TYPEHASH = keccak256("Mint(address account,uint8 tier,uint64 deadline)");
    string private constant SIGNING_DOMAIN = "AegisWhitelistValidationHook";
    string private constant SIGNING_VERSION = "1";

    uint64 private constant PHASE_ONE_BLOCKS = 26;
    uint64 private constant PHASE_TWO_BLOCKS = 24;

    address private alice;
    address private bob;
    address private carol;
    uint256 private aliceKey;
    uint256 private bobKey;

    AegisWhitelistValidationHook private hook;
    ContinuousClearingAuction private auction;
    MockERC20 private token;
    MockERC721 private positionManager;
    uint256 private nextTokenId;

    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");
        carol = makeAddr("carol");

        positionManager = new MockERC721("V4 Positions", "V4POS");
        hook = new AegisWhitelistValidationHook(address(positionManager));
        nextTokenId = 1;

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
        _mintV4Position(alice);
        _mintTierThree(alice, aliceKey);
        vm.deal(alice, 3 ether);
        vm.prank(alice);
        vm.expectRevert();
        auction.submitBid{value: 2 ether}(FLOOR_PRICE + TICK_SPACING, 2 ether, alice, bytes(""));
    }

    function test_submitBid_tierThreeOnlyWindow_allowsTierThree() public {
        _startAuction();
        _rollAfter(1);
        _mintV4Position(alice);
        _mintTierThree(alice, aliceKey);
        vm.deal(alice, 3 ether);
        vm.prank(alice);
        uint256 bidId = auction.submitBid{value: 2 ether}(FLOOR_PRICE + TICK_SPACING, 2 ether, alice, bytes(""));

        assertEq(bidId, 0);
    }

    function test_submitBid_tierThreeOnlyWindow_rejectsTierTwo() public {
        _startAuction();
        _rollAfter(1);
        _mintTierTwo(bob, bobKey);
        vm.deal(bob, 3 ether);
        vm.prank(bob);
        vm.expectRevert();
        auction.submitBid{value: 2 ether}(FLOOR_PRICE + TICK_SPACING, 2 ether, bob, bytes(""));
    }

    function test_submitBid_tierTwoWindow_allowsTierTwo() public {
        _startAuction();
        _rollAfter(uint256(PHASE_ONE_BLOCKS) + 1);
        _mintTierTwo(bob, bobKey);
        vm.deal(bob, 6 ether);
        vm.prank(bob);
        uint256 bidId = auction.submitBid{value: 4 ether}(FLOOR_PRICE + TICK_SPACING, 4 ether, bob, bytes(""));

        assertEq(bidId, 0);
    }

    function test_submitBid_allTiersWindow_allowsTierOne() public {
        _startAuction();
        _rollAfter(uint256(PHASE_ONE_BLOCKS) + uint256(PHASE_TWO_BLOCKS) + 1);
        _mintTierOne(alice, aliceKey);
        vm.deal(alice, 3 ether);
        vm.prank(alice);
        uint256 bidId = auction.submitBid{value: 2 ether}(FLOOR_PRICE + TICK_SPACING, 2 ether, alice, bytes(""));

        assertEq(bidId, 0);
    }

    function test_submitBid_exceedsTierLimit_reverts() public {
        _startAuction();
        _rollAfter(uint256(PHASE_ONE_BLOCKS) + uint256(PHASE_TWO_BLOCKS) + 1);
        _mintTierOne(alice, aliceKey);
        vm.deal(alice, 3 ether);
        vm.prank(alice);
        vm.expectRevert();
        auction.submitBid{value: 3 ether}(FLOOR_PRICE + TICK_SPACING, 3 ether, alice, bytes(""));
    }

    function test_submitBid_ownerMustMatchSender_reverts() public {
        _startAuction();
        _rollAfter(uint256(PHASE_ONE_BLOCKS) + uint256(PHASE_TWO_BLOCKS) + 1);
        _mintTierOne(alice, aliceKey);
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert();
        auction.submitBid{value: 1 ether}(FLOOR_PRICE + TICK_SPACING, 1 ether, alice, bytes(""));
    }

    function test_submitBid_bidIdStartsAtZeroAndIncrements() public {
        _startAuction();
        _rollAfter(uint256(PHASE_ONE_BLOCKS) + uint256(PHASE_TWO_BLOCKS) + 1);
        _mintTierOne(alice, aliceKey);
        _mintTierTwo(bob, bobKey);

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

    function test_tierTokenTransfer_reverts() public {
        _mintTierOne(alice, aliceKey);
        vm.prank(alice);
        vm.expectRevert();
        hook.safeTransferFrom(alice, bob, TIER_ONE_ID, 1, bytes(""));
    }

    function test_mintTier_requiresValidSignature_reverts() public {
        bytes memory signature = _signMint(alice, bobKey, TIER_THREE_ID, SIGNATURE_DEADLINE);
        vm.prank(alice);
        vm.expectRevert();
        hook.mintTierThree(SIGNATURE_DEADLINE, signature);
    }

    function test_mintTier_revertsWhenAlreadyOwned() public {
        _mintTierOne(alice, aliceKey);
        vm.expectRevert();
        _mintTierOne(alice, aliceKey);
    }

    function _mintTierOne(address account, uint256 key) private {
        bytes memory signature = _signMint(account, key, TIER_ONE_ID, SIGNATURE_DEADLINE);
        vm.prank(account);
        hook.mintTierOne(SIGNATURE_DEADLINE, signature);
    }

    function _mintTierTwo(address account, uint256 key) private {
        bytes memory signature = _signMint(account, key, TIER_TWO_ID, SIGNATURE_DEADLINE);
        vm.prank(account);
        hook.mintTierTwo(SIGNATURE_DEADLINE, signature);
    }

    function _mintTierThree(address account, uint256 key) private {
        bytes memory signature = _signMint(account, key, TIER_THREE_ID, SIGNATURE_DEADLINE);
        vm.prank(account);
        hook.mintTierThree(SIGNATURE_DEADLINE, signature);
    }

    function _signMint(address account, uint256 key, uint8 tier, uint64 deadline)
        private
        view
        returns (bytes memory)
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(SIGNING_DOMAIN)),
                keccak256(bytes(SIGNING_VERSION)),
                block.chainid,
                address(hook)
            )
        );
        bytes32 structHash = keccak256(abi.encode(MINT_TYPEHASH, account, tier, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _startAuction() private {
        hook.startAuction(address(auction), PHASE_ONE_BLOCKS, PHASE_TWO_BLOCKS);
    }

    function _rollAfter(uint256 delta) private {
        vm.roll(uint256(hook.auctionStart()) + delta);
    }

    function _mintV4Position(address to) private {
        positionManager.mint(to, nextTokenId);
        nextTokenId += 1;
    }
}
