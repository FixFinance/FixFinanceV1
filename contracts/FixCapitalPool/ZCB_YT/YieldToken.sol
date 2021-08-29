// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "../../interfaces/IFixCapitalPool.sol";
import "../../interfaces/IWrapper.sol";
import "../../interfaces/IYieldToken.sol";
import "../../interfaces/IERC20.sol";
import "../../libraries/SafeMath.sol";

contract YieldToken is IYieldToken {

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
		symbol = string(abi.encodePacked(_wrapper.symbol(),'yt'));
		name = string(abi.encodePacked(_wrapper.name(),' yield token'));
		wrapper = _wrapper;
        fcp = IFixCapitalPool(_fixCapitalPoolAddress);
        maturity = _maturity;
	}

    function lastUpdate() external view override returns(uint) {
        return wrapper.lastUpdate();
    }

	function totalSupply() public view override returns (uint _supply){
		_supply = wrapper.balanceOf(address(fcp));
	}

    function balanceOf(address _owner) public view override returns (uint _amount) {
    	_amount = fcp.balanceYield(_owner);
    }

    function transfer(address _to, uint256 _value) public override returns (bool success) {
        fcp.transferYT(msg.sender, _to, _value);

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

        fcp.transferYT(_from, _to, _value);

        allowance[_from][msg.sender] -= _value;

        emit Transfer(_from, _to, _value);

        return true;
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
        @Description: get the address of the IWrapper contract corresponding to this YT
    */
    function WrapperAddress() external view override returns (address) {
        return address(wrapper);
    }

    /*
        Here we repeat all of the ERC20 functions except we denominate the values in underlying asset rather
        than wrapped asset amounts and add _2 at the end of the names. We also add bool _roundUp as a parameter
    */

    function balanceOf_2(address _owner, bool _roundUp) external view override returns (uint) {
        return _roundUp ? wrapper.WrappedAmtToUnitAmt_RoundUp(balanceOf(_owner)) : wrapper.WrappedAmtToUnitAmt_RoundDown(balanceOf(_owner));
    }

    //_value denominated in unit not in wrapped
    function transfer_2(address _to, uint256 _value, bool _roundUp) external override {
        transfer(_to, _roundUp ? wrapper.UnitAmtToWrappedAmt_RoundUp(_value) : wrapper.UnitAmtToWrappedAmt_RoundDown(_value));
    }

    //_value denominated in unit not in wrapped
    function approve_2(address _spender, uint256 _value, bool _roundUp) external override {
        approve(_spender, _roundUp ? wrapper.UnitAmtToWrappedAmt_RoundUp(_value) : wrapper.UnitAmtToWrappedAmt_RoundDown(_value));        
    }

    //_value denominated in unit not in wrapped
    function transferFrom_2(address _from, address _to, uint256 _value, bool _roundUp) external override {
        transferFrom(_from, _to, _roundUp ? wrapper.UnitAmtToWrappedAmt_RoundUp(_value) : wrapper.UnitAmtToWrappedAmt_RoundDown(_value));
    }

}