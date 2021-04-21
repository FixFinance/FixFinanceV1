pragma solidity >=0.6.0;

import "./interfaces/ICapitalHandler.sol";
import "./interfaces/IWrapper.sol";
import "./interfaces/IZeroCouponBond.sol";

contract ZeroCouponBond is IZeroCouponBond {

	ICapitalHandler immutable ch;
	IWrapper immutable wrapper;

    string public override name;
    string public override symbol;
	uint8 public immutable override decimals;
    uint public immutable override maturity;

    mapping(address => mapping(address => uint256)) public override allowance;

	constructor(address _wrapperAddress, address _capitalHandlerAddress, uint _maturity) public {
		IWrapper _wrapper = IWrapper(_wrapperAddress);
		decimals = _wrapper.decimals();
		symbol = string(abi.encodePacked(_wrapper.symbol(),'zcb'));
		name = string(abi.encodePacked(_wrapper.name(),' zero coupon bond'));
		wrapper = _wrapper;
        ch = ICapitalHandler(_capitalHandlerAddress);
        maturity = _maturity;
	}

	function balanceOf(address _owner) public view override returns (uint balance) {
		balance = ch.totalBalanceZCB(_owner);
	}

    function transfer(address _to, uint256 _value) public override returns (bool success) {
    	ch.transferZCB(msg.sender, _to, _value);

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

    	ch.transferZCB(_from, _to, _value);

        allowance[_from][msg.sender] -= _value;

        emit Transfer(_from, _to, _value);

        return true;
    }

    function totalSupply() public view override returns (uint _supply) {
    	_supply = wrapper.WrappedAmtToUnitAmt_RoundDown(wrapper.balanceOf(address(this)));
    }

    /*
        @Description: the CapitalHandler contract can decrement approvals by calling this function

        @param address _owner: the owner of the funds that are approved
        @param address _spender: the spender of the funds that are approved
        @param uint _amount: the amount by which to decrement the allowance
    */
    function decrementAllowance(address _owner, address _spender, uint _amount) external override {
        require(msg.sender == address(ch));
        require(allowance[_owner][_spender] >= _amount);
        allowance[_owner][_spender] -= _amount;
    }

    /*
        @Description: get the address of this contract's corresponding CapitalHandler contract
    */
    function CapitalHandlerAddress() external view override returns (address) {
        return address(ch);
    }
}