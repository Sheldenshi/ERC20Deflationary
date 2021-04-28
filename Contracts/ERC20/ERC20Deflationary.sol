// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../Utils/Context.sol";
import "../Utils/Counters.sol";
import "../Utils/Address.sol";
import "../Utils/Ownable.sol";
import "./IERC20.sol";

contract ERC20Deflationary is Context, IERC20, Ownable {
    using Address for address;

    // balances for address that are included.
    mapping(address => uint256) private _rBalances;
    // balances for address that are excluded.
    mapping(address => uint256) private _tBalances;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) private _isAccExclFromFee;
    // _isAccExclFromRwd vs _exclAccFromRwd?
    mapping(address => bool) private _isAccExclFromRwd;
    address[] private _exclAccFromRwd;

    uint256 private _totalSupply;
    uint256 private _rTotal;
    uint256 private _tFeeTotal;

    // this percent of transaction amount that will be burnt.
    uint8 private _taxBurn;
    // percent of transaction amount that will be redistribute to all holders.
    uint8 private _taxRwd;
    // percent of transaction amount that will be added to the liquidity pool
    uint8 private _taxLiq;

    // TODO: Add decimals to the constructor
    string private _name;
    string private _symbol;

    // account for burning coins.
    // 1 - Set liquidity fee
    // 2 - Set reflection reward
    // 3 - Set burn %
    // 4 - Set X% to go a an arbitrary wallet (e.g. dev wallet)
    address private constant burnAcc =
        address(0x000000000000000000000000000000000000dead00);

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        uint8 taxBurn_,
        uint8 taxRwd_,
        uint8 taxLiq_
    ) {
        require(taxBurn_ + taxRwd_ + taxLiq_ < 100, "Tax fee too high.");

        // Sets the values for `name`, `symbol`, `totalSupply`, `taxBurn`, `taxRwd`, and `taxLiq`.
        _name = name_;
        _symbol = symbol_;
        _taxBurn = taxBurn_;
        _taxRwd = taxRwd_;
        _taxLiq = taxLiq_;
        _totalSupply = totalSupply_;
        _rTotal = (~uint256(0) - (~uint256(0) % _totalSupply));

        // mint
        _rBalances[_msgSender()] = _rTotal;

        // exclude owner and this contract from fee.
        exclAccFromFee(owner(), true);
        exclAccFromFee(address(this), true);

        // exclude owner and burnAcc from receiving rewards.
        // we do want the owner to get rewards don't we?
        exclAccFromReward(owner(), false);
        exclAccFromReward(burnAcc, true);

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

    function taxBurn() public view virtual returns (uint8) {
        return _taxBurn;
    }

    function taxRwd() public view virtual returns (uint8) {
        return _taxRwd;
    }

    function taxLiq() public view virtual returns (uint8) {
        return _taxLiq;
    }

    // Actually this might make more sense
    function setTaxBurn(uint8 taxBurn_) external onlyOwner {
        _taxBurn = taxBurn_;
    }

    function setTaxRwd(uint8 taxRwd_) external onlyOwner {
        _taxRwd = taxRwd_;
    }

    function setTaxLiq(uint8 taxLiq_) external onlyOwner {
        _taxLiq = taxLiq_;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual returns (uint256) {
        if (_isAccExclFromRwd[account]) return _tBalances[account];
        return tokFromRefl(_rBalances[account]);
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount)
        public
        virtual
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender)
        public
        view
        virtual
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount)
        public
        virtual
        returns (bool)
    {
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
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual returns (bool) {
        _transfer(sender, recipient, amount);
        require(
            _allowances[sender][_msgSender()] >= amount,
            "ERC20: transfer amount exceeds allowance"
        );
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()] - amount
        );
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
    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] + addedValue
        );
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
    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(
            currentAllowance >= subtractedValue,
            "ERC20: decreased allowance below zero"
        );
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);
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
        require(account != burnAcc, "ERC20: burn from the burn address");

        uint256 accountBalance = balanceOf(account);
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");

        if (isExcluded(account)) {
            _tBalances[account] -= amount;
        } else {
            _rBalances[account] -= amount;
        }

        _tBalances[burnAcc] += amount;

        // decrease the total coin supply
        _totalSupply -= amount;

        // todo: update _rTotal
        _rTotal -= amount;

        emit Transfer(account, burnAcc, amount);
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
        require(
            currentAllowance >= amount,
            "ERC20: burn amount exceeds allowance"
        );
        _approve(account, _msgSender(), currentAllowance - amount);
        _burn(account, amount);
    }

    function isExcluded(address account) public view returns (bool) {
        return _isAccExclFromRwd[account];
    }

    function totalFees() public view virtual returns (uint256) {
        return _tFeeTotal;
    }

    // todo: figure out what this does.
    // tVals = uint256 tTransferAmount, uint256 tBurnFee, uint256 tRewardFee, uint256 tLiquidityFee
    // rVals = uint256 rAmount, uint256 rTransferAmount, uint256 rBurnFee, uint256 rRewardFee, uint256 rLiquidityFee
    function reflect(uint256 amount) public {
        address sender = _msgSender();
        require(
            !_isAccExclFromRwd[sender],
            "Excluded addresses cannot call this function"
        );
        (uint256[4] memory tVals, uint256[5] memory rVals) = _getVals(amount);
        _rBalances[sender] = _rBalances[sender] - rVals[0];
        _rTotal = _rTotal - rVals[0];
        _tFeeTotal = _tFeeTotal + amount;
    }

    // todo: figure out what this does.
    // Seems to be utterly useless... 🤔
    function reflFromTok(uint256 tAmount, bool deductTransferFee)
        public
        view
        returns (uint256)
    {
        require(tAmount <= _totalSupply, "Amount must be less than supply");
        if (!deductTransferFee) {
            (, uint256[5] memory rVals) = _getVals(amount);
            return rVals[0];
        } else {
            (, uint256 rTransferAmount, , , , , , , ) = _getVals(tAmount);
            return rTransferAmount;
        }
    }

    /**
        Used to figure out the balance of rBalance.
     */
    function tokFromRefl(uint256 rAmount) public view returns (uint256) {
        require(
            rAmount <= _rTotal,
            "Amount must be less than total reflections"
        );
        uint256 currentRate = _getRate();
        return rAmount / currentRate;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    // Functions merged to avoid unecessary code repetitions and shorten the code
    function exclAccFromFee(address account, bool shouldExclude)
        public
        onlyOwner
    {
        if (shouldExclude) {
            _isAccExclFromFee[account] = true;
        } else {
            _isAccExclFromFee[account] = false;
        }
    }

    function exclAccFromReward(address account, bool shouldExclude)
        public
        onlyOwner
    {
        if (shouldExclude) {
            require(
                !_isAccExclFromRwd[account],
                "RFI: Account is already excluded"
            );
            if (_rBalances[account] > 0) {
                _tBalances[account] = tokFromRefl(_rBalances[account]);
            }
            _isAccExclFromRwd[account] = true;
            _exclAccFromRwd.push(account);
        } else {
            require(
                _isAccExclFromRwd[account],
                "RFI: Account is already included"
            );
            for (uint256 i = 0; i < _exclAccFromRwd.length; i++) {
                if (_exclAccFromRwd[i] == account) {
                    _exclAccFromRwd[i] = _exclAccFromRwd[
                        _exclAccFromRwd.length - 1
                    ];
                    _tBalances[account] = 0;
                    _isAccExclFromRwd[account] = false;
                    _exclAccFromRwd.pop();
                    break;
                }
            }
        }
    }

    // TODO
    function _transfert(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        // All transfer funcs have this code in common therefore we avoid code repetitions
        _rBalances[sender] = _rBalances[sender] - rVals[0];
        _rBalances[recipient] = _rBalances[recipient] + rVals[1];

        // Transfer from excluded
        if (_isAccExclFromRwd[sender] && !_isAccExclFromRwd[recipient]) {
            _tBalances[sender] = _tBalances[sender] - amount;
        }
        // Transfer to excluded
        else if (!_isAccExclFromRwd[sender] && _isAccExclFromRwd[recipient]) {
            _tBalances[recipient] = _tBalances[recipient] + tVals[0];
        }
        // Transfer both excluded
        else if (_isAccExclFromRwd[sender] && _isAccExclFromRwd[recipient]) {
            _tBalances[sender] = _tBalances[sender] - amount;
            _tBalances[recipient] = _tBalances[recipient] + tVals[0];
        }

        // logic goes there, if tvalue or rvalue = 0 relevant functions will run but do nothing as require will be added at the start of each functions burn, liquidity and reward
        _afterTokenTransfer(tVals, rVals);

        // All transfer funcs have this code in common therefore we avoid code repetitions
        emit Transfer(sender, recipient, tVals[0]);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if (_isAccExclFromRwd[sender] && !_isAccExclFromRwd[recipient]) {
            _transfertFromExcl(sender, recipient, amount);
        } else if (!_isAccExclFromRwd[sender] && _isAccExclFromRwd[recipient]) {
            _transfertToExcl(sender, recipient, amount);
        } else if (
            !_isAccExclFromRwd[sender] && !_isAccExclFromRwd[recipient]
        ) {
            _transfertStd(sender, recipient, amount);
        } else if (_isAccExclFromRwd[sender] && _isAccExclFromRwd[recipient]) {
            _transfertBothExcl(sender, recipient, amount);
        } else {
            _transfertStd(sender, recipient, amount);
        }
    }

    /**
     * burns
     * reflect
     * add liquidity

        tVals = (uint256 tTransferAmount, uint256 tBurnFee, uint256 tRewardFee, uint256 tLiquidityFee);
        rVals = uint256 rAmount, uint256 rTransferAmount, uint256 rBurnFee, uint256 rRewardFee, uint256 rLiquidityFee;
     */
    function _afterTokenTransfer(
        uint256[4] memory tVals,
        uint256[5] memory rVals
    ) internal virtual {
        // burn

        // reflect
        _reflFee(rVals[2], tVals[3]);

        //
    }

    // tVals = (uint256 tTransferAmount, uint256 tBurnFee, uint256 tRewardFee, uint256 tLiquidityFee);
    // rVals = uint256 rAmount, uint256 rTransferAmount, uint256 rBurnFee, uint256 rRewardFee, uint256 rLiquidityFee;
    function _transfertStd(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        (uint256[4] memory tVals, uint256[5] memory rVals) = _getVals(amount);

        _rBalances[sender] = _rBalances[sender] - rVals[0];
        _rBalances[recipient] = _rBalances[recipient] + rVals[1];

        _afterTokenTransfer(tVals, rVals);

        emit Transfer(sender, recipient, tVals[0]);
    }

    // tVals = (uint256 tTransferAmount, uint256 tBurnFee, uint256 tRewardFee, uint256 tLiquidityFee);
    // rVals = uint256 rAmount, uint256 rTransferAmount, uint256 rBurnFee, uint256 rRewardFee, uint256 rLiquidityFee;
    function _transfertToExcl(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        (uint256[4] memory tVals, uint256[5] memory rVals) = _getVals(amount);

        _rBalances[sender] = _rBalances[sender] - rVals[0];
        _tBalances[recipient] = _tBalances[recipient] + tVals[0];
        _rBalances[recipient] = _rBalances[recipient] + rVals[1];

        _afterTokenTransfer(tVals, rVals);

        emit Transfer(sender, recipient, tVals[0]);
    }

    // tVals = (uint256 tTransferAmount, uint256 tBurnFee, uint256 tRewardFee, uint256 tLiquidityFee);
    // rVals = uint256 rAmount, uint256 rTransferAmount, uint256 rBurnFee, uint256 rRewardFee, uint256 rLiquidityFee;
    function _transfertFromExcl(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        (uint256[4] memory tVals, uint256[5] memory rVals) = _getVals(amount);

        _tBalances[sender] = _tBalances[sender] - amount;
        _rBalances[sender] = _rBalances[sender] - rVals[0];
        _rBalances[recipient] = _rBalances[recipient] + tVals[1];

        _afterTokenTransfer(tVals, rVals);

        emit Transfer(sender, recipient, tVals[0]);
    }

    // tVals = (uint256 tTransferAmount, uint256 tBurnFee, uint256 tRewardFee, uint256 tLiquidityFee);
    // rVals = uint256 rAmount, uint256 rTransferAmount, uint256 rBurnFee, uint256 rRewardFee, uint256 rLiquidityFee;
    function _transfertBothExcl(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        (uint256[4] memory tVals, uint256[5] memory rVals) = _getVals(amount);

        _tBalances[sender] = _tBalances[sender] - amount;
        _rBalances[sender] = _rBalances[sender] - rVals[0];
        _tBalances[recipient] = _tBalances[recipient] + tVals[0];
        _rBalances[recipient] = _rBalances[recipient] + rVals[1];

        _afterTokenTransfer(tVals, rVals);

        emit Transfer(sender, recipient, tVals[0]);
    }

    function _reflFee(uint256 rFee, uint256 tFee) private {
        // to decrease rate thus increase amount reward receive.
        _rTotal = _rTotal - rFee;
        _tFeeTotal = _tFeeTotal + tFee;
    }

    function _getVals(uint256 amount)
        private
        view
        returns (uint256[4] memory, uint256[5] memory)
    {
        uint256[4] memory tVals = _getTVals(amount);
        uint256[5] memory rVals = _getRVals(amount, tVals, _getRate());
        return (tVals, rVals);
    }

    // function _getVals(uint256 amount) private view returns (uint256[5] memory, uint256[4] memory) {
    //     (uint256 tTransferAmount, uint256 tBurnFee, uint256 tRewardFee, uint256 tLiquidityFee) = _getTVals(amount);
    //     (uint256 rAmount, uint256 rTransferAmount, uint256 rBurnFee, uint256 rRewardFee, uint256 rLiquidityFee) = _getRVals(amount, tBurnFee, tRewardFee, tLiquidityFee, _getRate());
    //     return ([rAmount, rTransferAmount, rBurnFee, rRewardFee, rLiquidityFee], [tTransferAmount, tBurnFee, tRewardFee, tLiquidityFee]);
    // }

    function _getTVals(uint256 amount)
        private
        view
        returns (uint256[4] memory)
    {
        // No need for 3 different functions it is just a getting percentage thrice... might as well do it inline...
        uint256 tBurnFee = (amount * _taxBurn) / 100;
        uint256 tRewardFee = (amount * _taxRwd) / 100;
        uint256 tLiquidityFee = (amount * _taxLiq) / 100;

        // amount after fee
        uint256 tTransferAmount =
            amount - tBurnFee - tRewardFee - tLiquidityFee;
        return [tTransferAmount, tBurnFee, tRewardFee, tLiquidityFee];
    }

    // tVals = (uint256 tTransferAmount, uint256 tBurnFee, uint256 tRewardFee, uint256 tLiquidityFee);
    // rVals = uint256 rAmount, uint256 rTransferAmount, uint256 rBurnFee, uint256 rRewardFee, uint256 rLiquidityFee;
    function _getRVals(
        uint256 amount,
        uint256[4] memory tVals,
        uint256 currentRate
    ) private pure returns (uint256[5] memory) {
        uint256 rAmount = amount * currentRate;
        uint256 rBurnFee = tVals[1] * currentRate;
        uint256 rRewardFee = tVals[2] * currentRate;
        uint256 rLiquidityFee = tVals[3] * currentRate;
        uint256 rTransferAmount =
            rAmount - rBurnFee - rRewardFee - rLiquidityFee;
        return [rAmount, rTransferAmount, rBurnFee, rRewardFee, rLiquidityFee];
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply / tSupply;
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _totalSupply;
        for (uint256 i = 0; i < _exclAccFromRwd.length; i++) {
            if (
                _rBalances[_exclAccFromRwd[i]] > rSupply ||
                _tBalances[_exclAccFromRwd[i]] > tSupply
            ) return (_rTotal, _totalSupply);
            rSupply = rSupply - _rBalances[_exclAccFromRwd[i]];
            tSupply = tSupply - _tBalances[_exclAccFromRwd[i]];
        }
        if (rSupply < _rTotal.div(_totalSupply)) return (_rTotal, _totalSupply);
        return (rSupply, tSupply);
    }
}
