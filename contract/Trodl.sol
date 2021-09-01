// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.1.0/contracts/GSN/Context.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.1.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.1.0/contracts/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.1.0/contracts/utils/Address.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.1.0/contracts/access/Ownable.sol";

contract Trodl is Context, IERC20, Ownable {
    
    using SafeMath for uint256;
    using Address for address;

    mapping (address => uint256) private _refOwned;
    mapping (address => uint256) private _tokOwned;
    mapping (address => mapping (address => uint256)) private _allowances;

    // _isExempted from transaction rewards
    mapping (address => bool) private _isExempted;
    address[] private _exempted;

    uint256 private constant MAX = ~uint256(0);
    uint256 private _tokTotalSupply = 600 * 10**6 * 10**18;
    uint256 private _refTotalSupply = (MAX - (MAX % _tokTotalSupply));
    uint256 private _tokFeeTotal;
    uint256 private _tokBurned;

    string private _name = 'Trodl';
    string private _symbol = 'TRO';
    uint8 private _decimals = 18;

    constructor () public {
        _refOwned[_msgSender()] = _refTotalSupply;
        emit Transfer(address(0), _msgSender(), _tokTotalSupply);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tokTotalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExempted[account]) return _tokOwned[account];
        return tokenFromReflection(_refOwned[account]);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    function isExempted(address account) public view returns (bool) {
        return _isExempted[account];
    }

    function totalFees() public view returns (uint256) {
        return _tokFeeTotal;
    }

    function totalBurned() public view returns (uint256) {
        return _tokBurned;
    }

    function distribute(uint256 tokAmount, bool burn) public {
        address sender = _msgSender();
        require(!_isExempted[sender], "Trodl: Exempted addresses not allowed");
        if (!burn) {
            (uint256 refAmount,,,,) = _getValues(tokAmount);
            _refOwned[sender] = _refOwned[sender].sub(refAmount);
            _refTotalSupply = _refTotalSupply.sub(refAmount);
            _tokFeeTotal = _tokFeeTotal.add(tokAmount);
        } else {
            (uint256 refAmount,,,,) = _getValues(tokAmount);
            _refOwned[sender] = _refOwned[sender].sub(refAmount);    
            uint256 tokAmountHalf = tokAmount.div(2); 
            _refTotalSupply = _refTotalSupply.sub(refAmount);
            _tokFeeTotal = _tokFeeTotal.add(tokAmountHalf);
            _tokBurned = _tokBurned.add(tokAmountHalf);
        }
    }

    function burn(uint256 tokAmount) public {
        address sender = _msgSender();
        require(!_isExempted[sender], "Trodl: Exempted addresses cannot burn");
        (uint256 refAmount,,,,) = _getValues(tokAmount);
        _refOwned[sender] = _refOwned[sender].sub(refAmount);
        _refTotalSupply = _refTotalSupply.sub(refAmount);
        _tokBurned = _tokBurned.add(tokAmount);
    }

    function reflectionFromToken(uint256 tokAmount, bool deductTransferFeeAndBurn) public view returns(uint256) {
        require(tokAmount <= (_tokTotalSupply + _tokFeeTotal), "Trodl: Amount must be less than supply");
        if (!deductTransferFeeAndBurn) {
            (uint256 refAmount,,,,) = _getValues(tokAmount);
            return refAmount;
        } else {
            (,uint256 refTransferAmount,,,) = _getValues(tokAmount);
            return refTransferAmount;
        }
    }

    function tokenFromReflection(uint256 refAmount) public view returns(uint256) {
        require(refAmount <= _refTotalSupply, "Trodl: Amount must be less than total reflections");
        if(refAmount == 0) return 0;
        uint256 currentRate =  _getRate();
        return refAmount.div(currentRate);
    }

    function exemptAccount(address account) external onlyOwner() {
        require(!_isExempted[account], "Trodl: Account is already exempted");
        if(_refOwned[account] > 0) {
            _tokOwned[account] = tokenFromReflection(_refOwned[account]);
        }
        _isExempted[account] = true;
        _exempted.push(account);
    }
    
    function obligateAccount(address account) external onlyOwner() {
        require(_isExempted[account], "Trodl: Account is not Exempted");
        
        for (uint256 i = 0; i < _exempted.length; i++) {
            if (_exempted[i] == account) {
                uint256 _rBalance = reflectionFromToken(_tokOwned[account], false);
                _refTotalSupply = _refTotalSupply.sub(_refOwned[account].sub(_rBalance));
                _refOwned[account] = _rBalance;
                _tokOwned[account] = 0;
                _isExempted[account] = false;
                _exempted[i] = _exempted[_exempted.length - 1];               
                _exempted.pop();
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
        require(amount > 0, "Trodl: Transfer amount must be greater than zero");
        if (_isExempted[sender] && !_isExempted[recipient]) {
            _transferFromExempted(sender, recipient, amount);
        } else if (!_isExempted[sender] && _isExempted[recipient]) {
            _transferToExempted(sender, recipient, amount);
        } else if (_isExempted[sender] && _isExempted[recipient]) {
            _transferBothExempted(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }
    }

    function _transferStandard(address sender, address recipient, uint256 tokAmount) private {
        (uint256 refAmount, uint256 refTransferAmount, uint256 refFeeHalf, uint256 tokTransferAmount, uint256 tokFeeHalf) = _getValues(tokAmount);
        _refOwned[sender] = _refOwned[sender].sub(refAmount);
        _refOwned[recipient] = _refOwned[recipient].add(refTransferAmount);
        _distributeFee(refFeeHalf, tokFeeHalf);
        emit Transfer(sender, recipient, tokTransferAmount);
    }

    function _transferToExempted(address sender, address recipient, uint256 tokAmount) private {
        (uint256 refAmount, uint256 refTransferAmount, uint256 refFeeHalf, uint256 tokTransferAmount, uint256 tokFeeHalf) = _getValues(tokAmount);
        _refOwned[sender] = _refOwned[sender].sub(refAmount);
        _tokOwned[recipient] = _tokOwned[recipient].add(tokTransferAmount);
        _refOwned[recipient] = _refOwned[recipient].add(refTransferAmount);           
        _distributeFee(refFeeHalf, tokFeeHalf);
        emit Transfer(sender, recipient, tokTransferAmount);
    }

    function _transferFromExempted(address sender, address recipient, uint256 tokAmount) private {
        (uint256 refAmount, uint256 refTransferAmount, uint256 refFeeHalf, uint256 tokTransferAmount,uint256 tokFeeHalf) = _getValues(tokAmount);
        _tokOwned[sender] = _tokOwned[sender].sub(tokAmount);
        _refOwned[sender] = _refOwned[sender].sub(refAmount);
        _refOwned[recipient] = _refOwned[recipient].add(refTransferAmount);   
        _distributeFee(refFeeHalf, tokFeeHalf);
        emit Transfer(sender, recipient, tokTransferAmount);
    }

    function _transferBothExempted(address sender, address recipient, uint256 tokAmount) private {
        (uint256 refAmount, uint256 refTransferAmount, uint256 refFeeHalf, uint256 tokTransferAmount, uint256 tokFeeHalf) = _getValues(tokAmount);
        _tokOwned[sender] = _tokOwned[sender].sub(tokAmount);
        _refOwned[sender] = _refOwned[sender].sub(refAmount);
        _tokOwned[recipient] = _tokOwned[recipient].add(tokTransferAmount);
        _refOwned[recipient] = _refOwned[recipient].add(refTransferAmount);        
        _distributeFee(refFeeHalf, tokFeeHalf);
        emit Transfer(sender, recipient, tokTransferAmount);
    }

    function _distributeFee(uint256 refFeeHalf, uint256 tokFeeHalf) private {
        _refTotalSupply = _refTotalSupply.sub(refFeeHalf);
        _tokFeeTotal = _tokFeeTotal.add(tokFeeHalf);
        _tokBurned = _tokBurned.add(tokFeeHalf);
        _tokTotalSupply = _tokTotalSupply.sub(tokFeeHalf);
        
    }

    function _getValues(uint256 tokAmount) private view returns (uint256, uint256, uint256, uint256, uint256) {
        (uint256 tokTransferAmount, uint256 tFee, uint256 tokFeeHalf) = _getTValues(tokAmount);
        uint256 currentRate =  _getRate();
        (uint256 refAmount, uint256 refTransferAmount, uint256 refFeeHalf) = _getRValues(tokAmount, tFee, tokFeeHalf, currentRate);
        return (refAmount, refTransferAmount, refFeeHalf, tokTransferAmount, tokFeeHalf);
    }

    function _getTValues(uint256 tokAmount) private pure returns (uint256, uint256, uint256) {
        uint256 tokFeeHalf = tokAmount.div(200);
        uint256 tFee = tokFeeHalf.mul(2);
        uint256 tokTransferAmount = tokAmount.sub(tFee);       
        return (tokTransferAmount, tFee, tokFeeHalf);
    }

    function _getRValues(uint256 tokAmount, uint256 tFee, uint256 tokFeeHalf, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
        uint256 refAmount = tokAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 refFeeHalf = tokFeeHalf.mul(currentRate);
        uint256 refTransferAmount = refAmount.sub(rFee);
        return (refAmount, refTransferAmount, refFeeHalf);
    }

    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _refTotalSupply;
        uint256 tTotal = _tokTotalSupply.add( _tokFeeTotal);    
        uint256 tSupply = tTotal;  
        for (uint256 i = 0; i < _exempted.length; i++) {
            if (_refOwned[_exempted[i]] > rSupply || _tokOwned[_exempted[i]] > tSupply) return (_refTotalSupply, tTotal);
            rSupply = rSupply.sub(_refOwned[_exempted[i]]);
            tSupply = tSupply.sub(_tokOwned[_exempted[i]]);
        }
        if (rSupply < _refTotalSupply.div(tTotal)) return (_refTotalSupply, tTotal);
        return (rSupply, tSupply);
    }
}