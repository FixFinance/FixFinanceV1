// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "../interfaces/ICToken.sol";

contract dummyCToken is ICToken {

	uint8 public override decimals;

	uint public override totalSupply;

	uint public override exchangeRateStored;

	mapping(address => uint) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    string public override name = "Token";
    string public override symbol = "TKN";

    constructor() public {
    	exchangeRateStored = (1 ether);
        balanceOf[msg.sender] = (1 ether);
        totalSupply = (1 ether);
    }

    function mintTo(address _to, uint _amount) public {
        balanceOf[_to] = _amount;
    }

    function setExchangeRate(uint _exchangeRate) public {
    	require(_exchangeRate > exchangeRateStored, "new exchange rate must be greater than previous");
    	exchangeRateStored = _exchangeRate;
    }

    function transfer(address _to, uint256 _value) public override returns (bool success) {
        require(_value <= balanceOf[msg.sender]);

        balanceOf[msg.sender] -= _value;
        balanceOf[_to] += _value;

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
    	require(_value <= balanceOf[_from]);

    	balanceOf[_from] -= _value;
    	balanceOf[_to] += _value;

        allowance[_from][msg.sender] -= _value;

        emit Transfer(_from, _to, _value);

        return true;
    }

}