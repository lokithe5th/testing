
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BaseSetup} from "@chimera/BaseSetup.sol";

import "src/mocks/MockToken.sol";
import "src/YourContract.sol";

abstract contract Setup is BaseSetup {

    YourContract yourContract;

    function setup() internal virtual override {
      yourContract = new YourContract(); // TODO: Add parameters here
    }
}
