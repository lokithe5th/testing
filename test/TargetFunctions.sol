
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {Properties} from "./Properties.sol";
import {vm} from "@chimera/Hevm.sol";

abstract contract TargetFunctions is BaseTargetFunctions, Properties, BeforeAfter {

    function yourContract_addBatch(address[] calldata _builders, uint256[] calldata _caps, address[] calldata _optionalTokenAddresses) public {
      yourContract.addBatch(_builders, _caps, _optionalTokenAddresses);
    }

    function yourContract_addBuilderStream(address _builder, uint256 _cap, address _optionalTokenAddress) public {
      yourContract.addBuilderStream(payable(_builder), _cap, _optionalTokenAddress);
    }

    function yourContract_renounceOwnership() public {
      yourContract.renounceOwnership();
    }

    function yourContract_streamWithdraw(uint256 _amount, string calldata _reason) public {
      yourContract.streamWithdraw(_amount, _reason);
    }

    function yourContract_transferOwnership(address newOwner) public {
      yourContract.transferOwnership(newOwner);
    }

    function yourContract_updateBuilderStreamCap(address _builder, uint256 _cap) public {
      yourContract.updateBuilderStreamCap(payable(_builder), _cap);
    }
}
