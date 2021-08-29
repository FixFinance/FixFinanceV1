// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../interfaces/IFixCapitalPool.sol";
import "../../interfaces/IWrapper.sol";
import "../../interfaces/IZeroCouponBond.sol";
import "../../libraries/SafeMath.sol";

contract ZeroCouponBond is IZeroCouponBond {
    using SafeMath for uint;

	IFixCapitalPool immutable fcp;
	IWrapper immutable wrapper;

    string public override name;
    string public override symbol;
	uint8 public immutable override decimals;
    uint public immutable override maturity;

    mapping(address => mapping(address => uint256)) public override allowance;

	constructor(address _wrapperAddress, address _fixCapitalPoolAddress, uint _maturity) public {
		IWrapper _wrapper = IWrapper(_wrapperAddress);
		decimals = _wrapper.decimals();
		symbol = string(abi.encodePacked(_wrapper.symbol(),'zcb'));
		name = string(abi.encodePacked(_wrapper.name(),' zero coupon bond'));
		wrapper = _wrapper;
        fcp = IFixCapitalPool(_fixCapitalPoolAddress);
        maturity = _maturity;
	}

    function lastUpdate() external view override returns(uint) {
        return wrapper.lastUpdate();
    }

	function balanceOf(address _owner) public view override returns (uint balance) {
		balance = fcp.totalBalanceZCB(_owner);
	}

    function transfer(address _to, uint256 _value) public override returns (bool success) {
    	fcp.transferZCB(msg.sender, _to, _value);

        emit Transfer(msg.sender, _to, _value);

        return true;
    }

    function approve(address _spender, uint256 _value) public override returns (bool success) {
        allowance[msg.sender][_spender] = _value;

        emit Approval(msg.sender, _spender, _value);

        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public override returns (bool success) {
        require(_value <= allowance[_from][msg.sender]);

    	fcp.transferZCB(_from, _to, _value);

        allowance[_from][msg.sender] -= _value;

        emit Transfer(_from, _to, _value);

        return true;
    }

    function totalSupply() public view override returns (uint _supply) {
        _supply = wrapper.balanceOf(address(fcp));
        IFixCapitalPool _fcp = fcp;
        if (_fcp.inPayoutPhase()) {
            _supply = _supply.mul(_fcp.maturityConversionRate()) / (1 ether);
        }
        else {
            _supply = wrapper.WrappedAmtToUnitAmt_RoundDown(_supply);
        }
    }

    /*
        @Description: the FixCapitalPool contract can decrement approvals by calling this function

        @param address _owner: the owner of the funds that are approved
        @param address _spender: the spender of the funds that are approved
        @param uint _amount: the amount by which to decrement the allowance
    */
    function decrementAllowance(address _owner, address _spender, uint _amount) external override {
        require(msg.sender == address(fcp));
        require(allowance[_owner][_spender] >= _amount);
        allowance[_owner][_spender] -= _amount;
    }

    /*
        @Description: the FixCapitalPool contract can set allowances

        @param address _owner: the owner of the funds that are approved
        @param address _spender: the spender of the funds that are approved
        @param uint _allowance: the new allowance amount
    */
    function setAllowance(address _owner, address _spender, uint _allowance) external override {
        require(msg.sender == address(fcp));
        allowance[_owner][_spender] = _allowance;

        emit Approval(_owner, _spender, _allowance);
    }

    /*
        @Description: get the address of this contract's corresponding FixCapitalPool contract
    */
    function FixCapitalPoolAddress() external view override returns (address) {
        return address(fcp);
    }

    /*
        @Description: get the address of the IWrapper contract corresponding to this ZCB
    */
    function WrapperAddress() external view override returns (address) {
        return address(wrapper);
    }
}