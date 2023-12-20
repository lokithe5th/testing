// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// For a foundry test we always need to import at least `Test` from the `forge-std` library
// For in contract logging we can also import `console2`
import {Test, console2} from "forge-std/Test.sol";
// We import our contract that will be the target of our testing
import "src/YourContract.sol";
// We need some standard contracts for mock tokens
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "src/mocks/MockToken.sol";

contract YourContractTest is Test {
    // As with a normal smart contract we can declare our global variables here
    // This is our testing target
    YourContract public yourContract;
    // Mock token
    MockToken public mockToken;
    // Some users to make life interesting
    address public bob = address(101);
    address public alice = address(102);
    address public dave = address(103);

    uint256 public constant DEFAULT_STREAM_VALUE = 0.5 ether;

    // Events to test
    event Withdraw(address indexed to, uint256 amount, string reason);
    event AddBuilder(address indexed to, uint256 amount);
    event UpdateBuilder(address indexed to, uint256 amount);

    // Here we are going to set up our contract `YourContract`
    // `setUp()` is run before each test function in our test file.
    function setUp() public {
        // We need to deploy the contract we wan't to interact with
        yourContract = new YourContract();
        // Let's set the local timestamp to 31 days
        vm.warp(31 days);

        mockToken = new MockToken("Mock Token", "MCK", 18);
    }

    // Let's do a simple test first to check that we have deployed our contract correctly
    // In this case there is a public constant we can test
    function test_constants() public {
        assertEqUint(yourContract.FREQUENCY(), 30 days);
    }

    // We do a simple unit test to give Bob a stream
    // We are giving him a cap of DEFAULT_STREAM_VALUE
    // We specifying address(0) to signify this is an ether stream
    function test_addBuilderStream() public {
        // Emits can be tricky in foundry
        vm.expectEmit(true, true, false, true, address(yourContract));
        emit AddBuilder(bob, DEFAULT_STREAM_VALUE);

        yourContract.addBuilderStream(payable(bob), DEFAULT_STREAM_VALUE, address(0));

        // Let's make sure that Bob has been added successfully  
        // We get the newly added data from the struct
        (uint256 cap, , address token) = yourContract.streamedBuilders(bob);
        // We assert that the cap is 0.5 as expected
        assertEq(cap, DEFAULT_STREAM_VALUE);
        // We assert the token address is address(0) as expected
        assertEq(address(0), token);
    }

    // Case: add valid builder + token
    function test_addBuilderStreamToken() public {
        // Emits can be tricky in foundry
        vm.expectEmit(true, true, false, true, address(yourContract));
        emit AddBuilder(bob, DEFAULT_STREAM_VALUE);

        yourContract.addBuilderStream(payable(bob), DEFAULT_STREAM_VALUE, address(mockToken));

        // Let's make sure that Bob has been added successfully  
        // We get the newly added data from the struct
        (uint256 cap, , address token) = yourContract.streamedBuilders(bob);
        // We assert that the cap is 0.5 as expected
        assertEq(cap, DEFAULT_STREAM_VALUE);
        // We assert the token address is address(0) as expected
        assertEq(address(mockToken), token);
    }

    // But we also want to test some negative cases
    // Let's test if someone else tries to add a stream  
    function test_addBuilderStreamNotOwner() public {
        // To impersonate an account we simply use `vm.prank(address account)` which impersonates for 1 contract call
        // or we can use `vm.startPrank(address account)` to impersonate until we wish to stop
        vm.startPrank(alice);
        // To test if a call reverts we use `vm.expectRevert()`, this means the test will fail if
        // the next contract call does not revert with the appropriate reason
        vm.expectRevert("Ownable: caller is not the owner");

        yourContract.addBuilderStream(payable(bob), DEFAULT_STREAM_VALUE, address(0));
    }

    // Case: valid stream cap update
    function test_updateBuilderStreamCap() public {
        test_addBuilderStream();
        
        // We know that Bob has been added in the preceeding function
        // We now try to increase his stream cap
        vm.expectEmit(true, true, false, true, address(yourContract));
        emit UpdateBuilder(bob, 1 ether);
        yourContract.updateBuilderStreamCap(payable(bob), 1 ether);

        // We assert the update went through
        (uint256 cap, ,) = yourContract.streamedBuilders(bob);
        assertEq(cap, 1 ether);
    }

    // Case: check against an unauthorized call to udpate stream cap
    function test_updateBuilderStreamCapNotOwner() public {
        test_addBuilderStream();
        vm.startPrank(alice);
        
        // Only the owner should be able to update a stream
        vm.expectRevert("Ownable: caller is not the owner");
        yourContract.updateBuilderStreamCap(payable(bob), 1 ether);

        // We assert the update didn't go through
        (uint256 cap, ,) = yourContract.streamedBuilders(bob);
        assertEq(cap, DEFAULT_STREAM_VALUE);
    }

    // Case: check against a call to update a non-existant builder
    function test_updateBuilderStreamCapNotBuilder() public {
        // We now expect a revert with a specific custom error
        vm.expectRevert(YourContract.NO_ACTIVE_STREAM.selector);
        yourContract.updateBuilderStreamCap(payable(bob), 1 ether);
    }

    // Case: can add multiple builders
    function test_addBatch() public {
        address[] memory builders = new address[](3);
        uint256[] memory caps = new uint256[](3);
        address[] memory tokens = new address[](3);

        builders[0] = (bob);
        caps[0] = DEFAULT_STREAM_VALUE;
        tokens[0] = address(0);

        builders[1] = (alice);
        caps[1] = DEFAULT_STREAM_VALUE;
        tokens[1] = address(0);

        builders[2] = (dave);
        caps[2] = DEFAULT_STREAM_VALUE;
        tokens[2] = address(0);

        // We expect multiple emits
        vm.expectEmit(true, true, false, true, address(yourContract));
        emit AddBuilder(bob, DEFAULT_STREAM_VALUE);

        vm.expectEmit(true, true, false, true, address(yourContract));
        emit AddBuilder(alice, DEFAULT_STREAM_VALUE);
        
        vm.expectEmit(true, true, false, true, address(yourContract));
        emit AddBuilder(dave, DEFAULT_STREAM_VALUE);

        yourContract.addBatch(builders, caps, tokens);

        // We assert that the batch was added successfully
        (uint256 cap, , address token) = yourContract.streamedBuilders(bob);
        assertEq(cap, DEFAULT_STREAM_VALUE);
        assertEq(token, address(0));

        (cap, , token) = yourContract.streamedBuilders(alice);
        assertEq(cap, DEFAULT_STREAM_VALUE);
        assertEq(token, address(0));

        (cap, , token) = yourContract.streamedBuilders(dave);
        assertEq(cap, DEFAULT_STREAM_VALUE);
        assertEq(token, address(0));
    }

    // Case: check failure due to array lengths
    function test_addBatchInvalidArrayLength() public {
        address[] memory builders = new address[](3);
        uint256[] memory caps = new uint256[](2);
        address[] memory tokens = new address[](3);

        builders[0] = (bob);
        caps[0] = DEFAULT_STREAM_VALUE;
        tokens[0] = address(0);

        builders[1] = (alice);
        caps[1] = DEFAULT_STREAM_VALUE;
        tokens[1] = address(0);

        builders[2] = (dave);
        tokens[2] = address(0);

        // Check that the array length check reverts
        vm.expectRevert(YourContract.INVALID_ARRAY_INPUT.selector);
        yourContract.addBatch(builders, caps, tokens);

        // We assert that the batch was not added successfully
        (uint256 cap, , address token) = yourContract.streamedBuilders(bob);
        assertEq(cap, 0);
        assertEq(token, address(0));

        (cap, , token) = yourContract.streamedBuilders(alice);
        assertEq(cap, 0);
        assertEq(token, address(0));

        (cap, , token) = yourContract.streamedBuilders(dave);
        assertEq(cap, 0);
        assertEq(token, address(0));
    }

    // Case: check the `allBuildersData` return function
    function test_allBuildersData() public {
        // We add some builders
        address[] memory builders = new address[](3);
        uint256[] memory caps = new uint256[](3);
        address[] memory tokens = new address[](3);

        builders[0] = (bob);
        caps[0] = DEFAULT_STREAM_VALUE;
        tokens[0] = address(0);

        builders[1] = (alice);
        caps[1] = DEFAULT_STREAM_VALUE;
        tokens[1] = address(0);

        builders[2] = (dave);
        caps[2] = DEFAULT_STREAM_VALUE;
        tokens[2] = address(0);

        yourContract.addBatch(builders, caps, tokens);

        // We now check the returned data from the target function
        YourContract.BuilderData[] memory returnedData = yourContract.allBuildersData(builders);

        // We assert that the batch was added successfully
        for (uint256 i; i < builders.length; i++) {
            assertEq(returnedData[i].builderAddress, builders[i]);
            assertEq(returnedData[i].cap, caps[i]);
            assertEq(returnedData[i].unlockedAmount, DEFAULT_STREAM_VALUE);
        }
    }

    // Case: check that the contract can receive ETH
    function test_receiveETH() public {
        // We test this by sending one ether to the contract
        (bool success, ) = address(yourContract).call{value: 1 ether}("");
        require(success, "Failed to send");

        // We assert that the contract has this balance
        assertEq(address(yourContract).balance, 1 ether);
    }

    // Case: ETH-based, valid withdrawal
    function test_streamWithdraw() public {
        // First we must add a stream
        test_addBuilderStream();
        // Then we should fund it
        test_receiveETH();

        // Now we need enough time to pass so that the stream is full
        vm.warp(block.timestamp + 31 days);

        // We check that Bob can withdraw DEFAULT_STREAM_VALUE
        assertEq(yourContract.unlockedBuilderAmount(bob), DEFAULT_STREAM_VALUE);

        // We withdraw the ether, impersonating bob
        uint256 bobBalance = bob.balance;

        vm.startPrank(bob);
        
        vm.expectEmit(true, true, true, true, address(yourContract));
        emit Withdraw(bob, DEFAULT_STREAM_VALUE, "Some reason");

        yourContract.streamWithdraw(DEFAULT_STREAM_VALUE, "Some reason");

        // We assert that bob's balance is now DEFAULT_STREAM_VALUE more
        assertEq(bob.balance, bobBalance + DEFAULT_STREAM_VALUE);
    }

    // Case: token-based stream, withdrawal
    function test_streamWithdrawToken() public {
        // First we must add a stream
        test_addBuilderStreamToken();
        // Then we should fund it
        deal(address(mockToken), address(yourContract), 1 ether);

        // Now we need enough time to pass so that the stream is full
        vm.warp(block.timestamp + 31 days);

        // We check that Bob can withdraw DEFAULT_STREAM_VALUE
        assertEq(yourContract.unlockedBuilderAmount(bob), DEFAULT_STREAM_VALUE);

        // We withdraw the token, impersonating bob
        uint256 bobBalance = mockToken.balanceOf(bob);

        vm.startPrank(bob);
        
        vm.expectEmit(true, true, true, true, address(yourContract));
        emit Withdraw(bob, DEFAULT_STREAM_VALUE, "Some reason");

        yourContract.streamWithdraw(DEFAULT_STREAM_VALUE, "Some reason");

        // We assert that bob's balance is now DEFAULT_STREAM_VALUE more
        assertEq(mockToken.balanceOf(bob), bobBalance + DEFAULT_STREAM_VALUE);
    }

    // Case: no eth in contract, valid streams
    function test_streamWithdrawNoETH() public {
        test_addBuilderStream();
        // Now we need enough time to pass so that the stream is full
        vm.warp(block.timestamp + 31 days);

        // We check that Bob can withdraw DEFAULT_STREAM_VALUE
        assertEq(yourContract.unlockedBuilderAmount(bob), DEFAULT_STREAM_VALUE);

        // We expect the withdraw to revert  
        vm.expectRevert(YourContract.NOT_ENOUGH_FUNDS_IN_CONTRACT.selector);
        yourContract.streamWithdraw(DEFAULT_STREAM_VALUE, "None");
    }

    // Case: token-based stream, builders can withdraw tokens
    function test_streamWithdrawNoToken() public {
        test_addBuilderStreamToken();
        // Now we need enough time to pass so that the stream is full
        vm.warp(block.timestamp + 31 days);

        // We check that Bob can withdraw DEFAULT_STREAM_VALUE
        assertEq(yourContract.unlockedBuilderAmount(bob), DEFAULT_STREAM_VALUE);

        // We expect the withdraw to revert  
        vm.expectRevert(YourContract.NOT_ENOUGH_FUNDS_IN_CONTRACT.selector);
        yourContract.streamWithdraw(DEFAULT_STREAM_VALUE, "None");
    }

    // Case: Non-builders have no stream
    function test_streamWithdrawNoBuilder() public {
        test_receiveETH();
        // Now we need enough time to pass so that the stream is full
        vm.warp(block.timestamp + 31 days);

        // We check that Alice cannot withdraw anything
        assertEq(yourContract.unlockedBuilderAmount(alice), 0);

        // We expect the withdraw to revert  
        vm.expectRevert(YourContract.NO_ACTIVE_STREAM.selector);
        yourContract.streamWithdraw(DEFAULT_STREAM_VALUE, "None");
    }

    // Case: ETH-based stream, not enough balance in contract for the amount requested
    function test_streamWithdrawNotEnoughFundsInContractEth() public {
        // We are adding Bob
        test_addBuilderStream();
        (bool success, ) = address(yourContract).call{value: 0.2 ether}("");

        // Now we need enough time to pass so that the stream is full
        vm.warp(block.timestamp + 21 days);

        // We expect the withdraw to revert  
        vm.startPrank(bob);
        vm.expectRevert(YourContract.NOT_ENOUGH_FUNDS_IN_CONTRACT.selector);
        yourContract.streamWithdraw(DEFAULT_STREAM_VALUE, "None");
    }

    // Case: token-based stream, not enough balance in contract for the amount requested
    function test_streamWithdrawNotEnoughFundsInContractToken() public {
        // We are adding Bob
        test_addBuilderStreamToken();
        deal(address(mockToken), address(yourContract), 0.2 ether);

        // Now we need enough time to pass so that the stream is full
        vm.warp(block.timestamp + 21 days);

        // We expect the withdraw to revert  
        vm.startPrank(bob);
        vm.expectRevert(YourContract.NOT_ENOUGH_FUNDS_IN_CONTRACT.selector);
        yourContract.streamWithdraw(DEFAULT_STREAM_VALUE, "None");
    }

    // Case: ETH-based stream, not enough accrued for the amount requested
    function test_streamWithdrawNotEnoughFundsInStreamEth() public {
        // We are adding Bob
        // 16 Nov 2023
        vm.warp(1700123467);
        test_addBuilderStream();
        vm.warp(1700123468);
        (bool success, ) = address(yourContract).call{value: 1 ether}("");

        // Bob makes his first withdrawal. 
        // By the way, the first withdrawal can be made immediately
        // Is this intended?

        vm.prank(bob);
        yourContract.streamWithdraw(DEFAULT_STREAM_VALUE, "None");
        // Now we need time to pass so the stream is not full
        // 30 Nov 2023
        vm.warp(1701333065);

        // We expect the withdraw to revert  
        vm.startPrank(bob);
        vm.expectRevert(YourContract.NOT_ENOUGH_FUNDS_IN_STREAM.selector);
        yourContract.streamWithdraw(DEFAULT_STREAM_VALUE, "None");
        vm.stopPrank();
    }

    // Case: token-based stream, not enough accrued for the amount requested
    function test_streamWithdrawNotEnoughFundsInStreamToken() public {
        // We are adding Bob
        // 16 Nov 2023
        vm.warp(1700123467);
        test_addBuilderStreamToken();
        vm.warp(1700123468);
        deal(address(mockToken), address(yourContract), 1 ether);

        // Bob makes his first withdrawal. 
        // By the way, the first withdrawal can be made immediately
        // Is this intended?

        vm.prank(bob);
        yourContract.streamWithdraw(DEFAULT_STREAM_VALUE, "None");
        // Now we need time to pass so the stream is not full
        // 30 Nov 2023
        vm.warp(1701333065);

        // We expect the withdraw to revert  
        vm.startPrank(bob);
        vm.expectRevert(YourContract.NOT_ENOUGH_FUNDS_IN_STREAM.selector);
        yourContract.streamWithdraw(DEFAULT_STREAM_VALUE, "None");
        vm.stopPrank();
    }

    // Case: builders should accrue streams according to time passed
    function test_unlockedBuilderAmount() public {
        // This adds Bob's stream
        vm.warp(1700123467);
        test_addBuilderStream();
        // We fund and withdraw the first immediate stream
        vm.warp(1700123468);
        (bool success, ) = address(yourContract).call{value: 1 ether}("");

        // Bob makes his first withdrawal. 
        // By the way, the first withdrawal can be made immediately
        // Is this intended? 
        // It turns out: Yes! BuidlGuidl is awesome like that

        vm.prank(bob);
        yourContract.streamWithdraw(DEFAULT_STREAM_VALUE, "None");

        // Now we need some time to pass so the stream is not full
        // 30 Nov 2023
        // We need to check that Bob has accrued the appropriate amount at various timestamps
        // We check in increments of 10 days
        uint256 amountAt0Days = yourContract.unlockedBuilderAmount(bob);
        assertEq(amountAt0Days, DEFAULT_STREAM_VALUE * 0 / 30);

        vm.warp(1700123468 + 10 days);
        uint256 amountAt10Days = yourContract.unlockedBuilderAmount(bob);
        assertEq(amountAt10Days, DEFAULT_STREAM_VALUE * 10 / 30);

        vm.warp(1700123468 + 20 days);
        uint256 amountAt20Days = yourContract.unlockedBuilderAmount(bob);
        assertEq(amountAt20Days, DEFAULT_STREAM_VALUE * 20 / 30);

        vm.warp(1700123468 + 30 days);
        uint256 amountAt30Days = yourContract.unlockedBuilderAmount(bob);
        assertEq(amountAt30Days, DEFAULT_STREAM_VALUE * 30 / 30);

        vm.warp(1700123468 + 50 days);
        uint256 amountAt50Days = yourContract.unlockedBuilderAmount(bob);
        assertEq(amountAt30Days, DEFAULT_STREAM_VALUE * 30 / 30);
    }

    // Case: Non-builders should not have amounts
    function test_unlockedBuilderAmountNonBuilder() public {
        // This adds Bob's stream
        vm.warp(1700123467);
        test_addBuilderStream();
        // We fund and withdraw the first immediate stream
        vm.warp(1700183468);
        (bool success, ) = address(yourContract).call{value: 1 ether}("");

        // We check that a non-builder cannot acrue a stream
        // It should always return 0
        assertEq(yourContract.unlockedBuilderAmount(alice), 0);
    }

    // Case: ETH-based stream, transfer to builder fails
    function test_withdrawStreamEthNonReceiver() public {
        // First we must add a stream
        yourContract.addBuilderStream(payable(address(mockToken)), DEFAULT_STREAM_VALUE, address(0));
        // Then we should fund it
        (bool success, ) = payable(address(yourContract)).call{value: 1 ether}("");

        // Now we need enough time to pass so that the stream is full
        vm.warp(block.timestamp + 31 days);

        vm.startPrank(address(mockToken));

        vm.expectRevert(YourContract.TRANSFER_FAILED.selector);
        yourContract.streamWithdraw(DEFAULT_STREAM_VALUE, "Some reason");

        // We assert that 
        assertEq(address(mockToken).balance, 0);
    }

    // Case: token-based stream, `transfer` to builder fails
    function test_withdrawStreamTokenNonReceiver() public {
        // First we must add a stream
        test_addBuilderStreamToken();
        // Then we should fund it
        deal(address(mockToken), address(yourContract), 1 ether);

        // Now we need enough time to pass so that the stream is full
        vm.warp(block.timestamp + 31 days);

        // We check that Bob can withdraw DEFAULT_STREAM_VALUE
        assertEq(yourContract.unlockedBuilderAmount(bob), DEFAULT_STREAM_VALUE);

        // We withdraw the token, impersonating bob
        uint256 bobBalance = mockToken.balanceOf(bob);
        mockToken.setBlacklist(bob, true);

        vm.startPrank(bob);
        
        vm.expectRevert(YourContract.TRANSFER_FAILED.selector);
        yourContract.streamWithdraw(DEFAULT_STREAM_VALUE, "Some reason");

        // We assert that bob's balance is still 0
        assertEq(mockToken.balanceOf(bob), 0);
    }

}