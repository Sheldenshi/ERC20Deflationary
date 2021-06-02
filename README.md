# ERC20Deflationary

If you find this useful, I accept donation of your token :) my ERC-20 wallet address: 0x09224bC4a1Ea9ce55E953bFab083A055eC4d19B7

** Reward, reflect, and distribute are used interchangeably in code comments.

An ERC20 Token that charges a + b + c % of transaction fees. 
- a% of a transaction will be automatically added to the liquidity pool and locked.
- b% of a transaction will be redistribute(reflected) to all holders. 
- c% of a transaction will be burnt.


Currently supports static reward (automatically redistribute b% of each transactions) and burn c% of transactions.

Feel free to submit an issue or pull request :)


## How to use:

Clone this git repo and import ERC20Deflationary.sol

Example:

```
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Context.sol";
import "./ERC20Deflationary.sol";

contract ExampleToken is Context, ERC20Deflationary {

    string private name_ = "ExampleToken";
    string private symbol_ = "EXT";
    uint8 private decimal_ = 9;
    uint256 private tokenSupply_ = 10 ** 12;
    uint8 private taxBurn_ = 10;
    uint8 private taxReward_ = 10;
    uint8 private taxLiquify_ = 10;
    uint8 private taxDecimals_ = 0;
    uint256 private minTokensBeforeSwap_ = (10 ** 6) * (10 ** decimal_);

    //address private routerAddress = // LP provider address

    constructor () ERC20Deflationary(name_, symbol_, decimal_, tokenSupply_) {
        enableAutoBurn(taxBurn_, taxDecimals_);
        enableReward(taxReward_, taxDecimals_);
        enableAutoSwapAndLiquify(taxLiquify_, taxDecimals_, routerAddress, minTokensBeforeSwap_);
    }

}
    }
}
```

## How to run test:

In the terminal

```
truffle test
```
## Deploy
```
truffle migrate --network testnet
```
## Verify
```
truffle run verify ExampleToken --network testnet
```
