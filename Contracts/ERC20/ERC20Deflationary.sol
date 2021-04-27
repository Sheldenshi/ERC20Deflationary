// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../Utils/Context.sol";
import "../Utils/SafeMath.sol";
import "../Utils/Counters.sol";
import "../Utils/Address.sol";
import "../Utils/Ownable.sol";
import "./IERC20.sol";


contract ERC20Deflationary is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    // balances for address that are included.
    mapping (address => uint256) private _rBalances;
    // balances for address that are excluded.
    mapping (address => uint256) private _tBalances;
    mapping (address => mapping (address => uint256)) private _allowances;

    mapping(address => bool) private _isExcludedFromFee;
    mapping (address => bool) private _isExcludedFromReward;
    address[] private _excludedFromReward;
   
    uint256 private  _totalSupply;
    uint256 private _rTotal;
    uint256 private _tFeeTotal;

    // this percent of transaction amount that will be burnt.
    uint8 private _taxFeeBurn;
    // percent of transaction amount that will be redistribute to all holders.
    uint8 private _taxFeeReward;
    // percent of transaction amount that will be added to the liquidity pool
    uint8 private _taxFeeLiquidity; 

    string private _name;
    string private _symbol;

    // account for burning coins.
    // 1 - Set liquidity fee
    // 2 - Set reflection reward
    // 3 - Set burn %
    // 4 - Set X% to go a an arbitrary wallet (e.g. dev wallet) 
    address private constant burnAccount = address(0x000000000000000000000000000000000000dead00);

    constructor (string memory name_, string memory symbol_, uint256 totalSupply_,
        uint8 taxFeeBurn_, uint8 taxFeeReward_, uint8 taxFeeLiquidity_) {
        
        require(taxFeeBurn_ + taxFeeReward_ + taxFeeLiquidity_ < 100, "Tax fee too high.");
        
        // Sets the values for `name`, `symbol`, `totalSupply`, `taxFeeBurn`, `taxFeeReward`, and `taxFeeLiquidity`.
        _name = name_;
        _symbol = symbol_;
        _taxFeeBurn = taxFeeBurn_;
        _taxFeeReward = taxFeeReward_;
        _taxFeeLiquidity = taxFeeLiquidity_;
        _totalSupply = totalSupply_;
        _rTotal = (~uint256(0) - (~uint256(0) % _totalSupply));

        // mint
        _rBalances[_msgSender()] = _rTotal;

        // exclude owner and this contract from fee.
        excludeFromFee(owner());
        excludeFromFee(address(this));

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
        return 9;
    }

    function taxFeeBurn() public view virtual returns (uint8) {
        return _taxFeeBurn;
    }

    function taxFeeReward() public view virtual returns (uint8) {
        return _taxFeeReward;
    }

    function taxFeeLiquidity() public view virtual returns (uint8) {
        return _taxFeeLiquidity;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
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
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()]- amount, "ERC20: transfer amount exceeds allowance");
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
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender]- subtractedValue, "ERC20: decreased allowance below zero");
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

        if (isExcluded(account)) {
            _tBalances[account] -= amount;
        } else {
            _rBalances[account] -= amount;
        }

        _tBalances[burnAccount] += amount;

        // decrease the total coin supply
        _totalSupply -= amount;

        // todo: update _rTotal
        _rTotal -= amount;

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

    // todo: figure out what this does.
    function reflect(uint256 tAmount) public {
        address sender = _msgSender();
        require(!_isExcludedFromReward[sender], "Excluded addresses cannot call this function");
        (uint256 rAmount,,,,,,,,) = _getValues(tAmount);
        _rBalances[sender] = _rBalances[sender] - rAmount;
        _rTotal = _rTotal- rAmount;
        _tFeeTotal = _tFeeTotal+tAmount;
    }

    // todo: figure out what this does.
    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) public view returns(uint256) {
        require(tAmount <= _totalSupply, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount,,,,,,,,) = _getValues(tAmount);
            return rAmount;
        } else {
            (,uint256 rTransferAmount,,,,,,,) = _getValues(tAmount);
            return rTransferAmount;
        }
    }

    /**
        Used to figure out the balance of rBalance.
     */
    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return rAmount.div(currentRate);
    }

    // suggestion: merge
    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
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
        require(amount > 0, "Transfer amount must be greater than zero");

        if (_isExcludedFromReward[sender] && !_isExcludedFromReward[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcludedFromReward[sender] && _isExcludedFromReward[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (!_isExcludedFromReward[sender] && !_isExcludedFromReward[recipient]) {
            _transferStandard(sender, recipient, amount);
        } else if (_isExcludedFromReward[sender] && _isExcludedFromReward[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }
    }


    /**
     * burns
     * reflect
     * add liquidity
     */
    function _afterTokenTransfer(uint256[5] memory rValues, uint256[4] memory tValues) internal virtual {
        (uint256 tTransferAmount, uint256 tBurnFee, uint256 tRewardFee, uint256 tLiquidityFee) = tValues;
        (uint256 rAmount, uint256 rTransferAmount, uint256 rBurnFee, uint256 rRewardFee, uint256 rLiquidityFee) = rValues;
        // burn 

        // reflect
        _reflectFee(rRewardFee, tRewardFee);

        // 
     }

 
    function _transferStandard(address sender, address recipient, uint256 amount) private {
        (uint256[5] memory rValues, uint256[4] memory tValues) = _getValues(amount);
        (uint256 tTransferAmount, uint256 tBurnFee, uint256 tRewardFee, uint256 tLiquidityFee) = tValues;
        (uint256 rAmount, uint256 rTransferAmount, uint256 rBurnFee, uint256 rRewardFee, uint256 rLiquidityFee) = rValues;
        _rBalances[sender] = _rBalances[sender] - rAmount;
        _rBalances[recipient] = _rBalances[recipient] + rTransferAmount;   
        
        _afterTokenTransfer(tValues, rValues);

        emit Transfer(sender, recipient, tValues['transferAmount']);
    }

    function _transferToExcluded(address sender, address recipient, uint256 amount) private {
        (uint256[5] memory rValues, uint256[4] memory tValues) = _getValues(amount);
        (uint256 tTransferAmount, uint256 tBurnFee, uint256 tRewardFee, uint256 tLiquidityFee) = tValues;
        (uint256 rAmount, uint256 rTransferAmount, uint256 rBurnFee, uint256 rRewardFee, uint256 rLiquidityFee) = rValues;
        
        _rBalances[sender] = _rBalances[sender] - rAmount;
        _tBalances[recipient] = _tBalances[recipient] + tTransferAmount;
        _rBalances[recipient] = _rBalances[recipient] + rTransferAmount;    

        _afterTokenTransfer(tValues, rValues);
        
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(address sender, address recipient, uint256 amount) private {
        (uint256[5] memory rValues, uint256[4] memory tValues) = _getValues(amount);
        (uint256 tTransferAmount, uint256 tBurnFee, uint256 tRewardFee, uint256 tLiquidityFee) = tValues;
        (uint256 rAmount, uint256 rTransferAmount, uint256 rBurnFee, uint256 rRewardFee, uint256 rLiquidityFee) = rValues;
        
        _tBalances[sender] = _tBalances[sender] - amount;
        _rBalances[sender] = _rBalances[sender] - rAmount;
        _rBalances[recipient] = _rBalances[recipient] + rTransferAmount;   

        _afterTokenTransfer(tValues, rValues);

        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferBothExcluded(address sender, address recipient, uint256 amount) private {
        (uint256[5] memory rValues, uint256[4] memory tValues) = _getValues(amount);
        (uint256 tTransferAmount, uint256 tBurnFee, uint256 tRewardFee, uint256 tLiquidityFee) = tValues;
        (uint256 rAmount, uint256 rTransferAmount, uint256 rBurnFee, uint256 rRewardFee, uint256 rLiquidityFee) = rValues;

        _tBalances[sender] = _tBalances[sender] - amount;
        _rBalances[sender] = _rBalances[sender] - rAmount;
        _tBalances[recipient] = _tBalances[recipient] + tTransferAmount;
        _rBalances[recipient] = _rBalances[recipient] + rTransferAmount;        

        _afterTokenTransfer(tValues, rValues);
        
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        // to decrease rate thus increase amount reward receive.
        _rTotal = _rTotal - rFee;
        _tFeeTotal = _tFeeTotal + tFee;
    }

    function _getValues(uint256 amount) private view returns (uint256[4] memory, uint256[5] memory) {
        uint256[4] memory tValues = _getTValues(amount);
        uint256[5] memory rValues = _getRValues(amount, tValues, _getRate());
        return (tValues, rValues);
    }
    // function _getValues(uint256 amount) private view returns (uint256[5] memory, uint256[4] memory) {
    //     (uint256 tTransferAmount, uint256 tBurnFee, uint256 tRewardFee, uint256 tLiquidityFee) = _getTValues(amount);
    //     (uint256 rAmount, uint256 rTransferAmount, uint256 rBurnFee, uint256 rRewardFee, uint256 rLiquidityFee) = _getRValues(amount, tBurnFee, tRewardFee, tLiquidityFee, _getRate());
    //     return ([rAmount, rTransferAmount, rBurnFee, rRewardFee, rLiquidityFee], [tTransferAmount, tBurnFee, tRewardFee, tLiquidityFee]);
    // }

    function _getTValues(uint256 amount) private view returns (uint256[4] memory) {
        // calculate fee
        uint256 tBurnFee = _calculateTaxFeeBurn(amount);
        uint256 tRewardFee = _calculateTaxFeeReward(amount);
        uint256 tLiquidityFee = _calculateTaxFeeLiquidity(amount);
        
        // amount after fee
        uint256 tTransferAmount = amount - tBurnFee - tRewardFee - tLiquidityFee;
        return [tTransferAmount, tBurnFee, tRewardFee, tLiquidityFee];
    }

    function _getRValues(uint256 amount, uint256[4] memory tValues, uint256 currentRate) private pure returns (uint256[5] memory) {
        (uint256 tTransferAmount, uint256 tBurnFee, uint256 tRewardFee, uint256 tLiquidityFee) = tValues;
        uint256 rAmount = amount * currentRate;
        uint256 rBurnFee = tBurnFee * currentRate;
        uint256 rRewardFee = tRewardFee * currentRate;
        uint256 rLiquidityFee = tLiquidityFee * currentRate;
        uint256 rTransferAmount = rAmount - rBurnFee - rRewardFee - rLiquidityFee;
        return [rAmount, rTransferAmount, rBurnFee, rRewardFee, rLiquidityFee];
    }

    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _totalSupply;      
        for (uint256 i = 0; i < _excludedFromReward.length; i++) {
            if (_rBalances[_excludedFromReward[i]] > rSupply || _tBalances[_excludedFromReward[i]] > tSupply) return (_rTotal, _totalSupply);
            rSupply = rSupply - _rBalances[_excludedFromReward[i]];
            tSupply = tSupply - _tBalances[_excludedFromReward[i]];
        }
        if (rSupply < _rTotal.div(_totalSupply)) return (_rTotal, _totalSupply);
        return (rSupply, tSupply);
    }

    function setTaxFeeBurn(uint8 taxFeeBurn_) external onlyOwner {
        _taxFeeBurn = taxFeeBurn_;
    }

    function setTaxFeeReward(uint8 taxFeeReward_) external onlyOwner {
        _taxFeeReward = taxFeeReward_;
    }

    function setTaxFeeLiquidity(uint8 taxFeeLiquidity_) external onlyOwner {
        _taxFeeLiquidity = taxFeeLiquidity_;
    }

    function _calculateTaxFeeBurn(uint256 amount) private view returns (uint256) {
        return amount*_taxFeeBurn.div(10**2);
    }

    function _calculateTaxFeeReward(uint256 amount) private view returns (uint256) {
        return amount*_taxFeeReward.div(10**2);
    }

    function _calculateTaxFeeLiquidity(uint256 amount) private view returns (uint256) {
        return amount*_taxFeeLiquidity.div(10**2);
    }

}