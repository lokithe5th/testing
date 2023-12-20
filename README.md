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
- When withdrawing from a stream the contract balance after withdrawal SHOULD be equal to the balance before - withdrawn amount
- Non-builders SHOULD NOT be able to claim streams
- Only the owner SHOULD be able to access privileged functions.

We have eight invariants that should hold in our contract that has less than 130 lines.  

## Reworking the current tests  

Refer to the repo to see how the test file changes to accommodate foundry fuzz tests. 

Highligting a few interesting cheats here: 

### `vm.assume()`

`vm.assume(condition)` is a cheat code used in Foundry. This allows us to filter the values provided by Foundry. It's used by simply stating a condition that must hold for the fuzzed inputs. E.g. `vm.assume(_builder != address(this))`

### `bound()`
You will at times run into issues where Foundry errors out because you've rejected too many possible inputs with the `assume` cheat. 

We get around this by using `input = bound(input, minVal, maxVal)`, where `input` is a `uint256` provided by the fuzzer and the `minVal` is the lowest allowed value and `maxVal` is the largest allowed value. It takes the input created by the fuzzer and returns a value bound within the min and max ranges you define. 

Nifty! 

### `assumeNotPrecompile(address)`  

`assumeNotPrecompile()` along with `assumeAddressIsNot()` and `assumeNotZeroAddress()` are great examples of extra cheat codes that Foundry provides access to. There are too many of these to name here, but it's worthwhile exploring it to find out.

## Gotchas
### Array values repeating  
Pretty soon we run into this challenge during the `test_addBatchFuzz` test:
```
    ├─ [912] YourContract::streamedBuilders(0x0000000000000000000000000000000000002B28) [staticcall]
    │   └─ ← 188063726281073745118794773114831187209042962873547266811280170673 [1.88e65], 86400 [8.64e4], MockToken: [0x2e234DAe75C793f67A35089C9d99245E1C58470b]
    ├─ emit log(: Error: a == b not satisfied [uint])
    ├─ emit log_named_uint(key:       Left, val: 188063726281073745118794773114831187209042962873547266811280170673 [1.88e65])
    ├─ emit log_named_uint(key:      Right, val: 898734154750939992864526935637855074663122227116 [8.987e47])
```

What's happened here is that some of the addresses have been duplicated and the caps updated later on in the arrays. This can be frustrating and you can spend hours trying to find the issue until you realize that it's the fuzzed inputs that are being duplicated.

The approach I chose to implement is quite simple: If the cap is not equal to the expected value, then we loop through the array and see if it has been updated somewhere later and then check that the address reflects correctly there. If this is not the case there is an error in the contract.

### `block.timestamp`  
We once again ran into some issues with `block.timestamp`. When dealing with contracts that use `block.timestamp`, be sure to set the current time with `vm.warp(targetDate)`.

Otherwise you may experience issues when trying to do math functions, as the block timestamp may start at 0. 

## New issues exposed by fuzz tests  

As expected our fuzz testing exposed a few implicit assumptions and/or issues that we hadn't yet documented. 

Such findings are important because of the composability of DeFi - what happens to someone building on our contracts that is unaware of our implicit assumptions? It creates a security risk. This is why we make our assumptions explicit in our docs.

### `cap` should not be greater than a `uint96` value  
After running a few fuzz tests it became apparent that for a large enough `cap` value, the following code would create an unexpected overflow:
```
        builderStream.last = builderStream.last + ((block.timestamp - builderStream.last) * _amount / totalAmountCanWithdraw);
```

This is an impossible value in practice, yet it revealed the implicit assumption that token or ETH amounts would be less than the maximum of `uint256`.

Our fix in our test is to bind the `cap` to always be less than `uint128`. 

The reporting would be a `LOW` severity finding with the recommendation to either document that stream caps must be less than `uint128` or explicitly require it when creating a stream.

### `cap` can be set to be `0` 
Another finding from the foundry fuzzing is that a stream cap can be set to `0`. This would cause updates to the stream cap to always revert because of this code:
```
    if (builderStream.cap == 0) revert NO_ACTIVE_STREAM();
```

This would be another `LOW` severity finding with a recommendation to not allow a stream cap to be set as `0`. Should a stream need to be removed it should be done in an explicit `reduceBuilderStreamCap` function.

This led to another interesting finding:  

### Streams can be overwritten, causing builders to lose their current stream's accrued funds
The owner is able to add the same builder more than once, but with different `optionalTokenAddress` parameters. This creates a scenario where a builder may be busy accruing funds in one token, but the `owner` then adds the builder again but with a different token address. The builder's `BuilderStreamInfo.last` is overwritten and the builder will be able to withdraw the full amount of the new stream immediately, however they will not be able to access the previously accrued tokens.

This may be a `MEDIUM` finding in some cases, but here the `addBuilderStream` function has access control and this would constitute an admin mistake. In addition, switching the token back is possible by calling `addBuilderStream` again with the old token. The full amount is then withdrawable immediately.

## Conclusion  
That's a wrap for part 3! 

As you can see, simple fuzzing in Foundry can be powerful for identifying implicit assumptions about your project. 

The next part will focus on some more advanced fuzzing tools. First up: Medusa!