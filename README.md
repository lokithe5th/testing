# Testing in Foundry - Part 3

## Let's get fuzzical!

If you've been following along you'll know that we've gone from no tests, up to a fairly well-covered unit test repo for the BuidlGuidl's streaming contract. Although this is great to make sure the contracts do what we want them to do under ideal circumstances, on the blockchain circumstances may never be ideal.

There is a lot of theory on fuzzing and some great blogs about it too, but to keep it simple: For our purposes, when we talk about fuzzing we mean that we are using a tool (like Foundry) to programmatically generate several (sometimes thousands) of different inputs against which we test the state in our contracts. 

This is helpful for a number of reasons: 
1) it better simulates real-world behaviour (if only everything was a happy-path)
2) it is faster than manually writing a test for each possible scenario
3) it allows us to identify and explore edge cases that can only be found with certain contract states (find something even if we are not looking for it)

## Fuzzing in Foundry  

Foundry helpfully has native support for fuzzing. Want to see it in action? It's simple!

We start with our simplest test to demonstrate. Adding a stream for Bob (the buidler): 

```
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
```

Foundry recognizes that we want to fuzz the inputs for a certain test, when we specify input variables for our test functions. These inputs can then be used in the function itself. We then swap out our static instances of `Bob` and `DEFAULT_STREAM_VALUE` for the input variables `_builder` and `_cap`. Note that I changed the test name to `test_addBuilderStreamEth`. This leaves us with:

```
    function test_addBuilderStreamEth(address _builder, uint256 _cap) public {
        // We can specify bounds for fuzzed inputs using `vm.assume`
        vm.assume(_cap <= DEFAULT_STREAM_VALUE);
        // Emits can be tricky in foundry
        vm.expectEmit(true, true, false, true, address(yourContract));
        emit AddBuilder(_builder, _cap);

        yourContract.addBuilderStream(payable(_builder), _cap, address(0));

        // Let's make sure that Bob has been added successfully  
        // We get the newly added data from the struct
        (uint256 cap, , address token) = yourContract.streamedBuilders(_builder);
        // We assert that the cap is 0.5 as expected
        assertEq(cap, _cap);
        // We assert the token address is address(0) as expected
        assertEq(address(0), token);
    }
```

When we run this via `test --match-test test_addBuilderStreamEth -vvv` and get: 
```
Running 1 test for test/YourContract.t.sol:YourContractTest
[PASS] test_addBuilderStreamEth(address,uint256) (runs: 256, μ: 61117, ~: 63061)
Test result: ok. 1 passed; 0 failed; 0 skipped; finished in 22.48ms

Ran 1 test suites: 1 tests passed, 0 failed, 0 skipped (1 total tests)
```

With a few simple tweaks we see that Foundry ran this test 256 times!

## Changes  

Inevitably this requires changes to the other tests. But the amount of freedom this provides you as a developer means that it is well worth the effort. 

## Invariants

At this point it may be a good idea to talk about invariants. Although there is (once again) a plethora of great articles/blogs or and videos about the topic, in it's simplest form: an invariant is a context-specific condition related to the state of your contract that must always hold.

For example, the new eBTC contest has a huge list of invariants that ensure the health of the protocol. In their case, these are rules like: the amount of collateral held should always be above 125% of the total debt of the protocol. 

Invariants are usually specific to the project you are building. What do you think may be a few invariants we have in our contract here? 

Another way to approach it is to figure out what you expect the protocol state should be at a specific point in time. `SHOULD` is the key word here. For example:

- A builder SHOULD only be able to claim up and equal to their `cap`
- A builder SHOULD only have one stream allocated at a time  
- A builder SHOULD be able to claim all the funds in a stream immediately after being added
- Claimable funds SHOULD accrue linearly according to time passed up to `FREQUENCY` 
- Additional funds SHOULD NOT accrue once `FREQUENCY` has passed
- When withdrawing from a stream a the contract balance after withdrawal SHOULD be equal to the balance before - withdrawn amount

We already have six invariants that should hold in our contract that has less than 130 lines.  

## Reworking the current tests  

Refer to the repo to see how the test file changes to accommodate foundry fuzz tests. 

Highligting a few interesting cheats here: 

### `vm.assume`

`vm.assume(condition)` is a cheat code used in Foundry. This allows us to filter the values provided by Foundry.

### `assumeNotPrecompile(address)`  

`assumeNotPrecompile()` along with `assumeAddressIsNot()` and `assumeNotZeroAddress()` are great examples of extra cheat codes that Foundry provides access to. There are too many of these to name here, but it's worthwhile exploring it to find out.

### 