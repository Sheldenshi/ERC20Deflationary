pragma solidity ^0.8.4;

import "contracts/Utils/Context.sol";
import "contracts/ERC20Deflationary.sol";
import "interfaces/Pancakeswap/IRouter02.sol";

contract ExampleToken is Context, ERC20Deflationary {

    // pancakeswap for testnet
    address constant routerAddress = 0x73D58041eDdD468e016Cfbc13f3BDc4248cCD65D;

    constructor () ERC20Deflationary("TestCoin", "TEST", 9, 100) {
        enableAutoBurn(10);
        enableReward(10);
        enableAutoSwapAndLiquify(10, routerAddress, 10 * 10**9);
    }

}