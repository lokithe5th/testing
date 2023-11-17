# Testing in Foundry  

## Introduction  

We are continuing with creating the tests for the BuidlGuidl Token streams contract. 

The focus today is completing all the ETH related unit tests and then tacking the token related tests as well.

## Start-stop  

Within the first few minutes we run into an interesting issue. All code has bugs and test code is no exception.


We are trying to create a unit test that triggers the `NOT_ENOUGH_FUNDS_IN_STREAM` error when calling `streamWithdraw`: 
```
        uint256 totalAmountCanWithdraw = unlockedBuilderAmount(msg.sender);
        if(totalAmountCanWithdraw < _amount) revert NOT_ENOUGH_FUNDS_IN_STREAM();

```

Using this test as a base:  

```
    function test_streamWithdrawNotEnoughFundsInContract() public {
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
```

We run into an issue immediately. Bob can, despite only a part of the time running out, withdraw all his ETH. 

There are two possibilities for this: either the test is wrong, or there is an issue in the contract itself. Let's find out which it is!

### Step 1: Hypothesis  

As the most complex part of the code is the stream accrual as time passes, the issue may be linked to that.

Hypothesis (call it H0): the stream accrual calculation is wrong.
Alternative hypothesis (call it H1): there is another underlying cause.

### Step 2: Test our H0
We can test this by logging the stream accrual calculation performed by `yourContract.unlockedBuilderAmount()` and setting the time via `vm.warp`.

We are focusing on this problem test, which we can run with: `forge test --match-test test_streamWithdrawNotWnoughFundsInStream -vvv`

The test looks like this:  
```
    function test_streamWithdrawNotEnoughFundsInStream() public {
        // We are adding Bob
        // 16 Nov 2023
        vm.warp(1700123467);
        test_addBuilderStream();
        (bool success, ) = address(yourContract).call{value: 0.7 ether}("");
        console2.log("Bob's unlocked stream ", yourContract.unlockedBuilderAmount(bob));
        // Now we need time to pass so the stream is not full
        // 30 Nov 2023
        vm.warp(1701333065);
        console2.log("Bob's unlocked stream ", yourContract.unlockedBuilderAmount(bob));
        // We expect the withdraw to revert  
        vm.startPrank(bob);
        //vm.expectRevert(YourContract.NOT_ENOUGH_FUNDS_IN_STREAM.selector);
        yourContract.streamWithdraw(DEFAULT_STREAM_VALUE, "None");
        vm.stopPrank();
        console2.log("Bob's balance ", bob.balance);
    }
```

And our output is this: 
```
Running 1 test for test/YourContract.t.sol:YourContractTest
[PASS] test_streamWithdrawNotEnoughFundsInStream() (gas: 119486)
Logs:
  Bob's unlocked stream  500000000000000000
  Bob's unlocked stream  500000000000000000
  Bob's balance  500000000000000000

Test result: ok. 1 passed; 0 failed; 0 skipped; finished in 1.16ms
```

### Step 3: Interpretation

What this tells us is that according to the logic in the contract, Bob had 0.5 ether available immediately after his stream was opened. 

> This may signal a bug in the contract. We should ascertain from the devs if the entire stream is supposed to be withdrawable immediately after the first funding.

After reaching out to Austin, he points us in the direction of his [tweets earlier this year](https://x.com/austingriffith/status/1674444986463719424?s=46&t=3J-S7_iZrqdWSB0sUNFYRA). This confirms that it is expected behaviour.

### Step 4: Conclusion  
We accept our alternative hypothesis, meaning that the stream accrual logic is not faulty, but that the underlying cause was something else. 

In this case, the issue was our assumption that the stream should not be withdrawable immediately after opening. This was incorrect! As Austin helpfully noted that builders are trusted and their first withdrawal can happen immediately.

This is a great reason why it's always a good idea to test your code. You will gain a much better understanding of the code.

## Token-related unit tests  

Now we need to complete the last of the token-streams unit tests.

First, we will need to create a better mock token to use here. The easiest way is to use the Openzeppelin ERC20 implementation, conveniently available from the library already imported, as a base.

Looking ahead, we know that we would need to test the `TRANSFER_FAILED` error case for token transfers, so we quickly extend the ERC20 contract to include these functions. 

This conveniently brings us to the concept of `mocks`. A mock contract is a contract that imitates a contract that our testing target is expected to work with. 

We create `MockToken`, which is basically an `ERC20` contract extension, with added `blacklist` capability so that we can test cases where transfers will fail.

> Always ensure you are creating accurate mocks! If the mock is inaccurate it may create or hide actual issues.  

With the mock implemented we simply implement the rest of the token-related test cases that are yet to be done.

The `YourContract.t.sol` has extensive comments for these tests.

## When are we done? 

Before you call it quits on the unit tests, we first check the amount of `coverage` we have.

```
forge coverage
```

This will output a summary like this:
```
| File                    | % Lines         | % Statements    | % Branches     | % Funcs       |
|-------------------------|-----------------|-----------------|----------------|---------------|
src/YourContract.sol    | 100.00% (44/44) | 100.00% (64/64) | 96.15% (25/26) | 100.00% (6/6)
```

We see that we have almost perfect coverage, but there is one branch that isn't being hit. `branches` refers to the conditional statements (`if`) that are present in the code.

Let's inspect this closely:

```
forge coverage --report debug
```

And this conveniently gives us the exact line that isn't covered yet:
```
Uncovered for src/YourContract.sol:
- Branch (branch: 12, path: 1) (location: source ID 23, line 118, chars 4634-4672, hits: 0)
```

We know from our test `test_withdrawStreamTokenNonReceiver` that we do cover this line. So after some deliberation we will treat this as a bug in the reporting mechanism.

> 100% coverage doesn't mean no bugs!

We can now be confident that each function in `YourContract` has been tested. Our unit test is complete.

Unfortunately, these unit tests clearly represent the most straightforward happy paths that users can take. Luckily Foundry gives us an super power: fuzzing!

Come back for part 3 soon!