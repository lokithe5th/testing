# Testing in Foundry  

## Intro  

Testing your smart contracts is extremely important. But doing thorough testing is hard. As a competitor in contests on Code4rena I've been lucky enough to be exposed to many different testing methodologies. And while security reviews are fun, practicing the techniques I've been exposed to is the only way to level up my testing skills as a dev.  

If you're new to smart contracts, join me as I start from scratch and implement tests for some BuidlGuidl contracts. We'll be moving from basic unit tests, to fuzz tests in Foundry, up to fuzzing with Echidna and invariant testing.  

The setup is short and simple. We'll be taking this [contract](https://github.com/BuidlGuidl/hacker-houses-streams/blob/token-streams/packages/hardhat/contracts/YourContract.sol). This is the updated contract that the BuidlGuidl can use to stream ETH or tokens to users.  

> You will need to install Foundry, if you haven't yet. You can find the page [here](https://book.getfoundry.sh/getting-started/installation)

## First steps 
The quickest way to learn is by doing. Let's get started. 

The way I usually start is by creating a new Foundry project. If you want to follow along, you can create a new Foundry project with `forge init`. This will initialize a clean project.

Plan: The plan for today is to write a simple unit test for each of the functions in this contract.

We'll start by setting up the skeleton for unit tests of our simple test contract. But first, we should ensure that the imports used by the BuidlGuidl contract are present. From the `YourContract.sol` file we see that it requires the OpenZeppelin contracts. 

```
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
```

Because we are placing the file in a new directory, we will need to make sure these dependencies are installed. In forge we can add dependencies with `forge install <dependency-github>`.  

> Make sure you `forge install openzeppelin/openzeppelin-contracts@v4.8.1` as the newest versions

## Test file

Create your test file. The naming convention is usually:
`<contract_name>.t.sol`

And this file should be located in the `test` directory of the foundry project.  

Here is the first part of the test file `YourContract.t.sol`, after we have done the initial setup. Don't worry, we'll explain as we work through the code. 

```
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// For a foundry test we always need to import at least `Test` from the `forge-std` library
// For in contract logging we can also import `console2`
import {Test, console2} from "forge-std/Test.sol";
// We import our contract that will be the target of our testing
import "src/YourContract.sol";

contract YourContractTest is Test {
    // As with a normal smart contract we can declare our global variables here
    YourContract public yourContract;

    // Here we are going to set up our contract `YourContract`
    // `setUp()` is run before each test function in our test file.
    function setUp() public {
        // We need to deploy the contract we wan't to interact with
        yourContract = new YourContract();
    }

    // Let's do a simple test first to check that we have deployed our contract correctly
    // In this case there is a public constant we can test
    function test_Constants() public {
        assertEqUint(yourContract.FREQUENCY(), 30 days);
    }

}
```

Just like a typical Solidity smart contract we have a `pragma` statement, imports and the contract name.  

There is a special function called `setUp()`. This function will be called before each separate test instance is run. This is where we make sure our contract `YourContract.sol` is deployed and set up correctly.  

Writing a test on this contract is super simple: we define a function that starts with the key word `test`. There are a few different conventions. Some devs name the tests `testConstants()`, others would use `test_constants()`. In other words, the convention is usually `test<targetFunctionName>`. This makes sure it is always clear what function you are testing.  

Next step: adding a test for `addBuilderStream()`

```
    // We do a simple unit test to give Bob a stream
    // We are giving him a cap of 0.5 ether
    // We specifying address(0) to signify this is an ether stream
    function test_addBuilderStream() public {
        yourContract.addBuilderStream(payable(bob), 0.5 ether, address(0));
    }
```

We run this test with `forge test` and... BOOM! An error. But what did we do wrong? Our clues will be in the logs: 

```
Running 2 tests for test/YourContract.t.sol:YourContractTest
[FAIL. Reason: Arithmetic over/underflow] test_addBuilderStream() (gas: 10165)
[PASS] test_constants() (gas: 5470)
Test result: FAILED. 1 passed; 1 failed; 0 skipped; finished in 428.99µs
 
Ran 1 test suites: 1 tests passed, 1 failed, 0 skipped (2 total tests)

Failing tests:
Encountered 1 failing test in test/YourContract.t.sol:YourContractTest
[FAIL. Reason: Arithmetic over/underflow] test_addBuilderStream() (gas: 10165)

Encountered a total of 1 failing tests, 1 tests succeeded
```  

