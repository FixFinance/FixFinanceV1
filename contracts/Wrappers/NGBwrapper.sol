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
	uint32 private SBPSRetained = 999_000;

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

	/*
		init
	*/
	constructor (address _underlyingAssetAddress, address _treasuryAddress, uint32 _SBPSRetained) public {
		require(_SBPSRetained > 0 && _SBPSRetained <= totalSBPS);
		underlyingAssetAddress = _underlyingAssetAddress;
		decimals = IERC20(_underlyingAssetAddress).decimals();
		name = string(abi.encodePacked('wrapped ',IERC20(_underlyingAssetAddress).name()));
		symbol = string(abi.encodePacked('w', IERC20(_underlyingAssetAddress).symbol()));
		treasuryAddress = _treasuryAddress;
		SBPSRetained = _SBPSRetained;
	}

	/*
		@Description: make first deposit into contract, totalSupply must == 0
		
		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amountUnit: the amount of underlying asset units to deposit

		@return uint _amountWrappedToken: the amount of wrapped tokens that were minted
	*/
	function firstDeposit(address _to, uint _amountUnit) internal returns (uint _amountWrappedToken) {
		IERC20 _aToken = IERC20(underlyingAssetAddress);
		_aToken.transferFrom(msg.sender, address(this), _amountUnit);
		balanceOf[_to] = _amountUnit;
		totalSupply = _amountUnit;
		_amountWrappedToken = _amountUnit;
		lastHarvest = block.timestamp;
		prevRatio = 1 ether;
	}

	/*
		@Description: send in underlying asset, receive wrapped asset

		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amountUnit: the amount of underlying asset units to deposit

		@return uint _amountWrappedToken: the amount of wrapped tokens that were minted
	*/
	function deposit(address _to, uint _amountUnit) internal returns (uint _amountWrappedToken) {
		uint _totalSupply = totalSupply;
		if (_totalSupply == 0) {
			return firstDeposit(_to, _amountUnit);
		}
		harvestToTreasury();
		IERC20 _aToken = IERC20(underlyingAssetAddress);
		uint contractBalance = _aToken.balanceOf(address(this));
		_aToken.transferFrom(msg.sender, address(this), _amountUnit);
		_amountWrappedToken = totalSupply*_amountUnit/contractBalance;
		balanceOf[_to] += _amountWrappedToken;
		totalSupply += _amountWrappedToken;
	}

	/*
		@Description: send in a specific amount of underlying asset, receive wrapped asset

		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amount: the amount of underlying asset units to deposit
	*/
	function depositUnitAmount(address _to, uint _amount) external override returns (uint _amountWrapped) {
		return deposit(_to, _amount);
	}

	/*
		@Description: send in underlying asset, receive a specific amount of wrapped asset

		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amount: the amount of wrapped asset units to mint
	*/
	function depositWrappedAmount(address _to, uint _amount) external override returns (uint _amountUnit) {
		_amountUnit = WrappedAmtToUnitAmt_RoundUp(_amount);
		deposit(_to, _amountUnit);
	}

	/*
		@Description: get the time at which the amount of yield generated in this wrapper was last updated
			because there is a limit of 20% of interest generated since last harvest that may be collected
			as fees we will always be able to get a wrapped asset to underlying asset ratio that accounts
			for 80% of interest generated since last harvest thus we return the current timestamp as the
			last update timestamp
	*/
	function lastUpdate() external view override returns (uint) {
		return block.timestamp;
	}

	/*
		@Description: get the ratio of underlyingAsset / wrappedAsset
	*/
	function getRatio() internal view returns (uint) {
		uint _totalSupply = totalSupply;	
		uint _prevRatio = prevRatio;
		uint contractBalance = IERC20(underlyingAssetAddress).balanceOf(address(this));
		uint nonFeeAdjustedRatio = uint(1 ether).mul(contractBalance).div(_totalSupply);
		//handle odd case, most likely only caused by rounding error (off by 1)
		if (nonFeeAdjustedRatio <= _prevRatio) {
			return _prevRatio;
		}
		uint minNewRatio = (nonFeeAdjustedRatio-_prevRatio)
			.mul(minHarvestRetention)
			.div(totalSBPS)
			.add(_prevRatio);
		return minNewRatio;
	}

	/*
		@Description: this function is called by amms to ensure the state of the wrapper has not changed
			between registration of a quote and acceptance of a quote.
			If the values returned by this function change after quote registration the amm quote will no
			longer be valid

		@return uint updateTimestamp: as long as within same block there is no problem
		@return uint ratio: as long as no yield is generated between quote registration and acceptance
			this function will not be responsible for reversion of quote acceptance
	*/
	function getStatus() external view override returns (uint updateTimestamp, uint ratio) {
		return (block.timestamp, getRatio());
	}

	/*
		@Description: collect fee, send 50% to owner and 50% to treasury address
			after the fee is collected the funds that are retained for wrapped asset holders will
			be == underlyingAsset.balanceOf(this) * (SBPSRetained/totalSBPS)**timeSinceLastHarvest(years)
			though it should be noted that if the fee is greater than 20% of the total interest
			generated since the last harvest the fee will be set to 20% of the total interest
			generated since the last harvest
	*/
	function harvestToTreasury() internal {
		uint _lastHarvest = lastHarvest;
		if (block.timestamp == _lastHarvest) {
			return;
		}
		uint contractBalance = IERC20(underlyingAssetAddress).balanceOf(address(this));
		uint prevTotalSupply = totalSupply;
		uint _prevRatio = prevRatio;
		//time in years
		/*
			nextBalance = contractBalance * ((totalBips-bipsToTreasury)/totalBips)**t
			prevTotalSupply*contractBalance/totalSupply = contractBalance * ((totalBips-bipsToTreasury)/totalBips)**t
			prevTotalSupply/totalSupply = ((totalBips-bipsToTreasury)/totalBips)**t
			totalSupply = prevTotalSupply*((totalBips-bipsToTreasury)/totalBips)**(-t)
		*/
		uint effectiveRatio = uint(1 ether).mul(contractBalance);
		uint nonFeeAdjustedRatio = effectiveRatio.div(prevTotalSupply);
		if (nonFeeAdjustedRatio <= _prevRatio) {
			//only continue if yield has been generated
			return;
		}
		uint minNewRatio = (nonFeeAdjustedRatio - _prevRatio).mul(minHarvestRetention).div(totalSBPS).add(_prevRatio);
		int128 time = int128(((block.timestamp - _lastHarvest) << 64)/ BigMath.SecondsPerYear);
		uint term = uint(BigMath.Pow(int128((uint(SBPSRetained) << 64) / totalSBPS), time.neg()));
		uint newTotalSupply = prevTotalSupply.mul(term) / ABDK_1;
		effectiveRatio = effectiveRatio.div(newTotalSupply);
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
		uint dividend = newTotalSupply.sub(prevTotalSupply) >> 1;
		balanceOf[treasuryAddress] += dividend;
		balanceOf[owner] += dividend;
		totalSupply = newTotalSupply;
	}

	/*
		@Description: harvest fees to treasury and owner
	*/
	function forceHarvest() external override {
		harvestToTreasury();
	}

	/*
		@Description: burn wrapped asset to receive an amount of underlying asset of _amountUnit

		@param address _to: the address that shall receive the underlying asset
		@param uint _amountUnit: the amount of underlying asset units to withdraw

		@return uint _amountWrappedToken: the amount of units of wrapped asset that were burned
	*/
	function withdrawUnitAmount(address _to, uint _amountUnit) public override returns (uint _amountWrappedToken) {
		harvestToTreasury();
		IERC20 _aToken = IERC20(underlyingAssetAddress);
		uint contractBalance = _aToken.balanceOf(address(this));
		//_amountWrappedToken == ceil(totalSupply*_amountUnit/contractBalance)
		_amountWrappedToken = totalSupply*_amountUnit;
		_amountWrappedToken = (_amountWrappedToken%contractBalance == 0 ? 0 : 1) + (_amountWrappedToken/contractBalance);
		require(balanceOf[msg.sender] >= _amountWrappedToken);
		balanceOf[msg.sender] -= _amountWrappedToken;
		totalSupply -= _amountWrappedToken;
		_aToken.transfer(_to, _amountUnit);
	}

	/*
		@Description: burn a specific amount of wrappet asset to get out underlying asset

		@param address _to: the address that shall receive the underlying asset
		@param uint _amountWrappedToken: the amount of units of wrappet asset to burn

		@return uint _amountUnit: the amount of underlying asset received
	*/
	function withdrawWrappedAmount(address _to, uint _amountWrappedToken) public override returns (uint _amountUnit) {
		require(balanceOf[msg.sender] >= _amountWrappedToken);
		harvestToTreasury();
		IERC20 _aToken = IERC20(underlyingAssetAddress);
		uint contractBalance = _aToken.balanceOf(address(this));
		_amountUnit = contractBalance*_amountWrappedToken/totalSupply;
		balanceOf[msg.sender] -= _amountWrappedToken;
		totalSupply -= _amountWrappedToken;
		_aToken.transfer(_to, _amountUnit);
	}


	/*
		@Description: convert an amount of underlying asset to its corresponding amount of wrapped asset, round down

		@param uint _amountUnit: the amount of underlying asset to convert

		@return uint _amountWrappedToken: the greatest amount of wrapped asset that is <= _amountUnit underlying asset
	*/
	function UnitAmtToWrappedAmt_RoundDown(uint _amountUnit) public view override returns (uint _amountWrappedToken) {
		uint ratio = getRatio();
		/*
			ratio == amountUnit/amountWrapped
			amountWrapped == amountUnit/ratio
		*/
		_amountWrappedToken = _amountUnit.mul(1 ether).div(ratio);
	}

	/*
		@Description: convert an amount of underlying asset to its corresponding amount of wrapped asset, round up

		@param uint _amountUnit: the amount of underlying asset to convert

		@return uint _amountWrappedToken: the smallest amount of wrapped asset that is >= _amountUnit underlying asset
	*/
	function UnitAmtToWrappedAmt_RoundUp(uint _amountUnit) public view override returns (uint _amountWrappedToken) {
		uint ratio = getRatio();
		/*
			ratio == amountUnit/amountWrapped
			amountWrapped == amountUnit/ratio
		*/
		_amountWrappedToken = _amountUnit.mul(1 ether);
		_amountWrappedToken = _amountWrappedToken/ratio + (_amountWrappedToken%ratio == 0 ? 0 : 1);
	}

	/*
		@Description: convert an amount of wrapped asset to its corresponding amount of underlying asset, round down

		@oaram unit _amountWrappedToken: the amount of wrapped asset to convert

		@return uint _amountWrappedToken: the greatest amount of underlying asset that is <= _amountWrapped wrapped asset
	*/
	function WrappedAmtToUnitAmt_RoundDown(uint _amountWrappedToken) public view override returns (uint _amountUnit) {
		uint ratio = getRatio();
		/*
			ratio == amountUnit/amountWrapped
			amountUnit == amountWrapped * ratio
		*/
		_amountUnit = _amountWrappedToken.mul(ratio)/(1 ether);
	}

	/*
		@Description: convert an amount of wrapped asset to its corresponding amount of underlying asset, round up

		@oaram unit _amountWrappedToken: the amount of wrapped asset to convert

		@return uint _amountWrappedToken: the smallest amount of underlying asset that is >= _amountWrapped wrapped asset
	*/
	function WrappedAmtToUnitAmt_RoundUp(uint _amountWrappedToken) public view override returns (uint _amountUnit) {
		uint ratio = getRatio();
		/*
			ratio == amountUnit/amountWrapped
			amountUnit == amountWrapped * ratio
		*/
		_amountUnit = _amountWrappedToken.mul(ratio);
		_amountUnit = _amountUnit/(1 ether) + (_amountUnit%(1 ether) == 0 ? 0 : 1);
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

    //------------------------------------a-d-m-i-n----------------------------

    /*
		@Description: set the annual wrapper fee in super basis points
			half of all fees goes to owner, the other half goes to the treasury

		@param uint32 _SBPSRetained: the amount of super bips that are to be retained by
			the pool. You can think of it as if totalSBPS - _SBPSRetained is the annual
			asset management fee for a wrapper
    */
    function setFee(uint32 _SBPSRetained) external onlyOwner {
    	require(_SBPSRetained > 0 && _SBPSRetained <= totalSBPS);
    	SBPSRetained = _SBPSRetained;
    }
}