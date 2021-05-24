// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "../interfaces/IERC20.sol";

/*
    For the purposes of this project all we need our dummy aToken to be able to do is
    increase all balances of users by a factor which increases over time
*/
contract dummyAToken is IERC20 {
	uint8 public override decimals = 18;

	uint public override totalSupply = 1e18;

	mapping(address => uint) internal balanceOfInternal;
    mapping(address => mapping(address => uint256)) internal allowanceInternal;

    address varianceSwapHandlerAddress;

    uint public inflation = 1e18;

    string public override name = "dummyAToken";
    string public override symbol;

    constructor (string memory _symbol) public {
        symbol = _symbol;
    	balanceOfInternal[msg.sender] = totalSupply;
    }

    function mintTo(address _to, uint _amount) public {
        balanceOfInternal[_to] = _amount;
    }

    function setInflation(uint _inflation) public {
    	require(_inflation > inflation);
    	inflation = _inflation;
    }

    function balanceOf(address _owner) public override view returns (uint balance) {
    	balance = inflation*balanceOfInternal[_owner]/1e18;
    }

    function allowance(address _owner, address _spender) public override view returns (uint remaining) {
    	remaining = inflation*allowanceInternal[_owner][_spender]/1e18;
    }

    function transfer(address _to, uint256 _value) public override returns (bool success) {
    	uint internalVal = 1e18*_value/inflation;
        require(internalVal <= balanceOfInternal[msg.sender]);

        balanceOfInternal[msg.sender] -= internalVal;
        balanceOfInternal[_to] += internalVal;

        emit Transfer(msg.sender, _to, _value);

        return true;
    }

    function approve(address _spender, uint256 _value) public override returns (bool success) {
    	uint internalVal = 1e18*_value/inflation;
        allowanceInternal[msg.sender][_spender] = internalVal;

        emit Approval(msg.sender, _spender, _value);

        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public override returns (bool success) {
    	uint internalVal = 1e18*_value/inflation;
        require(internalVal <= allowanceInternal[_from][msg.sender]);
    	require(internalVal <= balanceOfInternal[_from]);

    	balanceOfInternal[_from] -= internalVal;
    	balanceOfInternal[_to] += internalVal;

        allowanceInternal[_from][msg.sender] -= internalVal;

        emit Transfer(_from, _to, _value);

        return true;
    }
}