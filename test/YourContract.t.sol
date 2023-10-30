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
    // We are giving him a cap of 0.5 ether
    // We specifying address(0) to signify this is an ether stream
    function test_addBuilderStream() public {
        // Emits can be tricky in foundry
        vm.expectEmit(true, true, false, true, address(yourContract));
        emit AddBuilder(bob, 0.5 ether);

        yourContract.addBuilderStream(payable(bob), 0.5 ether, address(0));

        // Let's make sure that Bob has been added successfully  
        // We get the newly added data from the struct
        (uint256 cap, , address token) = yourContract.streamedBuilders(bob);
        // We assert that the cap is 0.5 as expected
        assertEq(cap, 0.5 ether);
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

        yourContract.addBuilderStream(payable(bob), 0.5 ether, address(0));
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
        assertEq(cap, 0.5 ether);
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
        caps[0] = 0.5 ether;
        tokens[0] = address(0);

        builders[1] = (alice);
        caps[1] = 0.5 ether;
        tokens[1] = address(0);

        builders[2] = (dave);
        caps[2] = 0.5 ether;
        tokens[2] = address(0);

        // We expect multiple emits
        vm.expectEmit(true, true, false, true, address(yourContract));
        emit AddBuilder(bob, 0.5 ether);

        vm.expectEmit(true, true, false, true, address(yourContract));
        emit AddBuilder(alice, 0.5 ether);
        
        vm.expectEmit(true, true, false, true, address(yourContract));
        emit AddBuilder(dave, 0.5 ether);

        yourContract.addBatch(builders, caps, tokens);

        // We assert that the batch was added successfully
        (uint256 cap, , address token) = yourContract.streamedBuilders(bob);
        assertEq(cap, 0.5 ether);
        assertEq(token, address(0));

        (cap, , token) = yourContract.streamedBuilders(alice);
        assertEq(cap, 0.5 ether);
        assertEq(token, address(0));

        (cap, , token) = yourContract.streamedBuilders(dave);
        assertEq(cap, 0.5 ether);
        assertEq(token, address(0));
    }

    // Check failure due to array lengths
    function test_addBatchInvalidArrayLength() public {
        address[] memory builders = new address[](3);
        uint256[] memory caps = new uint256[](2);
        address[] memory tokens = new address[](3);

        builders[0] = (bob);
        caps[0] = 0.5 ether;
        tokens[0] = address(0);

        builders[1] = (alice);
        caps[1] = 0.5 ether;
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

}
