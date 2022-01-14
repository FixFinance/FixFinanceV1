// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "../../interfaces/IERC20.sol";
import "../../interfaces/INGBWrapper.sol";
import "../../interfaces/IInfoOracle.sol";
import "../../interfaces/IFixCapitalPool.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/ABDKMath64x64.sol";
import "../../libraries/SafeERC20.sol";
import "../../libraries/BigMath.sol";
import "../../helpers/nonReentrant.sol";
import "../../helpers/Ownable.sol";
import "./NGBwrapperInternals.sol";

/*
	Native Growing Balance Wrapper

	Underlying Asset is native to the chain of the wrapper

	The balances of the underlying asset automatically grow as yield is generated
*/
contract NGBwrapper is INGBWrapper, NGBwrapperInternals {
	using SafeMath for uint256;
	using ABDKMath64x64 for int128;
	using SafeERC20 for IERC20;

	address delegate1Address;
	address delegate2Address;
	address delegate3Address;

	/*
		init
	*/
	constructor (
		address _underlyingAssetAddress,
		address _infoOralceAddress,
		address _delegate1Address,
		address _delegate2Address,
		address _delegate3Address,
		uint32 _SBPSRetained
	) public {
		require(_SBPSRetained > 0 && _SBPSRetained <= totalSBPS);
		internalUnderlyingAssetAddress = _underlyingAssetAddress;
		internalDecimals = IERC20(_underlyingAssetAddress).decimals();
		internalName = string(abi.encodePacked('wrapped ',IERC20(_underlyingAssetAddress).name()));
		internalSymbol = string(abi.encodePacked('w', IERC20(_underlyingAssetAddress).symbol()));
		internalInfoOracleAddress = _infoOralceAddress;
		delegate1Address = _delegate1Address;
		delegate2Address = _delegate2Address;
		delegate3Address = _delegate3Address;
		SBPSRetained = _SBPSRetained;
	}

	/*
		@Description: send in a specific amount of underlying asset, receive wrapped asset

		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amount: the amount of underlying asset units to deposit
	*/
	function depositUnitAmount(address _to, uint _amount) public override returns (uint _amountWrapped) {
		address _delegateAddress = delegate1Address;
		bytes memory sig = abi.encodeWithSignature("depositUnitAmount(address,uint256)", _to, _amount);

		assembly {
			let retPtr := mload(0x40)

			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), retPtr, 0x20)

			if iszero(success) { revert(0,0) }

			_amountWrapped := mload(retPtr)
		}

		emit Deposit(_to, _amountWrapped);
	}

	/*
		@Description: send in underlying asset, receive a specific amount of wrapped asset

		@param address _to: the address that shall receive the newly minted wrapped tokens
		@param uint _amount: the amount of wrapped asset units to mint
	*/
	function depositWrappedAmount(address _to, uint _amount) external override returns (uint _amountUnit) {
		address _delegateAddress = delegate1Address;
		bytes memory sig = abi.encodeWithSignature("depositWrappedAmount(address,uint256)", _to, _amount);

		assembly {
			let retPtr := mload(0x40)

			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), retPtr, 0x20)

			if iszero(success) { revert(0,0) }

			_amountUnit := mload(retPtr)
		}

		emit Deposit(_to, _amount);
	}

	/*
		@Description: send in specific amount of the underlying to receive the wrapped asset
			this function does exactly the same thing as depositUnitAmount in NGBwrapper though it is needed to keep compatiability with IWrapper
	*/
	function depositUnderlying(address _to, uint _amount) external override returns (uint _amountWrapped) {
		_amountWrapped = depositUnitAmount(_to, _amount);
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
		(bool success, ) = delegate1Address.delegatecall(abi.encodeWithSignature("harvestToTreasury()"));
		require(success);
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
	function withdrawUnitAmount(address _to, uint _amountUnit, bool _claimRewards) external override returns (uint _amountWrappedToken) {
		address _delegateAddress = delegate1Address;
		bytes memory sig = abi.encodeWithSignature("withdrawUnitAmount(address,uint256,bool)", _to, _amountUnit, _claimRewards);

		assembly {
			let retPtr := mload(0x40)

			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), retPtr, 0x20)

			if iszero(success) { revert(0,0) }

			_amountWrappedToken := mload(retPtr)
		}

		emit Withdrawal(msg.sender, _amountWrappedToken);
	}

	/*
		@Description: burn a specific amount of wrappet asset to get out underlying asset

		@param address _to: the address that shall receive the underlying asset
		@param uint _amountWrappedToken: the amount of units of wrappet asset to burn

		@return uint _amountUnit: the amount of underlying asset received
	*/
	function withdrawWrappedAmount(address _to, uint _amountWrappedToken, bool _claimRewards) external override returns (uint _amountUnit) {
		address _delegateAddress = delegate1Address;
		bytes memory sig = abi.encodeWithSignature("withdrawWrappedAmount(address,uint256,bool)", _to, _amountWrappedToken, _claimRewards);

		assembly {
			let retPtr := mload(0x40)

			let success := delegatecall(gas(), _delegateAddress, add(sig, 0x20), mload(sig), retPtr, 0x20)

			if iszero(success) { revert(0,0) }

			_amountUnit := mload(retPtr)
		}

		emit Withdrawal(_to, _amountWrappedToken);
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


    function transfer(address _to, uint256 _value) external override returns (bool success) {
    	(success, ) = delegate3Address.delegatecall(abi.encodeWithSignature("transfer(address,uint256)", _to, _value));
    	require(success);

        emit Transfer(msg.sender, _to, _value);
    }

    function approve(address _spender, uint256 _value) external override returns (bool success) {
        internalAllowance[msg.sender][_spender] = _value;

        emit Approval(msg.sender, _spender, _value);

        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) external override returns (bool success) {
    	(success, ) = delegate3Address.delegatecall(abi.encodeWithSignature("transferFrom(address,address,uint256)", _from, _to, _value));
    	require(success);

        emit Transfer(_from, _to, _value);
    }

    //-----------------------E-I-P-3-1-6-5---f-l-a-s-h-l-o-a-n---f-u-n-c-t-i-o-n-a-l-i-t-y-----------------


    function maxFlashLoan(
        address token
    ) external view override returns (uint256) {
    	require(token == address(this));
    	uint _flashLoanFee = internalFlashLoanFee;
    	/*
			Theoretically it would be safe to have the maxFlashLoan be
			(uint256(-1) - internalTotalSupply).div(_flashLoanFee.add(totalSBPS)).mul(totalSBPS)
			but it doesn't hurt to have a lower maximum than the theoretical absolute maximum
			having a lower maximum flash loan amount may help prevent the occurance of edge case scenerios
			thus it may be beneficial to have maxFlashLoan return
			(uint256(-1) - internalTotalSupply).div(_flashLoanFee.add(totalSBPS))
    	*/
    	return (uint256(-1) - internalTotalSupply).div(_flashLoanFee.add(totalSBPS));
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
    	(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
    		"flashLoan(address,address,uint256,bytes)",
    		address(receiver),
    		token,
    		amount,
    		data
    	));
    	require(success);
    }

    //-----------r-e-w-a-r-d---a-s-s-e-t---d-i-s-t-r-i-b-u-t-i-o-n---m-e-c-h-a-n-i-s-m---------

	/*
		@Description: force the NGBwrapper to collect reward assets for msg.sender
	*/
	function forceRewardsCollection() external override {
		(bool success, ) = delegate1Address.delegatecall(abi.encodeWithSignature("forceRewardsCollection()"));
		require(success);
	}

	/*
		@Description: register as a distribution account,
			should only be done by contracts wishing to distribute rewards correctly among depositors
	*/
	function registerAsDistributionAccount() external override {
		internalIsDistributionAccount[msg.sender] = true;
	}

	/*
		@Description: remove registration as distribution account,
			receive back all funds that had not been distributed
	*/
	function delistDistributionAccount() external override {
		uint len = internalRewardsAssets.length;
		for (uint8 i = 0; i < len; i++) {
			address _rewardsAsset = internalImmutableRewardsAssets[i];
			uint dividend = internalDistributionAccountRewards[i][msg.sender];
			internalDistributionAccountRewards[i][msg.sender] = 0;
			IERC20(_rewardsAsset).safeTransfer(msg.sender, dividend);
		}
		internalIsDistributionAccount[msg.sender] = false;
	}

	/*
		@Description: change the amount of bond and yield in a subaccount

		@param address _claimRewards: pass true to enter the claimRewards modifier
			for either msg.sender or the _FCPaddr, depending on if _FCPaddr == address(0)
		@param address _subAccount: the sub account owner address, receives rewards
		@param address _FCPaddr: the address of the FCP for which sub account balances are held
		@param int _changeYield: change in the yield amount in the sub account,
			final amount - initial amount
		@param int _changeBond: the change in the bond amount for the sub account,
			final amount - initial amount
	*/
	function editSubAccountPosition(
		bool _claimRewards,
		address _subAccount,
		address _FCPaddr,
		int _changeYield,
		int _changeBond
	) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"editSubAccountPosition(bool,address,address,int256,int256)",
			_claimRewards,
			_subAccount,
			_FCPaddr,
			_changeYield,
			_changeBond
		));
		require(success);
	}

	/*
		@Description: force rewards for a sub account to be distributed

		@param bool _claimRewards: pass true to enter the claimRewards modifier for the distribution account
		@param address _distributionAccount: the address of the distribution account for the sub account
		@param address _subAccount: the address that is the owner of the sub account and shall receive the rewards
		@param address _FCPaddr: the address of the FCP contract for which the sub account amounts are denominated
	*/
	function forceClaimSubAccountRewards(
		bool _claimRewards,
		address _distributionAccount,
		address _subAccount,
		address _FCPaddr
	) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"forceClaimSubAccountRewards(bool,address,address,address)",
			_claimRewards,
			_distributionAccount,
			_subAccount,
			_FCPaddr
		));
		require(success);
	}

    /*
		@Description: force rewards for an FCP direct sub account to be claimed
			only callable by FCP contracts

		@param bool _inPayoutPhase: true if the FCP is in the payout phase
		@param bool _claimRewards: true if the FCP should claim its rewards
		@param address _subAcct: the owner of the FCP Direct sub account for which to claim rewards
		@param uint _yield: the yield amount in the ZCB & YT position of _subAcct
		@param uint _wrappedClaim: the effective amount of the wrapper asset used to calculate the
			distribution of rewards to _subAcct
    */
	function FCPDirectClaimSubAccountRewards(
		bool _inPayoutPhase,
		bool _claimRewards,
		address _subAcct,
		uint _yield,
		uint _wrappedClaim
	) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"FCPDirectClaimSubAccountRewards(bool,bool,address,uint256,uint256)",
			_inPayoutPhase,
			_claimRewards,
			_subAcct,
			_yield,
			_wrappedClaim
		));
		require(success);
	}


    /*
		@Description: force rewards for an FCP direct sub account to be claimed
			only callable by FCP contracts

		@param bool _inPayoutPhase: true if the FCP is in the payout phase
		@param bool _claimRewards: true if the FCP should claim its rewards
		@param address[2] _subAccts: the owners of the FCP direct sub accounts for which to claim rewards
		@param uint[2] _yieldArr: [yield balance of subAcct0, yield balance of subAcct1]
		@param uint[2] _wrappedClaims: the effective amount of the wrapper asset used to calculate the
			distribution for the sub accounts
    */
    function FCPDirectDoubleClaimSubAccountRewards(
        bool _inPayoutPhase,
        bool _claimRewards,
        address[2] calldata _subAccts,
        uint[2] calldata _yieldArr,
        uint[2] calldata _wrappedClaims
    ) external override {
    	(bool success, ) = delegate3Address.delegatecall(abi.encodeWithSignature(
    		"FCPDirectDoubleClaimSubAccountRewards(bool,bool,address[2],uint256[2],uint256[2])",
    		_inPayoutPhase,
    		_claimRewards,
    		_subAccts,
    		_yieldArr,
    		_wrappedClaims
    	));
    	require(success);
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

	function rewardsAssets(uint _index) external view override returns(address) {
		return internalRewardsAssets[_index];
	}

	function immutableRewardsAssets(uint _index) external view override returns(address) {
		return internalImmutableRewardsAssets[_index];
	}

	function prevContractBalance(uint _index) external view override returns(uint) {
		return internalPrevContractBalance[_index];
	}

	function totalRewardsPerWasset(uint _index) external view override returns(uint) {
		return internalTotalRewardsPerWasset[_index];
	}

	function totalRewardsPerWassetUponActivation(uint _index) external view override returns(uint) {
		return internalTRPWuponActivation[_index];
	}

	function prevTotalRewardsPerWasset(uint _index, address _wassetHolder) external view override returns(uint) {
		return internalPrevTotalRewardsPerWasset[_index][_wassetHolder];
	}

	function numRewardsAssets() external view override returns(uint) {
		return internalRewardsAssets.length;
	}

	function isDistributionAccount(address _addr) external view override returns(bool) {
		return internalIsDistributionAccount[_addr];
	}

	function distributionAccountRewards(uint _index, address _distributionAccount) external view override returns(uint) {
		return internalDistributionAccountRewards[_index][_distributionAccount];
	}

	function hasClaimedAllYTRewards(address _distributionAccount, address _subAccount, address _FCPaddr) external view override returns(bool) {
		return internalHasClaimedAllYTrewards[_distributionAccount][_subAccount][_FCPaddr];
	}

	function subAccountPrevTotalReturnsPerWasset(uint _index, address _distributionAccount, address _subAccount, address _FCPaddr) external view override returns(uint) {
		return internalSAPTRPW[_index][_distributionAccount][_subAccount][_FCPaddr];
	}

	function subAccountPositions(
		address _distributionAccount,
		address _subAccount, 
		address _FCPaddr
	) external view override returns(
		uint yield,
		int bond
	) {
		if (_distributionAccount == _FCPaddr) {
			require(address(IFixCapitalPool(_FCPaddr).wrapper()) == address(this));
			yield = IFixCapitalPool(_FCPaddr).balanceYield(_subAccount);
			bond = IFixCapitalPool(_FCPaddr).balanceBonds(_subAccount);
		}
		else {
			SubAccountPosition memory position = internalSubAccountPositions[_distributionAccount][_subAccount][_FCPaddr];
			yield = position.yield;
			bond = position.bond;
		}
	}

    //------------------------------------a-d-m-i-n----------------------------

    /*
		@Description: set the annual wrapper fee in super basis points
			half of all fees goes to owner, the other half goes to the treasury

		@param uint32 _SBPSRetained: the amount of super bips that are to be retained by
			the pool. You can think of it as if totalSBPS - _SBPSRetained is the annual
			asset management fee for a wrapper
    */
    function setInterestFee(uint32 _SBPSRetained) external onlyOwner override {
    	require(_SBPSRetained > 0 && _SBPSRetained <= totalSBPS);
    	SBPSRetained = _SBPSRetained;
    }

    /*
		@Description: set the percentage fee that is applied to all flashloans

		@param uint _flashLoanFee: the new fee percentage denominated in superbips which is to be applied to flashloans
    */
    function setFlashLoanFee(uint _flashLoanFee) external onlyOwner override {
    	internalFlashLoanFee = _flashLoanFee;
    }

    /*
		@Description: add an asset for which wrapped asset holders will earn LM rewards

		@param address _rewardsAsset: the new asset for which to start distribution of LM rewards
		@param uint8 _index: the index within the rewardsAddr array where the new rewards asset will be
    */
    function addRewardAsset(address _rewardsAsset) external override {
    	(bool success, ) = delegate3Address.delegatecall(abi.encodeWithSignature(
    		"addRewardAsset(address)",
    		_rewardsAsset
    	));
    	require(success);
    }

    /*
		@Description: deactivate a rewards asset
			any amount of this asset recived by this contract will sit dormant until activated

		@param uint _index: the index within the rewards asset array of the asset to deactivate
    */
    function deactivateRewardAsset(uint _index) external override {
    	(bool success, ) = delegate3Address.delegatecall(abi.encodeWithSignature(
    		"deactivateRewardAsset(uint256)",
    		_index
    	));
    	require(success);
    }

    /*
		@Description: reactivate a rewards asset,
			any amount of this asset henceforth received by this contract shall be distributed propotionally among
			wrapped asset holders

		@param uint _index: the index within the immutable rewards asset array of the asset to reactivate
    */
    function reactivateRewardAsset(uint _index) external onlyOwner override {
    	uint len = internalRewardsAssets.length;
    	require(_index < len);
    	internalRewardsAssets[_index] = internalImmutableRewardsAssets[_index];
    	internalTRPWuponActivation[_index] = internalTotalRewardsPerWasset[_index];
    }

    /*
		@Description: harvest the entirety of a reward asset to the owner & to fix finance, split 50/50
			this reward asset must not be listed within the immutableRewardsAssets array

		@param address _assetAddr: the address of the reward asset to harvest
	*/
	function harvestNonListedRewardAsset(address _assetAddr) external onlyOwner override {
		uint len = internalRewardsAssets.length;
		for (uint8 i = 0; i < len; i++) {
			require(internalImmutableRewardsAssets[i] != _assetAddr);
		}
		uint currentBal = IERC20(_assetAddr).balanceOf(address(this));
		IInfoOracle iorc = IInfoOracle(internalInfoOracleAddress);
		if (iorc.TreasuryFeeIsCollected()) {
			address sendTo = iorc.sendTo();
			uint toOwner = currentBal >> 1;
			IERC20(_assetAddr).safeTransfer(msg.sender, toOwner);
			IERC20(_assetAddr).safeTransfer(sendTo, currentBal - toOwner);
		}
		else {
			IERC20(_assetAddr).safeTransfer(msg.sender, currentBal);
		}
	}
}