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

Hypothesis: the stream accrual calculation is wrong.

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

What this tells us is that according to the logic in the contract, Bob had 0.5 ether available immediately after his stream was opened. 

> This may signal a bug in the contract. We should ascertain from the devs if the entire stream is supposed to be withdrawable immediately after the first funding.

After reaching out to Austin, he points us in the direction of his [tweets earlier this year](https://x.com/austingriffith/status/1674444986463719424?s=46&t=3J-S7_iZrqdWSB0sUNFYRA). This confirms that it is expected behaviour.

## Token-related unit tests  

First, we will need to create a mock token to use here.

## When are we done? 

Before you call it quits