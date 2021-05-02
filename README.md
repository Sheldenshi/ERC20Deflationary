# ERC20Deflationary

** Reward, reflect, and distribute are used interchangeably in code comments.

An ERC20 Token that charges a + b + c % of transaction fees. 
- a% of a transaction will be automatically add to the liquidity pool and be locked.
- b% of a transaction will be redistribute(reflect) to all holders. 
- c% of a transaction will be burnt.


Currently supports static reward (automatically redistribute b% of each transactions) and burn c% of transactions.

Feel free to submit an issue or pull request :)


## How to use:

Clone this git repo and import ERC20Deflationary.sol

Example:

```
pragma solidity ^0.8.4;

import "./ERC20Deflationary.sol";

contract TestCoin is ERC20Deflationary {
    constructor() ERC20Deflationary("TestCoin", "TEST", 9, 100) {
         // default is 0
         // not required
         setTaxBurn(a);
         setTaxReward(b);
         setTaxLiquidity(c);
    }
}
```

## How to run test:

In the terminal

```
truffle test
```
