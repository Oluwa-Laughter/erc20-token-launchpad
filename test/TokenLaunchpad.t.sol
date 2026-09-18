// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TokenLaunchpad} from "../src/TokenLaunchpad.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract TokenLaunchpadTest is Test {
    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    TokenLaunchpad launchpad;
    MockERC20 token;

    address creator = makeAddr("creator");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address attacker = makeAddr("attacker");
    address feeRecipient = makeAddr("feeRecipient");

    uint256 constant PLATFORM_FEE_BPS = 200; // 2%

    uint256 constant PRICE = 0.001 ether;

    uint256 constant ALLOCATION = 100_000 ether;

    uint256 constant HARD_CAP = 50 ether;

    uint256 constant WALLET_LIMIT = 5 ether;

    uint256 startTime;
    uint256 endTime;

    uint256 saleId;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        /*
         * Creator deploys the Launchpad.
         *
         * Therefore:
         *
         * owner == creator
         */

        vm.prank(creator);

        launchpad = new TokenLaunchpad(feeRecipient, PLATFORM_FEE_BPS);

        token = new MockERC20();

        /*
         * Give creator the sale allocation.
         */

        token.mint(creator, ALLOCATION);

        /*
         * Give buyers ETH.
         */

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(attacker, 100 ether);

        startTime = block.timestamp + 1 days;

        endTime = startTime + 7 days;

        /*
         * Creator approves Launchpad and
         * creates the sale.
         */

        vm.startPrank(creator);

        token.approve(address(launchpad), ALLOCATION);

        saleId = launchpad.createSale(address(token), PRICE, ALLOCATION, startTime, endTime, HARD_CAP, WALLET_LIMIT);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function testDeployerIsOwner() public view {
        assertEq(launchpad.owner(), creator);
    }

    function testNonOwnerCannotCreateSale() public {
        token.mint(attacker, ALLOCATION);

        vm.startPrank(attacker);

        token.approve(address(launchpad), ALLOCATION);

        vm.expectRevert(TokenLaunchpad.NotOwner.selector);

        launchpad.createSale(
            address(token),
            PRICE,
            ALLOCATION,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            HARD_CAP,
            WALLET_LIMIT
        );

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           CREATE SALE
    //////////////////////////////////////////////////////////////*/

    function testCreateSale() public view {
        assertEq(launchpad.nextSaleId(), 1);

        assertEq(token.balanceOf(address(launchpad)), ALLOCATION);

        assertEq(token.balanceOf(creator), 0);
    }

    function testCreateSaleStoresCorrectData() public view {
        TokenLaunchpad.Sale memory sale = launchpad.getSale(saleId);

        assertEq(sale.creator, creator);

        assertEq(address(sale.token), address(token));

        assertEq(sale.price, PRICE);

        assertEq(sale.allocation, ALLOCATION);

        assertEq(sale.startTime, startTime);

        assertEq(sale.endTime, endTime);

        assertEq(sale.hardCap, HARD_CAP);

        assertEq(sale.walletLimit, WALLET_LIMIT);

        assertEq(sale.totalRaised, 0);

        assertEq(sale.totalTokensSold, 0);

        assertFalse(sale.proceedsWithdrawn);

        assertFalse(sale.unsoldRecovered);
    }

    /*//////////////////////////////////////////////////////////////
                     INVALID SALE CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    function testCreateSaleRevertsForZeroToken() public {
        vm.prank(creator);

        vm.expectRevert(TokenLaunchpad.ZeroAddress.selector);

        launchpad.createSale(address(0), PRICE, ALLOCATION, startTime, endTime, HARD_CAP, WALLET_LIMIT);
    }

    function testCreateSaleRevertsForZeroPrice() public {
        vm.prank(creator);

        vm.expectRevert(TokenLaunchpad.InvalidPrice.selector);

        launchpad.createSale(address(token), 0, ALLOCATION, startTime, endTime, HARD_CAP, WALLET_LIMIT);
    }

    function testCreateSaleRevertsForZeroAllocation() public {
        vm.prank(creator);

        vm.expectRevert(TokenLaunchpad.InvalidAllocation.selector);

        launchpad.createSale(address(token), PRICE, 0, startTime, endTime, HARD_CAP, WALLET_LIMIT);
    }

    function testCreateSaleRevertsForInvalidTime() public {
        vm.prank(creator);

        vm.expectRevert(TokenLaunchpad.InvalidTime.selector);

        launchpad.createSale(address(token), PRICE, ALLOCATION, block.timestamp, endTime, HARD_CAP, WALLET_LIMIT);
    }

    function testCreateSaleRevertsWhenEndBeforeStart() public {
        uint256 newStart = block.timestamp + 5 days;

        uint256 newEnd = block.timestamp + 4 days;

        vm.prank(creator);

        vm.expectRevert(TokenLaunchpad.InvalidTime.selector);

        launchpad.createSale(address(token), PRICE, ALLOCATION, newStart, newEnd, HARD_CAP, WALLET_LIMIT);
    }

    function testCreateSaleRevertsForZeroHardCap() public {
        vm.prank(creator);

        vm.expectRevert(TokenLaunchpad.InvalidHardCap.selector);

        launchpad.createSale(address(token), PRICE, ALLOCATION, startTime, endTime, 0, WALLET_LIMIT);
    }

    function testCreateSaleRevertsForZeroWalletLimit() public {
        vm.prank(creator);

        vm.expectRevert(TokenLaunchpad.InvalidWalletLimit.selector);

        launchpad.createSale(address(token), PRICE, ALLOCATION, startTime, endTime, HARD_CAP, 0);
    }

    function testCreateSaleRevertsWhenWalletLimitExceedsHardCap() public {
        vm.prank(creator);

        vm.expectRevert(TokenLaunchpad.InvalidWalletLimit.selector);

        launchpad.createSale(address(token), PRICE, ALLOCATION, startTime, endTime, HARD_CAP, HARD_CAP + 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                           SALE WINDOWS
    //////////////////////////////////////////////////////////////*/

    function testCannotBuyBeforeStart() public {
        vm.prank(alice);

        vm.expectRevert(TokenLaunchpad.SaleNotStarted.selector);

        launchpad.buy{value: 1 ether}(saleId);
    }

    function testCanBuyExactlyAtStart() public {
        vm.warp(startTime);

        vm.prank(alice);

        launchpad.buy{value: 1 ether}(saleId);

        assertEq(launchpad.contributions(saleId, alice), 1 ether);
    }

    function testCanBuyBeforeEnd() public {
        vm.warp(endTime - 1);

        vm.prank(alice);

        launchpad.buy{value: 1 ether}(saleId);

        assertEq(launchpad.contributions(saleId, alice), 1 ether);
    }

    function testCannotBuyExactlyAtEnd() public {
        vm.warp(endTime);

        vm.prank(alice);

        vm.expectRevert(TokenLaunchpad.SaleEnded.selector);

        launchpad.buy{value: 1 ether}(saleId);
    }

    /*//////////////////////////////////////////////////////////////
                                BUY
    //////////////////////////////////////////////////////////////*/

    function testBuyTokens() public {
        vm.warp(startTime);

        vm.prank(alice);

        launchpad.buy{value: 1 ether}(saleId);

        /*
         * price = 0.001 ETH/token
         *
         * 1 ETH = 1000 tokens
         */

        assertEq(launchpad.purchasedTokens(saleId, alice), 1_000 ether);

        assertEq(launchpad.contributions(saleId, alice), 1 ether);
    }

    function testZeroPaymentReverts() public {
        vm.warp(startTime);

        vm.prank(alice);

        vm.expectRevert(TokenLaunchpad.ZeroPayment.selector);

        launchpad.buy{value: 0}(saleId);
    }

    function testMultipleBuyers() public {
        vm.warp(startTime);

        vm.prank(alice);

        launchpad.buy{value: 1 ether}(saleId);

        vm.prank(bob);

        launchpad.buy{value: 2 ether}(saleId);

        assertEq(launchpad.contributions(saleId, alice), 1 ether);

        assertEq(launchpad.contributions(saleId, bob), 2 ether);

        assertEq(launchpad.purchasedTokens(saleId, alice), 1_000 ether);

        assertEq(launchpad.purchasedTokens(saleId, bob), 2_000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                           WALLET LIMIT
    //////////////////////////////////////////////////////////////*/

    function testCanReachExactWalletLimit() public {
        vm.warp(startTime);

        vm.prank(alice);

        launchpad.buy{value: WALLET_LIMIT}(saleId);

        assertEq(launchpad.contributions(saleId, alice), WALLET_LIMIT);
    }

    function testWalletLimitAcrossMultiplePurchases() public {
        vm.warp(startTime);

        vm.startPrank(alice);

        launchpad.buy{value: 3 ether}(saleId);

        launchpad.buy{value: 2 ether}(saleId);

        assertEq(launchpad.contributions(saleId, alice), 5 ether);

        vm.expectRevert(TokenLaunchpad.WalletLimitExceeded.selector);

        launchpad.buy{value: PRICE}(saleId);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              HARD CAP
    //////////////////////////////////////////////////////////////*/

    function testCanReachExactHardCap() public {
        vm.warp(startTime);

        /*
         * 10 wallets × 5 ETH
         * = exact 50 ETH hard cap.
         */

        for (uint256 i = 0; i < 10; i++) {
            address buyer = makeAddr(string.concat("buyer", vm.toString(i)));

            vm.deal(buyer, 5 ether);

            vm.prank(buyer);

            launchpad.buy{value: 5 ether}(saleId);
        }

        TokenLaunchpad.Sale memory sale = launchpad.getSale(saleId);

        assertEq(sale.totalRaised, HARD_CAP);
    }

    function testCannotExceedHardCap() public {
        vm.warp(startTime);

        for (uint256 i = 0; i < 10; i++) {
            address buyer = makeAddr(string.concat("buyer", vm.toString(i)));

            vm.deal(buyer, 5 ether);

            vm.prank(buyer);

            launchpad.buy{value: 5 ether}(saleId);
        }

        address extraBuyer = makeAddr("extraBuyer");

        vm.deal(extraBuyer, 1 ether);

        vm.prank(extraBuyer);

        vm.expectRevert(TokenLaunchpad.HardCapExceeded.selector);

        launchpad.buy{value: PRICE}(saleId);
    }

    /*//////////////////////////////////////////////////////////////
                              CLAIMING
    //////////////////////////////////////////////////////////////*/

    function testCannotClaimBeforeSaleEnds() public {
        vm.warp(startTime);

        vm.prank(alice);

        launchpad.buy{value: 1 ether}(saleId);

        vm.prank(alice);

        vm.expectRevert(TokenLaunchpad.SaleNotEnded.selector);

        launchpad.claim(saleId);
    }

    function testBuyerCanClaimExactlyAtEnd() public {
        vm.warp(startTime);

        vm.prank(alice);

        launchpad.buy{value: 1 ether}(saleId);

        vm.warp(endTime);

        vm.prank(alice);

        launchpad.claim(saleId);

        assertEq(token.balanceOf(alice), 1_000 ether);

        assertTrue(launchpad.hasClaimed(saleId, alice));
    }

    function testCannotClaimWithoutPurchase() public {
        vm.warp(endTime);

        vm.prank(alice);

        vm.expectRevert(TokenLaunchpad.NothingToClaim.selector);

        launchpad.claim(saleId);
    }

    function testCannotClaimTwice() public {
        vm.warp(startTime);

        vm.prank(alice);

        launchpad.buy{value: 1 ether}(saleId);

        vm.warp(endTime);

        vm.startPrank(alice);

        launchpad.claim(saleId);

        vm.expectRevert(TokenLaunchpad.AlreadyClaimed.selector);

        launchpad.claim(saleId);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        WITHDRAWAL ACCESS
    //////////////////////////////////////////////////////////////*/

    function testNonOwnerCannotWithdraw() public {
        vm.warp(endTime);

        vm.prank(attacker);

        vm.expectRevert(TokenLaunchpad.NotOwner.selector);

        launchpad.withdrawProceeds(saleId);
    }

    function testOwnerCannotWithdrawBeforeEnd() public {
        vm.warp(startTime);

        vm.prank(alice);

        launchpad.buy{value: 1 ether}(saleId);

        vm.prank(creator);

        vm.expectRevert(TokenLaunchpad.SaleNotEnded.selector);

        launchpad.withdrawProceeds(saleId);
    }

    /*//////////////////////////////////////////////////////////////
                       PROCEEDS + PLATFORM FEE
    //////////////////////////////////////////////////////////////*/

    function testOwnerWithdrawsProceeds() public {
        vm.warp(startTime);

        vm.prank(alice);

        launchpad.buy{value: 5 ether}(saleId);

        vm.warp(endTime);

        uint256 creatorBefore = creator.balance;

        uint256 feeRecipientBefore = feeRecipient.balance;

        vm.prank(creator);

        launchpad.withdrawProceeds(saleId);

        /*
         * 2% of 5 ETH = 0.1 ETH
         *
         * Creator:
         * 5 - 0.1 = 4.9 ETH
         */

        assertEq(creator.balance - creatorBefore, 4.9 ether);

        assertEq(feeRecipient.balance - feeRecipientBefore, 0.1 ether);

        assertEq(address(launchpad).balance, 0);
    }

    function testCannotWithdrawTwice() public {
        vm.warp(startTime);

        vm.prank(alice);

        launchpad.buy{value: 1 ether}(saleId);

        vm.warp(endTime);

        vm.startPrank(creator);

        launchpad.withdrawProceeds(saleId);

        vm.expectRevert(TokenLaunchpad.AlreadyWithdrawn.selector);

        launchpad.withdrawProceeds(saleId);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                       UNSOLD TOKEN RECOVERY
    //////////////////////////////////////////////////////////////*/

    function testNonOwnerCannotRecoverUnsoldTokens() public {
        vm.warp(endTime);

        vm.prank(attacker);

        vm.expectRevert(TokenLaunchpad.NotOwner.selector);

        launchpad.recoverUnsoldTokens(saleId);
    }

    function testOwnerCannotRecoverBeforeEnd() public {
        vm.prank(creator);

        vm.expectRevert(TokenLaunchpad.SaleNotEnded.selector);

        launchpad.recoverUnsoldTokens(saleId);
    }

    function testRecoverUnsoldTokens() public {
        vm.warp(startTime);

        vm.prank(alice);

        launchpad.buy{value: 1 ether}(saleId);

        uint256 sold = 1_000 ether;

        vm.warp(endTime);

        vm.prank(creator);

        launchpad.recoverUnsoldTokens(saleId);

        /*
         * Owner gets only unsold tokens.
         */

        assertEq(token.balanceOf(creator), ALLOCATION - sold);

        /*
         * Purchased tokens stay inside
         * Launchpad for Alice.
         */

        assertEq(token.balanceOf(address(launchpad)), sold);

        /*
         * Alice can still claim.
         */

        vm.prank(alice);

        launchpad.claim(saleId);

        assertEq(token.balanceOf(alice), sold);

        assertEq(token.balanceOf(address(launchpad)), 0);
    }

    function testCannotRecoverUnsoldTokensTwice() public {
        vm.warp(endTime);

        vm.startPrank(creator);

        launchpad.recoverUnsoldTokens(saleId);

        vm.expectRevert(TokenLaunchpad.AlreadyRecovered.selector);

        launchpad.recoverUnsoldTokens(saleId);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         INVALID SALE ID
    //////////////////////////////////////////////////////////////*/

    function testInvalidSaleIdReverts() public {
        uint256 invalidSaleId = 100;

        vm.warp(startTime);

        vm.prank(alice);

        vm.expectRevert(TokenLaunchpad.SaleDoesNotExist.selector);

        launchpad.buy{value: 1 ether}(invalidSaleId);
    }

    /*//////////////////////////////////////////////////////////////
                              FUZZING
    //////////////////////////////////////////////////////////////*/

    function testFuzzBuyWithinWalletLimit(uint256 numberOfTokens) public {
        vm.warp(startTime);

        /*
         * Since:
         *
         * PRICE = 0.001 ETH
         * WALLET_LIMIT = 5 ETH
         *
         * maximum whole tokens purchasable
         * by one wallet = 5000.
         */

        numberOfTokens = bound(numberOfTokens, 1, WALLET_LIMIT / PRICE);

        uint256 payment = numberOfTokens * PRICE;

        vm.prank(alice);

        launchpad.buy{value: payment}(saleId);

        assertEq(launchpad.contributions(saleId, alice), payment);

        assertEq(launchpad.purchasedTokens(saleId, alice), numberOfTokens * 1e18);

        assertLe(launchpad.contributions(saleId, alice), WALLET_LIMIT);
    }

    function testIncorrectPaymentReverts() public {
        vm.warp(startTime);

        uint256 incorrectPayment = PRICE + (PRICE / 2);

        vm.prank(alice);

        vm.expectRevert(TokenLaunchpad.IncorrectPayment.selector);

        launchpad.buy{value: incorrectPayment}(saleId);
    }

    function testCanBuyOneWholeToken() public {
        vm.warp(startTime);

        vm.prank(alice);

        launchpad.buy{value: PRICE}(saleId);

        assertEq(launchpad.contributions(saleId, alice), PRICE);

        assertEq(launchpad.purchasedTokens(saleId, alice), 1 ether);
    }

    function testCannotExceedTokenAllocation() public {
        uint256 smallAllocation = 2 ether;

        uint256 newStart = block.timestamp + 1 days;

        uint256 newEnd = newStart + 1 days;

        /*
         * Give creator another 2 tokens.
         */

        token.mint(creator, smallAllocation);

        vm.startPrank(creator);

        token.approve(address(launchpad), smallAllocation);

        uint256 smallSaleId =
            launchpad.createSale(address(token), PRICE, smallAllocation, newStart, newEnd, 10 ether, 10 ether);

        vm.stopPrank();

        vm.warp(newStart);

        /*
         * Alice buys the entire allocation:
         * 2 tokens.
         */

        vm.prank(alice);

        launchpad.buy{value: 2 * PRICE}(smallSaleId);

        /*
         * Bob attempts to buy another token.
         */

        vm.prank(bob);

        vm.expectRevert(TokenLaunchpad.AllocationExceeded.selector);

        launchpad.buy{value: PRICE}(smallSaleId);
    }
}
