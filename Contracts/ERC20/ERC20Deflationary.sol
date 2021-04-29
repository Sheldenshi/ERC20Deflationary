// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "../Utils/Context.sol";
import "../Utils/Ownable.sol";
import "./IERC20.sol";


contract ERC20Deflationary is Context, IERC20, Ownable {
    // balances for address that are included.
    mapping (address => uint256) private _rBalances;
    // balances for address that are excluded.
    mapping (address => uint256) private _tBalances;
    mapping (address => mapping (address => uint256)) private _allowances;

    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => bool) private _isExcludedFromReward;

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

    string private _name;
    string private _symbol;

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

        // exclude owner and burnAccount from receiving rewards.
        excludeAccountFromReward(owner());
        excludeAccountFromReward(burnAccount);
        
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
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender]+addedValue);
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
    function distribute(uint256 amount) public {
        address sender = _msgSender();
        require(!_isExcludedFromReward[sender], "Excluded addresses cannot call this function");
        ValuesFromAmount memory values = _getValues(amount, false);
        _rBalances[sender] = _rBalances[sender] - values.rAmount;
        _rTotal = _rTotal - values.rAmount;
        _tFeeTotal = _tFeeTotal + amount ;
    }

    // todo: figure out what this does.
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

    
    function _excludeFromFee(address account) private onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function _includeInFee(address account) private onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function excludeAccountFromReward(address account) public onlyOwner {
        require(!_isExcludedFromReward[account], "Account is already excluded");
        if(_rBalances[account] > 0) {
            _tBalances[account] = tokenFromReflection(_rBalances[account]);
        }
        _isExcludedFromReward[account] = true;
        _excludedFromReward.push(account);
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
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) private {
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

        _afterTokenTransfer(values);

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
        burn(values.tBurnFee);
        
        // reflect
        _distributeFee(values.rRewardFee, values.tRewardFee);

        // todo: add liquidity
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

        _afterTokenTransfer(values);
        
        emit Transfer(sender, recipient, values.tTransferAmount);
    }

    
    function _transferFromExcluded(address sender, address recipient, ValuesFromAmount memory values) private {
        
        _tBalances[sender] = _tBalances[sender] - values.amount;
        _rBalances[sender] = _rBalances[sender] - values.rAmount;
        _rBalances[recipient] = _rBalances[recipient] + values.rTransferAmount;   

        _afterTokenTransfer(values);

        emit Transfer(sender, recipient, values.tTransferAmount);
    }

    
    function _transferBothExcluded(address sender, address recipient, ValuesFromAmount memory values) private {

        _tBalances[sender] = _tBalances[sender] - values.amount;
        _rBalances[sender] = _rBalances[sender] - values.rAmount;
        _tBalances[recipient] = _tBalances[recipient] + values.tTransferAmount;
        _rBalances[recipient] = _rBalances[recipient] + values.rTransferAmount;        

        _afterTokenTransfer(values);
        
        emit Transfer(sender, recipient, values.tTransferAmount);
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

    function setTaxFeeBurn(uint8 taxFeeBurn_) public onlyOwner {
        require(taxFeeBurn_ + _taxReward + _taxLiquidity < 100, "Tax fee too high.");
        _taxBurn = taxFeeBurn_;
    }

    function setTaxFeeReward(uint8 taxFeeReward_) public onlyOwner {
        require(_taxBurn + taxFeeReward_ + _taxLiquidity < 100, "Tax fee too high.");
        _taxReward = taxFeeReward_;
    }

    function setTaxFeeLiquidity(uint8 taxFeeLiquidity_) public onlyOwner {
        require(_taxBurn + _taxReward + taxFeeLiquidity_ < 100, "Tax fee too high.");
        _taxLiquidity = taxFeeLiquidity_;
    }

    function _calculateTax(uint256 amount, uint8 taxRate) private pure returns (uint256) {
        return amount * taxRate / (10**2);
    }

}
