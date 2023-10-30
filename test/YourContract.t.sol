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
    event AddBuilder(address indexed to, uint256 amount); 

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

}
