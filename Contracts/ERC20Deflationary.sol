// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./utils/Context.sol";
import "./utils/Ownable.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/Pancakeswap/IFactory.sol";
import "../interfaces/Pancakeswap/IPair.sol";
import "../interfaces/Pancakeswap/IRouter01.sol";
import "../interfaces/Pancakeswap/IRouter02.sol";


contract ERC20Deflationary is Context, IERC20, Ownable {
    // balances for address that are included.
    mapping (address => uint256) private _rBalances;
    // balances for address that are excluded.
    mapping (address => uint256) private _tBalances;
    mapping (address => mapping (address => uint256)) private _allowances;

    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => bool) private _isExcludedFromReward;


    // liquidity pool provider router
    IUniswapV2Router02 internal _uniswapV2Router;
    address internal _uniswapV2Pair;

    address private constant burnAccount = 0x000000000000000000000000000000000000dEaD;

    address[] private _excludedFromReward;
   
   // this percent of transaction amount that will be burnt.
    uint8 private _taxBurn;
    // percent of transaction amount that will be redistribute to all holders.
    uint8 private _taxReward;
    // percent of transaction amount that will be added to the liquidity pool
    uint8 private _taxLiquidity; 
    uint8 private immutable _decimals;
    uint256 private  _totalSupply;
    uint256 private _currentSupply;
    uint256 private _rTotal;
    uint256 private _tFeeTotal;

    // swap and liquify every million tokens
    uint256 private _minTokensBeforeSwap;

    string private _name;
    string private _symbol;


    bool private _inSwapAndLiquify;
    bool private _autoSwapAndLiquifyEnabled;
    bool private _autoBurnEnabled;
    bool private _rewardEnabled;
        
    modifier lockTheSwap {
        require(!_inSwapAndLiquify, "Currently in swap and liquify.");
        _inSwapAndLiquify = true;
        _;
        _inSwapAndLiquify = false;
    }

    struct ValuesFromAmount {
        uint256 amount;
        uint256 tBurnFee;
        uint256 tRewardFee;
        uint256 tLiquidityFee;
        // amount after fee
        uint256 tTransferAmount;

        uint256 rAmount;
        uint256 rBurnFee;
        uint256 rRewardFee;
        uint256 rLiquidityFee;
        uint256 rTransferAmount;
    }

    event Burn(address from, uint256 amount);
    event TaxBurnUpdate(uint8 previous, uint8 current);
    event TaxRewardUpdate(uint8 previous, uint8 current);
    event TaxLiquidityUpdate(uint8 previous, uint8 current);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensAddedToLiquidity
    );
    event ExcludeAccountFromReward(address account);
    event IncludeAccountInReward(address account);
    event ExcludeAccountFromFee(address account);
    event IncludeAccountInFee(address account);
    event MinTokensBeforeSwapUpdated(uint256 previous, uint256 current);
    event EnabledAutoBurn(uint8 taxBurn_);
    event EnabledReward(uint taxReward_);
    event EnabledAutoSwapAndLiquify(uint8 taxLiquidity_);
    event DisabledAutoBurn();
    event DisabledReward();
    event DisabledAutoSwapAndLiquify();


    constructor (string memory name_, string memory symbol_, uint8 decimals_, uint256 totalSupply_) {
        // Sets the values for `name`, `symbol`, `totalSupply`, `taxFeeBurn`, `taxFeeReward`, and `taxFeeLiquidity`.
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _totalSupply = totalSupply_ * (10**decimals_);
        _currentSupply = _totalSupply;
        _rTotal = (~uint256(0) - (~uint256(0) % _totalSupply));

        // mint
        _rBalances[_msgSender()] = _rTotal;

        
        
        
        // exclude owner and this contract from fee.
        _excludeFromFee(owner());
        _excludeFromFee(address(this));

        // exclude owner, burnAccount, and this contract from receiving rewards.
        excludeAccountFromReward(owner());
        excludeAccountFromReward(burnAccount);
        excludeAccountFromReward(address(this));
        
        emit Transfer(address(0), _msgSender(), _totalSupply);
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    function taxBurn() public view virtual returns (uint8) {
        return _taxBurn;
    }

    function taxReward() public view virtual returns (uint8) {
        return _taxReward;
    }

    function taxLiquidity() public view virtual returns (uint8) {
        return _taxLiquidity;
    }
    function minTokensBeforeSwap() public view virtual returns (uint256) {
        return _minTokensBeforeSwap;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function currentSupply() public view virtual returns (uint256) {
        return _currentSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        if (_isExcludedFromReward[account]) return _tBalances[account];
        return tokenFromReflection(_rBalances[account]);
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        require(_allowances[sender][_msgSender()] >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()] - amount);
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        return true;
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != burnAccount, "ERC20: burn from the burn address");

        uint256 accountBalance = balanceOf(account);
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");

        uint256 rAmount = _getRValuesWithoutFee(amount);

        if (isExcluded(account)) {
            _tBalances[account] -= amount;
            _rBalances[account] -= rAmount;
        } else {
            _rBalances[account] -= rAmount;
        }

        _tBalances[burnAccount] += amount;
        _rBalances[burnAccount] += rAmount;

        // decrease the current coin supply
        _currentSupply -= amount;

        emit Burn(account, amount);
        emit Transfer(account, burnAccount, amount);
    }
   
     

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }


    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        ValuesFromAmount memory values = _getValues(amount, _isExcludedFromFee[sender]);
        
        if (_isExcludedFromReward[sender] && !_isExcludedFromReward[recipient]) {
            _transferFromExcluded(sender, recipient, values);
        } else if (!_isExcludedFromReward[sender] && _isExcludedFromReward[recipient]) {
            _transferToExcluded(sender, recipient, values);
        } else if (!_isExcludedFromReward[sender] && !_isExcludedFromReward[recipient]) {
            _transferStandard(sender, recipient, values);
        } else if (_isExcludedFromReward[sender] && _isExcludedFromReward[recipient]) {
            _transferBothExcluded(sender, recipient, values);
        } else {
            _transferStandard(sender, recipient, values);
        }

        if (!_isExcludedFromFee[sender]) {
            _afterTokenTransfer(values);
        }

    }

    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     */
    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, deducting from the caller's
     * allowance.
     *
     * See {ERC20-_burn} and {ERC20-allowance}.
     *
     * Requirements:
     *
     * - the caller must have allowance for ``accounts``'s tokens of at least
     * `amount`.
     */
    function burnFrom(address account, uint256 amount) public virtual {
        uint256 currentAllowance = allowance(account, _msgSender());
        require(currentAllowance >= amount, "ERC20: burn amount exceeds allowance");
        _approve(account, _msgSender(), currentAllowance - amount);
        _burn(account, amount);
    }

    function isExcluded(address account) public view returns (bool) {
        return _isExcludedFromReward[account];
    }

    function totalFees() public view virtual returns (uint256) {
        return _tFeeTotal;
    }

    /**
     * @dev Distribute tokens to all holders that are included from reward. 
     *
     *  Requirements:
     * - the caller must have a balance of at least `amount`.
     */
    function airdrop(uint256 amount) public {
        address sender = _msgSender();
        require(!_isExcludedFromReward[sender], "Excluded addresses cannot call this function");
        ValuesFromAmount memory values = _getValues(amount, false);
        _rBalances[sender] = _rBalances[sender] - values.rAmount;
        _rTotal = _rTotal - values.rAmount;
        _tFeeTotal = _tFeeTotal + amount ;
    }

    function reflectionFromToken(uint256 amount, bool deductTransferFee) public view returns(uint256) {
        require(amount <= _totalSupply, "Amount must be less than supply");
        ValuesFromAmount memory values = _getValues(amount, deductTransferFee);
        return values.rTransferAmount;
    }

    /**
        Used to figure out the balance of rBalance.
     */
    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return rAmount / currentRate;
    }


    /**
     * burns
     * reflect
     * add liquidity

        tValues = (uint256 tTransferAmount, uint256 tBurnFee, uint256 tRewardFee, uint256 tLiquidityFee);
        rValues = uint256 rAmount, uint256 rTransferAmount, uint256 rBurnFee, uint256 rRewardFee, uint256 rLiquidityFee;
     */
    function _afterTokenTransfer(ValuesFromAmount memory values) internal virtual {
        // burn from contract address
        if (_autoBurnEnabled) {
            _tBalances[address(this)] += values.tBurnFee;
            _rBalances[address(this)] += values.rBurnFee;
            _approve(address(this), _msgSender(), values.tBurnFee);
            burnFrom(address(this), values.tBurnFee);
        }   
        
        
        // reflect
        if (_rewardEnabled) {
            _distributeFee(values.rRewardFee, values.tRewardFee);
        }
        
        
        // add to liquidity
        
        if (_autoSwapAndLiquifyEnabled) {
            // add liquidity fee to this contract.
            _tBalances[address(this)] += values.tLiquidityFee;
            _rBalances[address(this)] += values.rLiquidityFee;

            uint256 contractBalance = _tBalances[address(this)];

            // whether the current contract balances makes the threshold to swap and liquify.
            bool overMinTokensBeforeSwap = contractBalance >= _minTokensBeforeSwap;

            if (overMinTokensBeforeSwap &&
                !_inSwapAndLiquify &&
                _msgSender() != _uniswapV2Pair &&
                _autoSwapAndLiquifyEnabled
                ) 
            {
                swapAndLiquify(contractBalance);
            }
        }
        
     }

    
    function _transferStandard(address sender, address recipient, ValuesFromAmount memory values) private {
        
    
        _rBalances[sender] = _rBalances[sender] - values.rAmount;
        _rBalances[recipient] = _rBalances[recipient] + values.rTransferAmount;   

        emit Transfer(sender, recipient, values.tTransferAmount);
    }

    
    function _transferToExcluded(address sender, address recipient, ValuesFromAmount memory values) private {
        
        _rBalances[sender] = _rBalances[sender] - values.rAmount;
        _tBalances[recipient] = _tBalances[recipient] + values.tTransferAmount;
        _rBalances[recipient] = _rBalances[recipient] + values.rTransferAmount;    

        
        emit Transfer(sender, recipient, values.tTransferAmount);
    }

    
    function _transferFromExcluded(address sender, address recipient, ValuesFromAmount memory values) private {
        
        _tBalances[sender] = _tBalances[sender] - values.amount;
        _rBalances[sender] = _rBalances[sender] - values.rAmount;
        _rBalances[recipient] = _rBalances[recipient] + values.rTransferAmount;   


        emit Transfer(sender, recipient, values.tTransferAmount);
    }

    
    function _transferBothExcluded(address sender, address recipient, ValuesFromAmount memory values) private {

        _tBalances[sender] = _tBalances[sender] - values.amount;
        _rBalances[sender] = _rBalances[sender] - values.rAmount;
        _tBalances[recipient] = _tBalances[recipient] + values.tTransferAmount;
        _rBalances[recipient] = _rBalances[recipient] + values.rTransferAmount;        

        
        emit Transfer(sender, recipient, values.tTransferAmount);
    }

    receive() external payable {}

    function swapAndLiquify(uint256 contractBalance) internal lockTheSwap {
        // split the contract balance into two halves.
        uint256 tokensToSwap = contractBalance / 2;
        uint256 tokensAddToLiquidity = contractBalance - tokensToSwap;

        // contract's current ETH balance.
        uint256 initialBalance = address(this).balance;

        // swap half of the tokens to ETH.
        swapTokensForEth(tokensToSwap);

        uint256 ethAddToLiquify = address(this).balance - initialBalance;

        addLiquidity(ethAddToLiquify, tokensAddToLiquidity);

        emit SwapAndLiquify(tokensToSwap, ethAddToLiquify, tokensAddToLiquidity);
    }

    function swapTokensForEth(uint256 amount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _uniswapV2Router.WETH();

        _approve(address(this), address(_uniswapV2Router), amount);


        // swap tokens to eth
        _uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount, 
            0, 
            path, 
            address(this), 
            block.timestamp
            );
    }
    function addLiquidity(uint256 ethAmount, uint256 tokenAmount) public {
        _approve(address(this), address(_uniswapV2Router), tokenAmount);

        // add the liquidity
        _uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this), 
            tokenAmount, 
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this), 
            block.timestamp
        );
    }
    function _distributeFee(uint256 rFee, uint256 tFee) private {
        // to decrease rate thus increase amount reward receive.
        _rTotal = _rTotal - rFee;
        _tFeeTotal = _tFeeTotal + tFee;
    }
    
    function _getValues(uint256 amount, bool deductTransferFee) private view returns (ValuesFromAmount memory) {
        ValuesFromAmount memory values;
        values.amount = amount;
        _getTValues(values, deductTransferFee);
        _getRValues(values, deductTransferFee);
        return values;
    }

    function _getTValues(ValuesFromAmount memory values, bool deductTransferFee) view private {
        
        if (deductTransferFee) {
            values.tTransferAmount = values.amount;
        } else {
            // calculate fee
            values.tBurnFee = _calculateTax(values.amount, _taxBurn);
            values.tRewardFee = _calculateTax(values.amount, _taxReward);
            values.tLiquidityFee = _calculateTax(values.amount, _taxLiquidity);
            
            // amount after fee
            values.tTransferAmount = values.amount - values.tBurnFee - values.tRewardFee - values.tLiquidityFee;
        }
        
    }

    function _getRValues(ValuesFromAmount memory values, bool deductTransferFee) view private {
        uint256 currentRate = _getRate();

        values.rAmount = values.amount * currentRate;

        if (deductTransferFee) {
            values.rTransferAmount = values.rAmount;
        } else {
            values.rAmount = values.amount * currentRate;
            values.rBurnFee = values.tBurnFee * currentRate;
            values.rRewardFee = values.tRewardFee * currentRate;
            values.rLiquidityFee = values.tLiquidityFee * currentRate;
            values.rTransferAmount = values.rAmount - values.rBurnFee - values.rRewardFee - values.rLiquidityFee;
        }
        
    }

    function _getRValuesWithoutFee(uint256 amount) private view returns (uint256) {
        uint256 currentRate = _getRate();
        return amount * currentRate;
    }

    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply / tSupply;
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _totalSupply;      
        for (uint256 i = 0; i < _excludedFromReward.length; i++) {
            if (_rBalances[_excludedFromReward[i]] > rSupply || _tBalances[_excludedFromReward[i]] > tSupply) return (_rTotal, _totalSupply);
            rSupply = rSupply - _rBalances[_excludedFromReward[i]];
            tSupply = tSupply - _tBalances[_excludedFromReward[i]];
        }
        if (rSupply < _rTotal / _totalSupply) return (_rTotal, _totalSupply);
        return (rSupply, tSupply);
    }

    function _calculateTax(uint256 amount, uint8 taxRate) private pure returns (uint256) {
        return amount * taxRate / (10**2);
    }


    /*
        Owner functions
    */
    function enableAutoBurn(uint8 taxBurn_) public onlyOwner {
        require(!_autoBurnEnabled, "Auto burn feature is already enabled.");
        _autoBurnEnabled = true;
        setTaxBurn(taxBurn_);
        
        
        emit EnabledAutoBurn(taxBurn_);
    }

    function enableReward(uint8 taxReward_) public onlyOwner {
        require(!_rewardEnabled, "Reward feature is already enabled.");
        _rewardEnabled = true;
        setTaxReward(taxReward_);
        
        
        emit EnabledReward(taxReward_);
    }

    function enableAutoSwapAndLiquify(uint8 taxLiquidity_, address routerAddress, uint256 minTokensBeforeSwap_) public onlyOwner {
        require(!_autoSwapAndLiquifyEnabled, "Auto swap and liquify feature is already enabled.");

        _minTokensBeforeSwap = minTokensBeforeSwap_;

        // init Router
        
        IUniswapV2Router02 uniswapV2Router = IUniswapV2Router02(routerAddress);

        if (IUniswapV2Factory(uniswapV2Router.factory()).getPair(address(this), uniswapV2Router.WETH()) == address(0)) {
            _uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
                .createPair(address(this), uniswapV2Router.WETH());
        } else {
            _uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
                .getPair(address(this), uniswapV2Router.WETH());
        }
        

        _uniswapV2Router = uniswapV2Router;

        // enable
        _autoSwapAndLiquifyEnabled = true;
        setTaxLiquidity(taxLiquidity_);
        
        
        emit EnabledAutoSwapAndLiquify(taxLiquidity_);
    }


    function disableAutoBurn() public onlyOwner {
        require(_autoBurnEnabled, "Auto burn feature is already disabled.");
        setTaxBurn(0);
        _autoBurnEnabled = false;
        
        
        emit DisabledAutoBurn();
    }

    function disableReward() public onlyOwner {
        require(_rewardEnabled, "Reward feature is already disabled.");
        setTaxReward(0);
        _rewardEnabled = false;
        
        
        emit DisabledReward();
    }

    function disableAutoSwapAndLiquify() public onlyOwner {
        require(_autoSwapAndLiquifyEnabled, "Auto swap and liquify feature is already disabled.");
        setTaxLiquidity(0);
        _autoSwapAndLiquifyEnabled = false;
        
        
        emit DisabledAutoSwapAndLiquify();
    }

    function setMinTokensBeforeSwap(uint256 minTokensBeforeSwap_) public onlyOwner {
        require(minTokensBeforeSwap_ < _currentSupply, "minTokensBeforeSwap must be higher than current supply.");
        _minTokensBeforeSwap = minTokensBeforeSwap_;
    }

    function setTaxBurn(uint8 taxBurn_) public onlyOwner {
        require(_autoBurnEnabled, "Auto burn feature must be enabled. Try the EnableAutoBurn function.");
        require(taxBurn_ + _taxReward + _taxLiquidity < 100, "Tax fee too high.");
        uint8 previous = _taxBurn;
        _taxBurn = taxBurn_;
        emit TaxBurnUpdate(previous, _taxBurn);
    }

    function setTaxReward(uint8 taxReward_) public onlyOwner {
        require(_rewardEnabled, "Reward feature must be enabled. Try the EnableReward function.");
        require(_taxBurn + taxReward_ + _taxLiquidity < 100, "Tax fee too high.");
        uint8 previous = _taxReward;
        _taxReward = taxReward_;
        emit TaxRewardUpdate(previous, _taxReward);
    }

    function setTaxLiquidity(uint8 taxLiquidity_) public onlyOwner {
        require(_autoSwapAndLiquifyEnabled, "Auto swap and liquify feature must be enabled. Try the EnableAutoSwapAndLiquify function.");
        require(_taxBurn + _taxReward + taxLiquidity_ < 100, "Tax fee too high.");
        uint8 previous = _taxLiquidity;
        _taxLiquidity = taxLiquidity_;
        emit TaxLiquidityUpdate(previous, _taxLiquidity);
    }

    function _excludeFromFee(address account) private onlyOwner {
        _isExcludedFromFee[account] = true;

        emit ExcludeAccountFromFee(account);
    }

    function _includeInFee(address account) private onlyOwner {
        _isExcludedFromFee[account] = false;
        
        emit IncludeAccountInFee(account);
    }

    function excludeAccountFromReward(address account) public onlyOwner {
        require(!_isExcludedFromReward[account], "Account is already excluded");
        if(_rBalances[account] > 0) {
            _tBalances[account] = tokenFromReflection(_rBalances[account]);
        }
        _isExcludedFromReward[account] = true;
        _excludedFromReward.push(account);
        
        emit ExcludeAccountFromReward(account);
    }

    function includeAccountFromReward(address account) public onlyOwner {
        require(_isExcludedFromReward[account], "Account is already included");
        for (uint256 i = 0; i < _excludedFromReward.length; i++) {
            if (_excludedFromReward[i] == account) {
                _excludedFromReward[i] = _excludedFromReward[_excludedFromReward.length - 1];
                _tBalances[account] = 0;
                _isExcludedFromReward[account] = false;
                _excludedFromReward.pop();
                break;
            }
        }

        emit IncludeAccountInReward(account);
    }
    

}
