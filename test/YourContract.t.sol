// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// For a foundry test we always need to import at least `Test` from the `forge-std` library
// For in contract logging we can also import `console2`
import {Test, console2} from "forge-std/Test.sol";
// We import our contract that will be the target of our testing
import "src/YourContract.sol";

contract YourContractTest is Test {
    // As with a normal smart contract we can declare our global variables here
    // This is our testing target
    YourContract public yourContract;
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

    // We check against an unauthorized call
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

    // Check against a call to update a non-existant builder
    function test_updateBuilderStreamCapNotBuilder() public {
        // We now expect a revert with a specific custom error
        vm.expectRevert(YourContract.NO_ACTIVE_STREAM.selector);
        yourContract.updateBuilderStreamCap(payable(bob), 1 ether);
    }

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

    // Check failure due to array lengths
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

    // Check that the contract can receive ETH
    function test_receiveETH() public {
        // We test this by sending one ether to the contract
        (bool success, ) = address(yourContract).call{value: 1 ether}("");
        require(success, "Failed to send");

        // We assert that the contract has this balance
        assertEq(address(yourContract).balance, 1 ether);
    }

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

    function test_streamWithdrawNotEnoughFundsInStream() public {
        test_addBuilderStream();
        test_receiveETH();
        // Now we need enough time to pass so that the stream is full
        vm.warp(block.timestamp + 21 days);

        // We expect the withdraw to revert  
        vm.expectRevert(YourContract.NOT_ENOUGH_FUNDS_IN_STREAM.selector);
        yourContract.streamWithdraw(DEFAULT_STREAM_VALUE, "None");
    }

}
