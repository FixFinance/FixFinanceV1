pragma solidity >=0.6.5 <0.7.0;
import "./interfaces/IERC20.sol";
import "./interfaces/IWrapper.sol";
import "./libraries/SafeMath.sol";
import "./ERC20.sol";

contract AaveWrapper is IWrapper {
	using SafeMath for uint;

	address public override underlyingAssetAddress;

	bool public constant override underlyingIsWrapped = false;

	uint8 public immutable override decimals;

	constructor (address _underlyingAssetAddress) public {
		underlyingAssetAddress = _underlyingAssetAddress;
		decimals = IERC20(_underlyingAssetAddress).decimals();
		name = string(abi.encodePacked('wrapped ',IERC20(_underlyingAssetAddress).name()));
		symbol = string(abi.encodePacked('w', IERC20(_underlyingAssetAddress).symbol()));
	}

	function balanceUnit(address _owner) external view override returns (uint balance) {
		if (balanceOf[_owner] == 0) return 0;
		return balanceOf[_owner] * IERC20(underlyingAssetAddress).balanceOf(address(this)) / totalSupply;
	}

	function firstDeposit(address _to, uint _amountAToken) internal returns (uint _amountWrappedToken) {
		IERC20 _aToken = IERC20(underlyingAssetAddress);
		_aToken.transferFrom(msg.sender, address(this), _amountAToken);
		balanceOf[_to] = _amountAToken;
		totalSupply = _amountAToken;
		_amountWrappedToken = _amountAToken;
	}

	function deposit(address _to, uint _amountAToken) internal returns (uint _amountWrappedToken) {
		uint _totalSupply = totalSupply;
		if (_totalSupply == 0) {
			return firstDeposit(_to, _amountAToken);
		}
		IERC20 _aToken = IERC20(underlyingAssetAddress);
		uint contractBalance = _aToken.balanceOf(address(this));
		_aToken.transferFrom(msg.sender, address(this), _amountAToken);
		_amountWrappedToken = totalSupply*_amountAToken/contractBalance;
		balanceOf[_to] += _amountWrappedToken;
		totalSupply += _amountWrappedToken;
	}

	function depositUnitAmount(address _to, uint _amount) external override returns (uint _amountWrapped) {
		return deposit(_to, _amount);
	}
	function depositWrappedAmount(address _to, uint _amount) external override returns (uint _amountUnit) {
		_amountUnit = WrappedAmtToUnitAmt_RoundUp(_amount);
		deposit(_to, _amountUnit);
	}


	function withdrawUnitAmount(address _to, uint _amountAToken) public override returns (uint _amountWrappedToken) {
		IERC20 _aToken = IERC20(underlyingAssetAddress);
		uint contractBalance = _aToken.balanceOf(address(this));
		//_amountWrappedToken == ceil(totalSupply*_amountAToken/contractBalance)
		_amountWrappedToken = totalSupply*_amountAToken;
		_amountWrappedToken = (_amountWrappedToken%contractBalance == 0 ? 0 : 1) + (_amountWrappedToken/contractBalance);
		require(balanceOf[msg.sender] >= _amountWrappedToken);
		balanceOf[msg.sender] -= _amountWrappedToken;
		totalSupply -= _amountWrappedToken;
		_aToken.transfer(_to, _amountAToken);
	}

	function withdrawWrappedAmount(address _to, uint _amountWrappedToken) public override returns (uint _amountAToken) {
		require(balanceOf[msg.sender] >= _amountWrappedToken);
		IERC20 _aToken = IERC20(underlyingAssetAddress);
		uint contractBalance = _aToken.balanceOf(address(this));
		_amountAToken = contractBalance*_amountWrappedToken/totalSupply;
		balanceOf[msg.sender] -= _amountWrappedToken;
		totalSupply -= _amountWrappedToken;
		_aToken.transfer(_to, _amountAToken);
	}

	function UnitAmtToWrappedAmt_RoundDown(uint _amountAToken) public view override returns (uint _amountWrappedToken) {
		IERC20 _aToken = IERC20(underlyingAssetAddress);
		uint contractBalance = _aToken.balanceOf(address(this));
		uint _totalSupply = totalSupply;
		if (_totalSupply == 0) return _amountAToken;
		/*
			_amountWrappedToken == ceil(contractBalance*_amountAToken/totalSupply)
		*/
		_amountWrappedToken = _totalSupply*_amountAToken/contractBalance;
	}

	function UnitAmtToWrappedAmt_RoundUp(uint _amountAToken) public view override returns (uint _amountWrappedToken) {
		IERC20 _aToken = IERC20(underlyingAssetAddress);
		uint contractBalance = _aToken.balanceOf(address(this));
		uint _totalSupply = totalSupply;
		if (_totalSupply == 0) return _amountAToken;
		/*
			_amountWrappedToken == ceil(contractBalance*_amountAToken/totalSupply)
		*/
		_amountWrappedToken = _totalSupply*_amountAToken;
		_amountWrappedToken = (_amountWrappedToken%contractBalance == 0 ? 0 : 1) + _amountWrappedToken/contractBalance;
	}

	function WrappedAmtToUnitAmt_RoundDown(uint _amountWrappedToken) public view override returns (uint _amountAToken) {
		IERC20 _aToken = IERC20(underlyingAssetAddress);
		uint contractBalance = _aToken.balanceOf(address(this));
		uint _totalSupply = totalSupply;
		_amountAToken = _totalSupply == 0 ? _amountWrappedToken : contractBalance*_amountWrappedToken/_totalSupply;
	}

	function WrappedAmtToUnitAmt_RoundUp(uint _amountWrappedToken) public view override returns (uint _amountAToken) {
		IERC20 _aToken = IERC20(underlyingAssetAddress);
		uint contractBalance = _aToken.balanceOf(address(this));
		uint _totalSupply = totalSupply;
		if (_totalSupply == 0) return _amountWrappedToken;
		_amountAToken = contractBalance*_amountWrappedToken;
		_amountAToken = _amountAToken/_totalSupply + (_amountAToken % _totalSupply == 0 ? 0 : 1);
	}


	//---------------------------------------------------i-m-p-l-e-m-e-n-t-s---E-R-C-2-0---------------------------
	uint public override totalSupply;

	mapping(address => uint) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    string public override name;
    string public override symbol;


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