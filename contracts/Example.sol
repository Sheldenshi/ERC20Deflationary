pragma solidity ^0.8.4;

import "./utils/Context.sol";
import "./ERC20Deflationary.sol";

contract Example is Context, ERC20Deflationary {

    // pancakeswap for testnet
    address routerAddress = 0x73D58041eDdD468e016Cfbc13f3BDc4248cCD65D;

    string name_ = "Example Token";
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