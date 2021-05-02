// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Context.sol";
import "./ERC20Deflationary.sol";

contract ExampleToken is Context, ERC20Deflationary {

    string private name_ = "ExampleToken";
    string private symbol_ = "EXT";
    uint8 private decimal_ = 9;
    uint256 private tokenSupply_ = 10 ** 15;
    uint8 private taxBurn_ = 10;
    uint8 private taxReward_ = 10;
    uint8 private taxLiquify_ = 10;
    uint256 private minTokensBeforeSwap_ = (10 ** 7) * (10 ** decimal_); 
    address private pancakeswapV2Router = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    constructor () ERC20Deflationary(name_, symbol_, decimal_, tokenSupply_) {
        enableAutoBurn(taxBurn_);
        enableReward(taxReward_);
        enableAutoSwapAndLiquify(taxLiquify_, pancakeswapV2Router, minTokensBeforeSwap_);
    }

}