The console output clearly shows us that our new test `test_addBuilderStream()` has failed due to `Arithmetic over/undeflow`. 

That's unexpected! Or is it? Remember that tests are likely to point out flaws in your code that you didn't even consider. At the least it deepens your understanding of the code.  

Looking at the `addBuilderStream` code:  
```
    function addBuilderStream(address payable _builder, uint256 _cap, address _optionalTokenAddress) public onlyOwner {
        streamedBuilders[_builder] = BuilderStreamInfo(_cap, block.timestamp - FREQUENCY, _optionalTokenAddress);
        emit AddBuilder(_builder, _cap);
    }
```

Can you spot the issue? Remember that foundry is spinning up a local chain for us to test with. This is your own little EVM, and it only contains what you put on it. Also, it starts at the moment you run your test. See the issue now? The statement `block.timestamp - FREQUENCY` must overflow if our chain timestamp is less than 30 days old. How do we fix this? We add a line to the setup file to have some time pass before we deploy.  

```
    function setUp() public {
        // We need to deploy the contract we wan't to interact with
        yourContract = new YourContract();
        // Let's set the local timestamp to 31 days
        vm.warp(31 days);
    }
```

And now our tests pass:  
```
Running 2 tests for test/YourContract.t.sol:YourContractTest
[PASS] test_addBuilderStream() (gas: 58256)
[PASS] test_constants() (gas: 5470)
Test result: ok. 2 passed; 0 failed; 0 skipped; finished in 447.81µs
```

Getting an error that's tricky to resolve, or just curious to see what's going on under the hood? Run your tests with increased verbosity: `forge test -vvvv`:  
```
Ran 1 test suites: 2 tests passed, 0 failed, 0 skipped (2 total tests)
┌─[lourens@parrot]─[~/Projects/testing]
└──╼ $forge test -vvvv
[⠢] Compiling...
[⠊] Compiling 1 files with 0.8.21
[⠒] Solc 0.8.21 finished in 689.38ms
Compiler run successful!

Running 2 tests for test/YourContract.t.sol:YourContractTest
[PASS] test_addBuilderStream() (gas: 58256)
Traces:
  [58256] YourContractTest::test_addBuilderStream() 
    ├─ [50894] YourContract::addBuilderStream(0x0000000000000000000000000000000000000065, 500000000000000000 [5e17], 0x0000000000000000000000000000000000000000) 
    │   ├─ emit AddBuilder(to: 0x0000000000000000000000000000000000000065, amount: 500000000000000000 [5e17])
    │   └─ ← ()
    └─ ← ()

[PASS] test_constants() (gas: 5470)
Traces:
  [5470] YourContractTest::test_constants() 
    ├─ [239] YourContract::FREQUENCY() [staticcall]
    │   └─ ← 2592000 [2.592e6]
    └─ ← ()

Test result: ok. 2 passed; 0 failed; 0 skipped; finished in 461.90µs
```

Inspecting the tests in this way is an awesome way to track function calls if you are doing a contest.  

You might have noticed that my `test_addBuilderStream` function is a bit light. Yes, we call the intended function on the contract, but we don't validate that everything's been emitted and set appropriately. Let's do that now:
```
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
```

*Please note: Emits in Foundry can be [tricky](https://book.getfoundry.sh/cheatcodes/expect-emit).*  

Now we want to test a negative case. What happens if the function is called by an account that is not the owner? We expect it to revert. Let's add this test: 

``` // But we also want to test some negative cases
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
```  

We now have the basics, so I'm going to go ahead and complete the rest of the unit tests for you. These are all in the repo.  

```
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
```

## Summary  

The repo now contains all necessary unit tests for the ETH streaming functionality.  

Crucially, we haven't even touched token streams or fuzzing yet! If you're interested, check back out the branch Part-2, to see how we set up a mock token to test with, and take our first baby steps with Foundry's fuzzer.