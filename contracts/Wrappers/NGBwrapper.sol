pragma solidity >=0.6.5 <0.7.0;
import "../interfaces/IERC20.sol";
import "../interfaces/IWrapper.sol";
import "../libraries/SafeMath.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/BigMath.sol";
import "../helpers/Ownable.sol";
import "../ERC20.sol";

/*
	Native Growing Balance Wrapper

	Underlying Asset is native to the chain of the wrapper

	The balances of the underlying asset automatically grow as yield is generated
*/
contract NGBwrapper is IWrapper, Ownable {
	using SafeMath for uint;
	using ABDKMath64x64 for int128;

	//SBPS == super bips == 1/100th of a bip
	//100 * 10_000 == 1_000_000
	uint32 private constant totalSBPS = 1_000_000;

	//totalSBPS - annualTreasuryFee(in sbps)
	uint32 private constant SBPSRetained = 999_000;

	//minimum amount of interest on each harvest that should be retained for holders
	//of this token.
	//800_000 sbps == 8_000 bips == 80%
	//ex. if 1000 units of interest are generated between harvests then 800 units
	//is the minimum amount that must be retained for tokens holders thus the
	//maximum amount that may go to the treasury is 200 units
	uint32 private constant minHarvestRetention = 800_000;

	uint private constant ABDK_1 = 1 << 64;

	int128 private constant MAX = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

	address public override underlyingAssetAddress;

	bool public constant override underlyingIsWrapped = false;

	uint public prevRatio;

	uint8 public immutable override decimals;

	address public immutable treasuryAddress;

	uint public lastHarvest;

	constructor (address _underlyingAssetAddress) public {
		underlyingAssetAddress = _underlyingAssetAddress;
		decimals = IERC20(_underlyingAssetAddress).decimals();
		name = string(abi.encodePacked('wrapped ',IERC20(_underlyingAssetAddress).name()));
		symbol = string(abi.encodePacked('w', IERC20(_underlyingAssetAddress).symbol()));
		treasuryAddress = address(0);
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
		lastHarvest = block.timestamp;
		prevRatio = 1 ether;
	}

	function deposit(address _to, uint _amountAToken) internal returns (uint _amountWrappedToken) {
		uint _totalSupply = totalSupply;
		if (_totalSupply == 0) {
			return firstDeposit(_to, _amountAToken);
		}
		harvestToTreasury();
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

	function lastUpdate() external view override returns (uint) {
		return block.timestamp;
	}

	function getRatio() internal view returns (uint) {
		uint _totalSupply = totalSupply;	
		uint _prevRatio = prevRatio;
		uint contractBalance = IERC20(underlyingAssetAddress).balanceOf(address(this));
		uint nonFeeAdjustedRatio = uint(1 ether).mul(contractBalance).div(_totalSupply);
		//handle odd case, most likely only caused by rounding error (off by 1)
		if (nonFeeAdjustedRatio < _prevRatio) {
			return nonFeeAdjustedRatio;
		}
		uint minNewRatio = nonFeeAdjustedRatio
			.sub(_prevRatio)
			.mul(minHarvestRetention)
			.div(totalSBPS)
			.add(_prevRatio);
		return minNewRatio;
	}

	function getStatus() external view override returns (uint updateTimestamp, uint ratio) {
		return (block.timestamp, getRatio());
	}

	function harvestToTreasury() internal {
		uint _lastHarvest = lastHarvest;
		if (block.timestamp == _lastHarvest) {
			return;
		}
		uint contractBalance = IERC20(underlyingAssetAddress).balanceOf(address(this));
		uint prevTotalSupply = totalSupply;
		uint _prevRatio = prevRatio;
		//time in years
		int128 time = int128(((block.timestamp - _lastHarvest) << 64)/ BigMath.SecondsPerYear);
		/*
			nextBalance = contractBalance * ((totalBips-bipsToTreasury)/totalBips)**t
			prevTotalSupply*contractBalance/totalSupply = contractBalance * ((totalBips-bipsToTreasury)/totalBips)**t
			prevTotalSupply/totalSupply = ((totalBips-bipsToTreasury)/totalBips)**t
			totalSupply = prevTotalSupply*((totalBips-bipsToTreasury)/totalBips)**(-t)
		*/
		uint term = uint(BigMath.Exp(int128((uint(SBPSRetained) << 64) / totalSBPS), time.neg()));
		uint newTotalSupply = prevTotalSupply.mul(term) / ABDK_1;
		uint effectiveRatio = uint(1 ether).mul(contractBalance);
		uint nonFeeAdjustedRatio = effectiveRatio.div(prevTotalSupply);
		effectiveRatio = effectiveRatio.div(newTotalSupply);
		uint minNewRatio = nonFeeAdjustedRatio.sub(_prevRatio).mul(minHarvestRetention).div(totalSBPS).add(_prevRatio);
		if (effectiveRatio < minNewRatio) {
			/*
				ratio == contractBalance/totalSupply
				totalSupply == contractBalance/ratio
			*/
			newTotalSupply = contractBalance.mul(1 ether).div(minNewRatio);
			prevRatio = minNewRatio;
		}
		else {
			prevRatio = effectiveRatio;
		}
		lastHarvest = block.timestamp;
		balanceOf[treasuryAddress] += newTotalSupply.sub(prevTotalSupply);
		totalSupply = newTotalSupply;
	}

	function forceHarvest() external override {
		harvestToTreasury();
	}

	function withdrawUnitAmount(address _to, uint _amountAToken) public override returns (uint _amountWrappedToken) {
		harvestToTreasury();
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
		harvestToTreasury();
		IERC20 _aToken = IERC20(underlyingAssetAddress);
		uint contractBalance = _aToken.balanceOf(address(this));
		_amountAToken = contractBalance*_amountWrappedToken/totalSupply;
		balanceOf[msg.sender] -= _amountWrappedToken;
		totalSupply -= _amountWrappedToken;
		_aToken.transfer(_to, _amountAToken);
	}

	function UnitAmtToWrappedAmt_RoundDown(uint _amountAToken) public view override returns (uint _amountWrappedToken) {
		uint ratio = getRatio();
		/*
			ratio == amountUnit/amountWrapped
			amountWrapped == amountUnit/ratio
		*/
		_amountWrappedToken = _amountAToken.mul(1 ether).div(ratio);
	}

	function UnitAmtToWrappedAmt_RoundUp(uint _amountAToken) public view override returns (uint _amountWrappedToken) {
		uint ratio = getRatio();
		/*
			ratio == amountUnit/amountWrapped
			amountWrapped == amountUnit/ratio
		*/
		_amountWrappedToken = _amountAToken.mul(1 ether);
		_amountWrappedToken = _amountWrappedToken/ratio + (_amountWrappedToken%ratio == 0 ? 0 : 1);
	}

	function WrappedAmtToUnitAmt_RoundDown(uint _amountWrappedToken) public view override returns (uint _amountAToken) {
		uint ratio = getRatio();
		/*
			ratio == amountUnit/amountWrapped
			amountUnit == amountWrapped * ratio
		*/
		_amountAToken = _amountWrappedToken.mul(ratio)/(1 ether);
	}

	function WrappedAmtToUnitAmt_RoundUp(uint _amountWrappedToken) public view override returns (uint _amountAToken) {
		uint ratio = getRatio();
		/*
			ratio == amountUnit/amountWrapped
			amountUnit == amountWrapped * ratio
		*/
		_amountAToken = _amountWrappedToken.mul(ratio);
		_amountAToken = _amountAToken/(1 ether) + (_amountAToken%(1 ether) == 0 ? 0 : 1);
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