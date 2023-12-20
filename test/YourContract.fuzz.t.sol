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

// This is the modified contract for fuzzing in Foundry for Part-3
contract YourContractFuzz is Test {
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
        vm.warp(1700113467);

        mockToken = new MockToken("Mock Token", "MCK", 18);
    }

    // Pseudorandom decimals token generator
    // It uses the fuzz input from foundry to generate a pseudorandom amount of decimals
    function _tokenHelper(address _seed) internal returns (address) {
        uint256 input = uint256(keccak256(abi.encodePacked(_seed)));
        uint8 decimals = uint8(bound(input, 1, 30));
        return address(new MockToken("Mock Token", "TKN", decimals));
    }

    // Let's do a simple test first to check that we have deployed our contract correctly
    // In this case there is a public constant we can test
    function test_constants() public {
        assertEqUint(yourContract.FREQUENCY(), 30 days);
    }

    // We do a simple unit test to give Bob a stream
    // We are giving him a cap of DEFAULT_STREAM_VALUE
    // We specifying address(0) to signify this is an ether stream
    function test_addBuilderStreamEth(address _builder, uint256 _cap) public {
        // We can specify bounds for fuzzed inputs using `vm.assume`
        assumeNotZeroAddress(_builder);


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

    // Case: add valid builder + token
    function test_addBuilderStreamToken(address _builder, uint256 _cap) public {
        // Emits can be tricky in foundry
        vm.expectEmit(true, true, false, true, address(yourContract));
        emit AddBuilder(_builder, _cap);

        mockToken = MockToken(_tokenHelper(_builder));

        yourContract.addBuilderStream(payable(_builder), _cap, address(mockToken));

        // Let's make sure that Bob has been added successfully  
        // We get the newly added data from the struct
        (uint256 cap, , address token) = yourContract.streamedBuilders(_builder);
        // We assert that the cap is 0.5 as expected
        assertEq(cap, _cap);
        // We assert the token address is address(0) as expected
        assertEq(address(mockToken), token);
    }

    // But we also want to test some negative cases
    // Let's test if someone else tries to add a stream  
    function test_addBuilderStreamNotOwner(address _notTheOwner) public {
        vm.assume(_notTheOwner != address(this));
        // To impersonate an account we simply use `vm.prank(address account)` which impersonates for 1 contract call
        // or we can use `vm.startPrank(address account)` to impersonate until we wish to stop
        vm.startPrank(_notTheOwner);
        // To test if a call reverts we use `vm.expectRevert()`, this means the test will fail if
        // the next contract call does not revert with the appropriate reason
        vm.expectRevert("Ownable: caller is not the owner");

        yourContract.addBuilderStream(payable(bob), DEFAULT_STREAM_VALUE, address(0));
    }

    // Case: valid stream cap update
    function test_updateBuilderStreamCap(address _builder, uint256 _cap, uint256 _startingCap) public {
        // Note: If the stream cap is 0, then the stream cap cannot be updated anymore
        assumeNotZeroAddress(_builder);
        vm.assume(_cap > 0);
        vm.assume(_startingCap > 0);
        test_addBuilderStreamEth(_builder, _startingCap);
        
        // We know that Bob has been added in the preceeding function
        // We now try to increase his stream cap
        vm.expectEmit(true, true, false, true, address(yourContract));
        emit UpdateBuilder(_builder, _cap);
        yourContract.updateBuilderStreamCap(payable(_builder), _cap);

        // We assert the update went through
        (uint256 cap, ,) = yourContract.streamedBuilders(_builder);
        assertEq(cap, _cap);
    }

    // Case: check against an unauthorized call to udpate stream cap
    function test_updateBuilderStreamCapNotOwner(address _notOwner) public {
        vm.assume(address(this) != _notOwner);
        test_addBuilderStreamEth(bob, DEFAULT_STREAM_VALUE);

        vm.startPrank(_notOwner);
        
        // Only the owner should be able to update a stream
        vm.expectRevert("Ownable: caller is not the owner");
        yourContract.updateBuilderStreamCap(payable(bob), 1 ether);

        // We assert the update didn't go through
        (uint256 cap, ,) = yourContract.streamedBuilders(bob);
        assertEq(cap, DEFAULT_STREAM_VALUE);
    }

    // Case: check against a call to update a non-existant builder
    function test_updateBuilderStreamCapNotBuilder(address _builder, uint256 _cap) public {
        // We now expect a revert with a specific custom error
        vm.expectRevert(YourContract.NO_ACTIVE_STREAM.selector);
        yourContract.updateBuilderStreamCap(payable(_builder), _cap);
    }

    // Case: can add multiple builders
    function test_addBatchFuzz(address[] memory _builders, uint256[] memory _caps) public {
        // The trick here is that the below will be rejected
        vm.assume(_builders.length > 0);
        vm.assume(_builders.length <= _caps.length);

        // Thus, we need a workaround to test that multiple builders with different caps can be added
        uint256 length = _builders.length;
        address[] memory _tokens = new address[](length);
        uint256[] memory _filteredCaps = new uint256[](length);

        // We expect multiple emits
        for (uint256 i; i < length; i++) {
            _tokens[i] = address(mockToken);
            _filteredCaps[i] = _caps[i];

            vm.expectEmit(true, true, false, true, address(yourContract));
            emit AddBuilder(_builders[i], _caps[i]);
        }

        yourContract.addBatch(_builders, _filteredCaps, _tokens);

        // We assert that the batch was added successfully
        for (uint256 i; i < length; i++) {
            (uint256 cap, , address token) = yourContract.streamedBuilders(_builders[i]);
            if (cap != _filteredCaps[i]) {
                uint256 k;
                // Why remove the `assertEq` here? 
                // Because the if statement is testing that the cap was updated and that it reflects correctly
                for (length - 1; k > 0; k--) {
                    if (_builders[i] == _builders[k] && cap == _filteredCaps[k]) {
                        cap = _filteredCaps[k];
                        break;
                    }
                }
            } else {
                assertEq(cap, _filteredCaps[i]);
            }
            assertEq(token, _tokens[i]);
        }

    }

    // Case: check failure due to array lengths
    function test_addBatchInvalidArrayLength(address[] memory _builders, uint256[] memory _caps) public {
        vm.assume(_builders.length > 0);
        vm.assume(_builders.length < _caps.length);
        address[] memory _tokens = new address[](_caps.length + 1);


        // Check that the array length check reverts
        vm.expectRevert(YourContract.INVALID_ARRAY_INPUT.selector);
        yourContract.addBatch(_builders, _caps, _tokens);
    }

    // Case: check the `allBuildersData` return function
    function test_allBuildersData(address[] memory _builders, uint256[] memory _caps) public {
        test_addBatchFuzz(_builders, _caps);

        vm.warp(block.timestamp + 5 days);
        // We now check the returned data from the target function
        YourContract.BuilderData[] memory returnedData = yourContract.allBuildersData(_builders);

        uint256 length = returnedData.length;

        // We assert that the batch was added successfully
        for (uint256 i; i < length; i++) {
            assertEq(returnedData[i].builderAddress, _builders[i]);

            if (returnedData[i].cap != _caps[i]) {
                // Because the if statement is testing that the cap was updated and that it reflects correctly
                for (uint256 k = returnedData.length; k > 0; k--) {
                    if (returnedData[i].builderAddress == _builders[k - 1] && returnedData[i].cap == _caps[k - 1]) {
                        returnedData[i].cap = _caps[k - 1];
                        break;
                    }
                }
            } else {
                assertEq(returnedData[i].cap, _caps[i]);
            }

            assertEq(returnedData[i].unlockedAmount, returnedData[i].cap);
        }
    }

    // Case: check that the contract can receive ETH
    function test_receiveETH(uint256 amount) public {
        vm.assume(amount > 0);
        // When sending ETH, make sure you deal enough to your test contract
        deal(address(this), amount);
        // We test this by sending one ether to the contract
        (bool success, ) = address(yourContract).call{value: amount}("");
        require(success, "Failed to send");

        // We assert that the contract has this balance
        assertEq(address(yourContract).balance, amount);
    }

    // Case: ETH-based, valid withdrawal
    function test_streamWithdraw(address user, uint256 cap, uint256 amount) public {
        cap = bound(cap, 1, type(uint128).max);
        // We need to enforce our assumptions for the inputs here
        // Note: there is an explicit assumption that `amount` is less than `cap`
        // This is because the contrary is explicitly tested `NotEnoughEthInStream`
        vm.assume(amount < cap);
        vm.assume(user != address(this) && user != address(yourContract));
        vm.assume(user != address(mockToken));

        // These addresses may revert ETH calls
        assumeNotZeroAddress(user);
        assumeNotPrecompile(user);
        assumeNotForgeAddress(user);

        // Setup the contract
        test_addBuilderStreamEth(user, cap);
        test_receiveETH(cap);

        // Now we need enough time to pass so that the stream is full
        vm.warp(block.timestamp + 31 days);

        // We check that `user` can withdraw `cap`
        assertEq(yourContract.unlockedBuilderAmount(user), cap);

        // We withdraw the ether, impersonating bob
        uint256 userBalance = user.balance;

        vm.startPrank(user);
        
        vm.expectEmit(true, true, true, true, address(yourContract));
        emit Withdraw(user, amount, "Some reason");

        yourContract.streamWithdraw(amount, "Some reason");

        // We assert that user's balance is now DEFAULT_STREAM_VALUE more
        assertEq(user.balance, userBalance + amount);
    }

    // Case: token-based stream, withdrawal
    function test_streamWithdrawToken(address _builder, uint256 _cap) public {
        _cap = bound(_cap, 1, type(uint128).max);
        vm.assume(_builder != address(this) && _builder != address(yourContract));

        // Tokens cannot be sent to the ZERO_ADDRESS
        assumeNotZeroAddress(_builder);

        // First we must add a stream
        test_addBuilderStreamToken(_builder, _cap);
        // Then we should fund it
        deal(address(mockToken), address(yourContract), _cap);

        // Now we need enough time to pass so that the stream is full
        vm.warp(block.timestamp + 31 days);

        // We check that `user` can withdraw `cap`
        assertEq(yourContract.unlockedBuilderAmount(_builder), _cap);

        // Get starting balance
        uint256 builderBalance = mockToken.balanceOf(_builder);

        vm.startPrank(_builder);
        vm.expectEmit(true, true, true, true, address(yourContract));
        emit Withdraw(_builder, _cap, "Some reason");

        yourContract.streamWithdraw(_cap, "Some reason");

        // We assert that user's balance is now `_cap` more
        assertEq(mockToken.balanceOf(_builder), builderBalance + _cap);
    }

    // Case: fail state, no eth in contract, valid streams
    function test_streamWithdrawNoETH(address _user, uint256 _cap) public {
        // Enforce appropriate limits
        _cap = bound(_cap, 1, type(uint128).max);
        assumeNotZeroAddress(_user);

        test_addBuilderStreamEth(_user, _cap);
        vm.warp(block.timestamp + 31 days);

        // We check that `user` can withdraw `cap`
        assertEq(yourContract.unlockedBuilderAmount(_user), _cap);

        // We expect the withdraw to revert  
        vm.expectRevert(YourContract.NOT_ENOUGH_FUNDS_IN_CONTRACT.selector);
        yourContract.streamWithdraw(_cap, "None");
    }

    // Case: fail state, token-based stream, builders can withdraw tokens
    function test_streamWithdrawNoToken(address _builder, uint256 _cap) public {
        _cap = bound(_cap, 1, type(uint128).max);

        test_addBuilderStreamToken(_builder, _cap);
        vm.warp(block.timestamp + 31 days);

        // We check that `user` can withdraw `cap`
        assertEq(yourContract.unlockedBuilderAmount(_builder), _cap);

        // We expect the withdraw to revert  
        vm.expectRevert(YourContract.NOT_ENOUGH_FUNDS_IN_CONTRACT.selector);
        yourContract.streamWithdraw(_cap, "None");
    }

    // Case: fail-state, non-builders have no stream
    function test_streamWithdrawNoBuilder(address user) public {
        test_receiveETH(1 ether);
        // Now we need enough time to pass so that the stream is full
        vm.warp(block.timestamp + 31 days);

        // We check that Alice cannot withdraw anything
        assertEq(yourContract.unlockedBuilderAmount(alice), 0);

        // We expect the withdraw to revert  
        vm.expectRevert(YourContract.NO_ACTIVE_STREAM.selector);
        yourContract.streamWithdraw(DEFAULT_STREAM_VALUE, "None");
    }

    // Case: ETH-based stream, not enough balance in contract for the amount requested
    function test_streamWithdrawNotEnoughFundsInContractEth(address user, uint256 cap) public {
        cap = bound(cap, 1, type(uint128).max);
        // We are adding Bob
        test_addBuilderStreamEth(user, cap);
        (bool success, ) = address(yourContract).call{value: cap / 2}("");

        // Now we need enough time to pass so that the stream is full
        vm.warp(block.timestamp + 21 days);

        // We expect the withdraw to revert  
        vm.startPrank(bob);
        vm.expectRevert(YourContract.NOT_ENOUGH_FUNDS_IN_CONTRACT.selector);
        yourContract.streamWithdraw(cap, "None");
    }

    // Case: token-based stream, not enough balance in contract for the amount requested
    function test_streamWithdrawNotEnoughFundsInContractToken(address _builder, uint256 _cap) public {
        _cap = bound(_cap, 1, type(uint128).max);

        assumeNotZeroAddress(_builder);
        assumeNotPrecompile(_builder);
        assumeNotForgeAddress(_builder);

        test_addBuilderStreamToken(_builder, _cap);
        deal(address(mockToken), address(yourContract), _cap / 2);

        // Now we need enough time to pass so that the stream is full
        vm.warp(block.timestamp + 21 days);

        // We expect the withdraw to revert  
        vm.startPrank(bob);
        vm.expectRevert(YourContract.NOT_ENOUGH_FUNDS_IN_CONTRACT.selector);
        yourContract.streamWithdraw(_cap, "None");
    }

    // Case: ETH-based stream, not enough accrued for the amount requested
    function test_streamWithdrawNotEnoughFundsInStreamEth(address _builder, uint256 _cap) public {
        _cap = bound(_cap, 1, type(uint128).max);

        vm.assume(_builder != address(yourContract) && _builder != address(this));
        vm.assume(_builder != address(mockToken));
        assumeNotZeroAddress(_builder);
        assumeNotPrecompile(_builder);
        assumeNotForgeAddress(_builder);
        
        test_addBuilderStreamToken(_builder, _cap);
        // We assert this assumption here because the preceding call changes the `MockToken`
        vm.assume(_builder != address(mockToken));

        // We provide enough funds for the contract itself so contract balance > requested
        deal(address(yourContract), _cap * 2);

        // 16 Nov 2023
        vm.warp(1700123467);
        test_addBuilderStreamEth(_builder, _cap);
        vm.warp(1700123468);
        (bool success, ) = address(yourContract).call{value: _cap}("");

        // `user` makes their first withdrawal. 
        vm.prank(_builder);
        yourContract.streamWithdraw(_cap, "None");
        // Now we need time to pass so the stream is not full
        // 30 Nov 2023
        vm.warp(1701333065);

        // We expect the withdraw to revert  
        vm.startPrank(_builder);
        vm.expectRevert(YourContract.NOT_ENOUGH_FUNDS_IN_STREAM.selector);
        yourContract.streamWithdraw(_cap, "None");
        vm.stopPrank();
    }

    // Case: token-based stream, not enough accrued for the amount requested
    function test_streamWithdrawNotEnoughFundsInStreamToken(address _builder, uint256 _cap) public {
        // Note: we picked up an important constraint here
        // If the `_cap` is large enough it will cause an overflow within the `streamWithdraw` call where
        // `(block.timestamp - builderStream.last) * _amount `
        _cap = bound(_cap, 1, type(uint128).max);

        assumeNotZeroAddress(_builder);
        assumeNotPrecompile(_builder);
        assumeNotForgeAddress(_builder);

        // 16 Nov 2023
        vm.warp(1700123467);
        test_addBuilderStreamToken(_builder, _cap);
        vm.warp(1700123468);
        deal(address(mockToken), address(yourContract), _cap * 2);

        vm.prank(_builder);
        yourContract.streamWithdraw(_cap, "None");
        // Now we need time to pass so the stream is not full
        // 30 Nov 2023
        vm.warp(1701333065);

        // We expect the withdraw to revert  
        vm.startPrank(_builder);
        vm.expectRevert(YourContract.NOT_ENOUGH_FUNDS_IN_STREAM.selector);
        yourContract.streamWithdraw(_cap, "None");
        vm.stopPrank();
    }

    // Case: builders should accrue streams according to time passed
    function test_unlockedBuilderAmount(address _builder, uint256 _cap) public {
        _cap = bound(_cap, 1, type(uint128).max);

        assumeNotZeroAddress(_builder);
        assumeNotPrecompile(_builder);
        assumeNotForgeAddress(_builder);

        // This adds builder's stream
        vm.warp(1700123467);
        test_addBuilderStreamEth(_builder, _cap);
        // We fund and withdraw the first immediate stream
        vm.warp(1700123468);
        deal(address(this), _cap);
        (bool success, ) = address(yourContract).call{value: _cap}("");

        vm.prank(_builder);
        yourContract.streamWithdraw(_cap, "None");

        // Now we need some time to pass so the stream is not full
        // 30 Nov 2023
        // We need to check that Bob has accrued the appropriate amount at various timestamps
        // We check in increments of 10 days
        uint256 amountAt0Days = yourContract.unlockedBuilderAmount(_builder);
        assertEq(amountAt0Days, _cap * 0 / 30);

        vm.warp(1700123468 + 10 days);
        uint256 amountAt10Days = yourContract.unlockedBuilderAmount(_builder);
        assertEq(amountAt10Days, _cap * 10 / 30);

        vm.warp(1700123468 + 20 days);
        uint256 amountAt20Days = yourContract.unlockedBuilderAmount(_builder);
        assertEq(amountAt20Days, _cap * 20 / 30);

        vm.warp(1700123468 + 30 days);
        uint256 amountAt30Days = yourContract.unlockedBuilderAmount(_builder);
        assertEq(amountAt30Days, _cap * 30 / 30);

        vm.warp(1700123468 + 50 days);
        uint256 amountAt50Days = yourContract.unlockedBuilderAmount(_builder);
        assertEq(amountAt30Days, _cap * 30 / 30);
    }

    // Case: Non-builders should not have amounts
    function test_unlockedBuilderAmountNonBuilder(address _builder) public {
        vm.assume(_builder != bob);

        vm.warp(1700123467);
        test_addBuilderStreamEth(bob, DEFAULT_STREAM_VALUE);
        vm.warp(1700183468);

        (bool success, ) = address(yourContract).call{value: 1 ether}("");

        // We check that a non-builder cannot acrue a stream
        // It should always return 0
        assertEq(yourContract.unlockedBuilderAmount(_builder), 0);
    }

    // Case: ETH-based stream, transfer to builder fails
    function test_withdrawStreamEthNonReceiver(uint256 _cap) public {
        vm.assume(_cap > 0 && _cap < type(uint96).max);

        // We add the `mockToken` as a builder because we know it cannot `receive` ETH
        yourContract.addBuilderStream(payable(address(mockToken)), _cap, address(0));

        deal(address(this), _cap);
        (bool success, ) = payable(address(yourContract)).call{value: _cap}("");

        vm.warp(block.timestamp + 31 days);
        vm.startPrank(address(mockToken));

        vm.expectRevert(YourContract.TRANSFER_FAILED.selector);
        yourContract.streamWithdraw(_cap, "Some reason");

        assertEq(address(mockToken).balance, 0);
    }

    // Case: token-based stream, `transfer` to builder fails
    function test_withdrawStreamTokenNonReceiver(address _builder, uint256 _cap) public {
        vm.assume(_cap > 0 && _cap < type(uint96).max);

        test_addBuilderStreamToken(_builder, _cap);
        deal(address(mockToken), address(yourContract), _cap);

        // Now we need enough time to pass so that the stream is full
        vm.warp(block.timestamp + 31 days);

        assertEq(yourContract.unlockedBuilderAmount(_builder), _cap);

        uint256 bobBalance = mockToken.balanceOf(_builder);
        // We test that token transfers fail by blacklisting the receiver
        mockToken.setBlacklist(_builder, true);

        vm.startPrank(_builder);
        
        vm.expectRevert(YourContract.TRANSFER_FAILED.selector);
        yourContract.streamWithdraw(_cap, "Some reason");

        // We assert that bob's balance is still 0
        assertEq(mockToken.balanceOf(_builder), 0);
    }

}
