pragma solidity >=0.6.5 <0.7.0;
import "./interfaces/IERC20.sol";


contract ERC20 is IERC20 {
	uint8 public override decimals;

	uint public override totalSupply;

	mapping(address => uint) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    string public override name = "Token";
    string public override symbol = "TKN";


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