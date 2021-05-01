pragma solidity ^0.8.4;

import "./utils/Context.sol";
import "./ERC20Deflationary.sol";

contract ExampleToken is Context, ERC20Deflationary {

    // pancakeswap for testnet
    //address routerAddress = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1;
    
    //uniswap
    address routerAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    string name_ = "ExampleToken";
    string symbol_ = "EXT";
    uint8 decimal_ = 9;
    uint256 totalSupply_ = 100;
    uint8 taxFee_ = 10;

    constructor () ERC20Deflationary(name_, symbol_, decimal_, totalSupply_) {
        enableAutoBurn(taxFee_);
        enableReward(taxFee_);
        //enableAutoSwapAndLiquify(10, routerAddress, 10 * 10**9);
    }

}