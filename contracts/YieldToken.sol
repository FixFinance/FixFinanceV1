pragma solidity >=0.6.5 <0.7.0;
import "./interfaces/ICapitalHandler.sol";
import "./interfaces/IWrapper.sol";
import "./interfaces/IYieldToken.sol";
import "./interfaces/IERC20.sol";
import "./libraries/SafeMath.sol";

contract YieldToken is IYieldToken {

	ICapitalHandler ch;
	IWrapper wrapper;

    string public override name;
    string public override symbol;
	uint8 public override decimals;

    mapping(address => mapping(address => uint256)) public override allowance;

	constructor(address _wrapperAddress, address _capitalHandler) public {
		IWrapper _wrapper = IWrapper(_wrapperAddress);
		decimals = _wrapper.decimals();
		symbol = string(abi.encodePacked(_wrapper.symbol(),'yt'));
		name = string(abi.encodePacked(_wrapper.name(),' yield token'));
		wrapper = _wrapper;
		ch = ICapitalHandler(_capitalHandler);
	}

	function totalSupply() public view override returns (uint _supply){
		_supply = wrapper.balanceOf(address(ch));
	}

    function balanceOf(address _owner) public view override returns (uint _amount) {
    	_amount = ch.balanceYield(_owner);
    }

    function transfer(address _to, uint256 _value) public override returns (bool success) {
        ch.transferYield(msg.sender, _to, _value);

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

        ch.transferYield(_from, _to, _value);

        allowance[_from][msg.sender] -= _value;

        emit Transfer(_from, _to, _value);

        return true;
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