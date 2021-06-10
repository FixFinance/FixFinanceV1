// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../interfaces/IZCBamm.sol";

abstract contract AZCBamm is IZCBamm {
	uint8 private constant LENGTH_RATE_SERIES = 31;

	address public override ZCBaddress;
	address public override YTaddress;
	address public override FCPaddress;

	//---------------------f-o-r---I-E_R_C-2-0-----------------------
	//total amount of smallest denomination units of coin in this smart contract
	uint public override totalSupply;
	//10 ** decimals == the amount of sub units in a whole coin
	uint8 public override decimals = 18;
	//each user's balance of coins
	mapping(address => uint) public override balanceOf;
	//the amount of funds each address has allowed other addresses to spend on the first address's behalf
	//holderOfFunds => spender => amountOfFundsAllowed
	mapping(address => mapping(address => uint)) public override allowance;


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