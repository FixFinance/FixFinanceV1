// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "../../interfaces/IERC20.sol";
import "../../interfaces/INGBWrapper.sol";
import "../../interfaces/IInfoOracle.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/ABDKMath64x64.sol";
import "../../libraries/BigMath.sol";
import "../../helpers/nonReentrant.sol";
import "../../helpers/Ownable.sol";
import "./NGBwrapperData.sol";

/*
	Native Growing Balance Wrapper

	Underlying Asset is native to the chain of the wrapper

	The balances of the underlying asset automatically grow as yield is generated
*/
contract NGBwrapper is INGBWrapper, NGBwrapperData {
	using SafeMath for uint;
	using ABDKMath64x64 for int128;

	modifier claimRewards(address _addr) {
		for (uint8 i = 0; i < NUM_REWARD_ASSETS; i++) {
			address _rewardsAddr = rewardsAddr[i];
			if (_rewardsAddr == address(0)) {
				_;
				return;
			}
			uint _totalSupply = internalTotalSupply;
			uint CBRA = IERC20(_rewardsAddr).balanceOf(_rewardsAddr); //contract balance rewards asset
			uint TDPW = totalDividendsPaidPerWasset[i]; //total dividends paid per wasset since contract inception
			uint CBRAPWA = CBRA.mul(1 ether).div(_totalSupply); //contract balance rewards asset per wasset
			uint TRPW = CBRAPWA.add(TDPW); //total rewards per wasset since contract inception
			//total rewards per wasset from contract inception to most recent rewards collection for _addr
			uint prevTRPW = prevTotalRewardsPerWasset[_addr][i];
			if (prevTRPW < TRPW) {
				uint RPW = TRPW - prevTRPW; //rewards per wasset
				uint dividend = RPW.mul(internalBalanceOf[_addr]) / (1 ether); //dividend to be paid to _addr
				uint additionalDPW = dividend.mul(1 ether).div(_totalSupply).add(1); //add 1 to avoid rounding errors
				IERC20(_rewardsAddr).transfer(_addr, dividend);
				totalDividendsPaidPerWasset[i] = TDPW.add(additionalDPW);
				prevTotalRewardsPerWasset[_addr][i] = TRPW;
			}
		}
		_;
	}

	modifier doubleClaimReward(address _addr0, address _addr1) {
		for (uint8 i = 0; i < NUM_REWARD_ASSETS; i++) {
			address _rewardsAddr = rewardsAddr[i];
			if (_rewardsAddr == address(0)) {
				_;
				return;
			}
			uint _totalSupply = internalTotalSupply;
			uint CBRA = IERC20(_rewardsAddr).balanceOf(_rewardsAddr); //contract balance rewards asset
			uint TDPW = totalDividendsPaidPerWasset[i]; //total dividends paid per wasset since contract inception
			uint CBRAPWA = CBRA.mul(1 ether).div(_totalSupply); //contract balance rewards asset per wasset
			uint TRPW = CBRAPWA.add(TDPW); //total rewards per wasset since contract inception
			//total rewards per wasset from contract inception to most recent rewards collection for _addr
			uint prevTRPW = prevTotalRewardsPerWasset[_addr0][i];
			uint nextTDPW = TDPW;
			if (prevTRPW < TRPW) {
				uint RPW = TRPW - prevTRPW; //rewards per wasset
				uint dividend = RPW.mul(internalBalanceOf[_addr0]);
				dividend = dividend / (1 ether); //dividend to be paid to _addr
				uint additionalDPW = dividend.mul(1 ether).div(_totalSupply).add(1); //add 1 to avoid rounding errors
				IERC20(_rewardsAddr).transfer(_addr0, dividend);
				nextTDPW = TDPW.add(additionalDPW);
				address addr = _addr0; //prevent stack too deep
				prevTotalRewardsPerWasset[addr][i] = TRPW;
			}
			prevTRPW = prevTotalRewardsPerWasset[_addr1][i];
			if (prevTRPW < TRPW) {
				uint RPW = TRPW - prevTRPW; //rewards per wasset
				uint dividend = RPW.mul(internalBalanceOf[_addr1]);
				dividend = dividend / (1 ether); //dividend to be paid to _addr
				uint additionalDPW = dividend.mul(1 ether).div(_totalSupply).add(1); //add 1 to avoid rounding errors
				IERC20(_rewardsAddr).transfer(_addr1, dividend);
				nextTDPW = TDPW.add(additionalDPW);
				prevTotalRewardsPerWasset[_addr1][i] = TRPW;
			}
			if (nextTDPW > TDPW) {
				totalDividendsPaidPerWasset[i] = nextTDPW;
			}
		}
		_;
	}

	/*
		init
	*/
	constructor (address _underlyingAssetAddress, address _infoOralceAddress, uint32 _SBPSRetained) public {
		require(_SBPSRetained > 0 && _SBPSRetained <= totalSBPS);
		internalUnderlyingAssetAddress = _underlyingAssetAddress;
		internalDecimals = IERC20(_underlyingAssetAddress).decimals();
		internalName = string(abi.encodePacked('wrapped ',IERC20(_underlyingAssetAddress).name()));
		internalSymbol = string(abi.encodePacked('w', IERC20(_underlyingAssetAddress).symbol()));
		internalInfoOracleAddress = _infoOralceAddress;
		SBPSRetained = _SBPSRetained;
	}

	/*
		@Description: make first deposit into contract, internalTotalSupply must == 0
		
		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amountUnit: the amount of underlying asset units to deposit

		@return uint _amountWrappedToken: the amount of wrapped tokens that were minted
	*/
	function firstDeposit(address _to, uint _amountUnit) internal returns (uint _amountWrappedToken) {
		IERC20 _aToken = IERC20(internalUnderlyingAssetAddress);
		bool success = _aToken.transferFrom(msg.sender, address(this), _amountUnit);
		require(success);
		internalBalanceOf[_to] = _amountUnit;
		internalTotalSupply = _amountUnit;
		_amountWrappedToken = _amountUnit;
		internalLastHarvest = block.timestamp;
		internalPrevRatio = 1 ether;
	}

	/*
		@Description: send in underlying asset, receive wrapped asset

		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amountUnit: the amount of underlying asset units to deposit

		@return uint _amountWrappedToken: the amount of wrapped tokens that were minted
	*/
	function deposit(address _to, uint _amountUnit) internal returns (uint _amountWrappedToken) {
		uint _totalSupply = internalTotalSupply;
		if (_totalSupply == 0) {
			return firstDeposit(_to, _amountUnit);
		}
		harvestToTreasury();
		IERC20 _aToken = IERC20(internalUnderlyingAssetAddress);
		uint contractBalance = _aToken.balanceOf(address(this));
		bool success = _aToken.transferFrom(msg.sender, address(this), _amountUnit);
		require(success);
		_amountWrappedToken = internalTotalSupply*_amountUnit/contractBalance;
		internalBalanceOf[_to] += _amountWrappedToken;
		internalTotalSupply += _amountWrappedToken;
	}

	/*
		@Description: send in a specific amount of underlying asset, receive wrapped asset

		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amount: the amount of underlying asset units to deposit
	*/
	function depositUnitAmount(address _to, uint _amount) external claimRewards(_to) override returns (uint _amountWrapped) {
		return deposit(_to, _amount);
	}

	/*
		@Description: send in underlying asset, receive a specific amount of wrapped asset

		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amount: the amount of wrapped asset units to mint
	*/
	function depositWrappedAmount(address _to, uint _amount) external claimRewards(_to) override returns (uint _amountUnit) {
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
		uint _totalSupply = internalTotalSupply;	
		uint _prevRatio = internalPrevRatio;
		uint contractBalance = IERC20(internalUnderlyingAssetAddress).balanceOf(address(this));
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
		uint _lastHarvest = internalLastHarvest;
		if (block.timestamp == _lastHarvest) {
			return;
		}
		uint contractBalance = IERC20(internalUnderlyingAssetAddress).balanceOf(address(this));
		uint prevTotalSupply = internalTotalSupply;
		uint _prevRatio = internalPrevRatio;
		//time in years
		/*
			nextBalance = contractBalance * ((totalBips-bipsToTreasury)/totalBips)**t
			prevTotalSupply*contractBalance/internalTotalSupply = contractBalance * ((totalBips-bipsToTreasury)/totalBips)**t
			prevTotalSupply/internalTotalSupply = ((totalBips-bipsToTreasury)/totalBips)**t
			internalTotalSupply = prevTotalSupply*((totalBips-bipsToTreasury)/totalBips)**(-t)
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
		uint newTotalSupply = prevTotalSupply.mul(term) >> 64;
		effectiveRatio = effectiveRatio.div(newTotalSupply);
		if (effectiveRatio < minNewRatio) {
			/*
				ratio == contractBalance/internalTotalSupply
				internalTotalSupply == contractBalance/ratio
			*/
			newTotalSupply = contractBalance.mul(1 ether).div(minNewRatio);
			internalPrevRatio = minNewRatio;
		}
		else {
			internalPrevRatio = effectiveRatio;
		}
		internalLastHarvest = block.timestamp;
		uint dividend = newTotalSupply.sub(prevTotalSupply);
		address sendTo = IInfoOracle(internalInfoOracleAddress).sendTo();
		internalBalanceOf[sendTo] += dividend >> 1;
		internalBalanceOf[owner] += dividend - (dividend >> 1);
		internalTotalSupply = newTotalSupply;
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
		IERC20 _aToken = IERC20(internalUnderlyingAssetAddress);
		uint contractBalance = _aToken.balanceOf(address(this));
		//_amountWrappedToken == ceil(internalTotalSupply*_amountUnit/contractBalance)
		_amountWrappedToken = internalTotalSupply*_amountUnit;
		_amountWrappedToken = (_amountWrappedToken%contractBalance == 0 ? 0 : 1) + (_amountWrappedToken/contractBalance);
		require(internalBalanceOf[msg.sender] >= _amountWrappedToken);
		internalBalanceOf[msg.sender] -= _amountWrappedToken;
		internalTotalSupply -= _amountWrappedToken;
		_aToken.transfer(_to, _amountUnit);
	}

	/*
		@Description: burn a specific amount of wrappet asset to get out underlying asset

		@param address _to: the address that shall receive the underlying asset
		@param uint _amountWrappedToken: the amount of units of wrappet asset to burn

		@return uint _amountUnit: the amount of underlying asset received
	*/
	function withdrawWrappedAmount(address _to, uint _amountWrappedToken) public override returns (uint _amountUnit) {
		require(internalBalanceOf[msg.sender] >= _amountWrappedToken);
		harvestToTreasury();
		IERC20 _aToken = IERC20(internalUnderlyingAssetAddress);
		uint contractBalance = _aToken.balanceOf(address(this));
		_amountUnit = contractBalance*_amountWrappedToken/internalTotalSupply;
		internalBalanceOf[msg.sender] -= _amountWrappedToken;
		internalTotalSupply -= _amountWrappedToken;
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


    function transfer(address _to, uint256 _value) public doubleClaimReward(_to, msg.sender) override returns (bool success) {
        require(_value <= internalBalanceOf[msg.sender]);

        internalBalanceOf[msg.sender] -= _value;
        internalBalanceOf[_to] += _value;

        emit Transfer(msg.sender, _to, _value);

        return true;
    }

    function approve(address _spender, uint256 _value) public override returns (bool success) {
        internalAllowance[msg.sender][_spender] = _value;

        emit Approval(msg.sender, _spender, _value);

        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public doubleClaimReward(_to, _from) override returns (bool success) {
        require(_value <= internalAllowance[_from][msg.sender]);
    	require(_value <= internalBalanceOf[_from]);

    	internalBalanceOf[_from] -= _value;
    	internalBalanceOf[_to] += _value;

        internalAllowance[_from][msg.sender] -= _value;

        emit Transfer(_from, _to, _value);

        return true;
    }

    //-----------------------E-I-P-3-1-6-5---f-l-a-s-h-l-o-a-n---f-u-n-c-t-i-o-n-a-l-i-t-y-----------------


    function maxFlashLoan(
        address token
    ) external view override returns (uint256) {
    	require(token == address(this));
    	uint _flashLoanFee = internalFlashLoanFee;
    	return (uint256(-1) - internalTotalSupply).div(_flashLoanFee == 0 ? 1 : _flashLoanFee);
    }

    function flashFee(
        address token,
        uint256 amount
    ) external view override returns (uint256) {
    	require(token == address(this));
    	return amount.mul(internalFlashLoanFee) / totalSBPS;
    }

    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external override noReentry returns (bool) {
    	require(token == address(this));
    	require(amount + internalTotalSupply <= uint256(-1));
    	uint _flashLoanFee = internalFlashLoanFee;
    	require(amount <= (uint256(-1) - internalTotalSupply) / (_flashLoanFee == 0 ? 1 : _flashLoanFee));
    	uint fee = amount.mul(_flashLoanFee) / totalSBPS;
    	internalBalanceOf[msg.sender] += amount;
        uint256 _allowance = internalAllowance[address(receiver)][address(this)];
        require(
            _allowance >= (amount + fee),
            "FlashMinter: Repay not approved"
        );
        internalAllowance[address(receiver)][address(this)] = _allowance - (amount + fee);
    	bytes32 out = receiver.onFlashLoan(msg.sender, token, amount, fee, data);
    	require(CALLBACK_SUCCESS == out);
        uint balance = internalBalanceOf[address(receiver)];
        require(balance >= (amount + fee));
        internalBalanceOf[address(receiver)] = balance - (amount + fee);
        internalTotalSupply = internalTotalSupply.sub(fee);
        return true;
    }

    //------------------------v-i-e-w-s---------------------------

	bool public constant override underlyingIsStatic = false;

	function flashLoanFee() external view override returns(uint256) {
		return internalFlashLoanFee;
	}

	function prevRatio() external view override returns(uint) {
		return internalPrevRatio;
	}

	function lastHarvest() external view override returns(uint) {
		return internalLastHarvest;
	}

	function underlyingAssetAddress() external view override returns(address) {
		return internalUnderlyingAssetAddress;
	}

	function infoOracleAddress() external view override returns(address) {
		return internalInfoOracleAddress;
	}

    function totalSupply() external view override returns (uint supply) {
    	return internalTotalSupply;
    }

    function balanceOf(address _owner) external view override returns (uint balance) {
    	return internalBalanceOf[_owner];
    }

    function allowance(address _owner, address _spender) external view override returns (uint remaining) {
    	return internalAllowance[_owner][_spender];
    }

    function decimals() external view override returns(uint8 digits) {
    	return internalDecimals;
    }

    function name() external view override returns (string memory _name) {
    	return internalName;
    }

    function symbol() external view override returns (string memory _symbol) {
    	return internalSymbol;
    }

    //------------------------------------a-d-m-i-n----------------------------

    /*
		@Description: set the annual wrapper fee in super basis points
			half of all fees goes to owner, the other half goes to the treasury

		@param uint32 _SBPSRetained: the amount of super bips that are to be retained by
			the pool. You can think of it as if totalSBPS - _SBPSRetained is the annual
			asset management fee for a wrapper
    */
    function setInterestFee(uint32 _SBPSRetained) external onlyOwner {
    	require(_SBPSRetained > 0 && _SBPSRetained <= totalSBPS);
    	SBPSRetained = _SBPSRetained;
    }

    /*
		@Description: set the percentage fee that is applied to all flashloans

		@param uint _flashLoanFee: the new fee percentage denominated in superbips which is to be applied to flashloans
    */
    function setFlashLoanFee(uint _flashLoanFee) external onlyOwner {
    	internalFlashLoanFee = _flashLoanFee;
    }

    /*
		@Description: add an asset for which wrapped asset holders will earn LM rewards

		@param address _rewardsAsset: the new asset for which to start distribution of LM rewards
		@param uint8 _index: the index within the rewardsAddr array where the new rewards asset will be
    */
    function addRewardAsset(address _rewardsAsset, uint8 _index) external onlyOwner {
    	require(_index < NUM_REWARD_ASSETS);
    	require(rewardsAddr[_index] == address(0));
    	for (uint8 i = 0; i < _index; i++) {
			address addr = rewardsAddr[_index-1];
			require(addr != _rewardsAsset && addr != address(0));
    	}
    	//collect and distribute current balance
    	rewardsAddr[_index] = _rewardsAsset;
    }

    /*
		@Description: remove old rewards asset that is non functional contract / invalid address

		@param address _newRewardAsset: the new asset to replace the previous rewards asset at index _index
			_newRewardAsset may equal address(0) only if the value at the next index is address(0)
		@param uint8 _index: the index for which to change the rewards asset address
    */
    function overwriteRewardAsset(address _newRewardAsset, uint8 _index) external onlyOwner {
    	require(_newRewardAsset != address(0));
    	require(_index < NUM_REWARD_ASSETS);
    	address prevRewardAsset = rewardsAddr[_index];
    	require(prevRewardAsset != address(0));
    	require(totalDividendsPaidPerWasset[_index] == 0);
    	bool success;
		bytes memory sig = abi.encodeWithSignature("balanceOf(address)", address(this));
		uint bal;
		assembly {
			success := delegatecall(gas(), prevRewardAsset, add(sig, 0x20), mload(sig), 0, 0x20)

			if success {
				bal := mload(0)
			}
		}
		if (success) {
			IERC20(prevRewardAsset).transfer(msg.sender, bal >> 1);
			address sendTo = IInfoOracle(internalInfoOracleAddress).sendTo();
			IERC20(prevRewardAsset).transfer(sendTo, bal >> 1);
		}
    	//collect and distribute current balance
    	rewardsAddr[_index] = _newRewardAsset;
    }
}