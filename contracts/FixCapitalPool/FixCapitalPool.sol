// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "../interfaces/IFixCapitalPool.sol";
import "../interfaces/IWrapper.sol";
import "../interfaces/IYieldToken.sol";
import "../interfaces/IZeroCouponBond.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IInfoOracle.sol";
import "../libraries/SafeMath.sol";
import "../libraries/SignedSafeMath.sol";
import "../helpers/Ownable.sol";
import "../helpers/nonReentrant.sol";
import "./ZCB_YT/ZCB_YT_Deployer.sol";
import "./FCPDelegateParent.sol";

contract FixCapitalPool is IFixCapitalPool, FCPDelegateParent {
	using SafeMath for uint;
	using SignedSafeMath for int;

	address delegate1Address;
	address delegate2Address;

    /*
		init
    */
	constructor(
		address _wrapper,
		uint40 _maturity,
		address _ZCB_YTdeployerAddr,
		address _infoOracleAddress,
		address _delegate1Address,
		address _delegate2Address
	) public {
		IWrapper temp = IWrapper(_wrapper);
		internalWrapper = temp;
		temp.registerAsDistributionAccount();
		IERC20 temp2 = IERC20(temp.underlyingAssetAddress());
		internalUnderlyingAssetAddress = address(temp2);
		internalMaturity = _maturity;
		internalYieldTokenAddress = ZCB_YT_Deployer(_ZCB_YTdeployerAddr).deployYT(_wrapper, _maturity);
		internalZeroCouponBondAddress = ZCB_YT_Deployer(_ZCB_YTdeployerAddr).deployZCB(_wrapper, _maturity);
		internalInfoOracleAddress = _infoOracleAddress;
		flashLoanFee = 100; //default flashloan fee of 100 super bips or 1 basis point or 0.01%
		delegate1Address = _delegate1Address;
		delegate2Address = _delegate2Address;
	}

	//-------------v-i-e-w-s---f-o-r---F-C-P-D-a-t-a---d-a-t-a-----

	function inPayoutPhase() external view override returns (bool) {
		return internalInPayoutPhase;
	}

	function maturity() external view override returns(uint40) {
		return internalMaturity;
	}

	function maturityConversionRate() external view override returns(uint) {
		return internalMaturityConversionRate;
	}

	function underlyingAssetAddress() external view override returns(address) {
		return internalUnderlyingAssetAddress;
	}

	function balanceBonds(address _owner) external view override returns(int) {
		return internalBalanceBonds[_owner];
	}

	function balanceYield(address _owner) external view override returns(uint) {
		return internalBalanceYield[_owner];
	}

	function yieldTokenAddress() external view override returns(address) {
		return internalYieldTokenAddress;
	}

	function zeroCouponBondAddress() external view override returns(address) {
		return internalZeroCouponBondAddress;
	}

	function whitelistedVaultFactories(address _vaultFactoryAddress) external view override returns(bool whitelisted) {
		return internalWhitelistedVaultFactories[_vaultFactoryAddress];
	}

	function infoOracleAddress() external view override returns(address) {
		return internalInfoOracleAddress;
	}

	function wrapper() external view override returns(IWrapper) {
		return internalWrapper;
	}

	function TotalRewardsPerWassetAtMaturity(uint _index) external view override returns(uint) {
		return internalTotalRewardsPerWassetAtMaturity[_index];
	}

	function isFinalized() external view override returns(bool) {
		return internalIsFinalized;
	}

	/*
		@Description: allow easy access to last update without going to internalWrapper contract directly
	*/
	function lastUpdate() external view override returns(uint) {
		return internalWrapper.lastUpdate();
	}

	/*
		@Description: return the amount of the bond value for which the ZCB contained is equal to
			the ZCB contained in (1 ether) of the yield value
	*/
	function currentConversionRate() external view override returns(uint conversionRate) {
		return internalInPayoutPhase ? internalMaturityConversionRate : internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
	}

	/*
		@Description: send wrapped asest to this fix capital pool, receive ZCB & YT

		@param address _to: the address that shall receive the ZCB and YT
		@param uint _amountWrappedTkn: the amount of wrapped asset to deposit
	*/
	function depositWrappedToken(address _to, uint _amountWrappedTkn) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"depositWrappedToken(address,uint256)",
			_to,
			_amountWrappedTkn
		));
		require(success);
	}

	/*
		@Description: return ZCB & YT and receive wrapped asset

		@param address _to: the address that shall receive the output
		@param uint _amountWrappedTkn: the amount of wrapped asset to withdraw
		@param bool _unwrap: if true - wrapped asset will be sent to _to address
			otherwise underlyingAsset will be sent
	*/
	function withdraw(address _to, uint _amountWrappedTkn, bool _unwrap) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"withdraw(address,uint256,bool)",
			_to,
			_amountWrappedTkn,
			_unwrap
		));
		require(success);
	}

	/*
		@Description: return Min(balanceZCB, balanceYT) of both ZCB & YT and receive the corresponding
			amount of wrapped asset.
			Essentially this function is like withdraw except it always withdraws as much as possible

		@param address _to: the address that shall receive the output
		@param bool _unwrap: if true - wrapped asset will be sent to _to address
			otherwise underlyingAsset will be sent
	*/
	function withdrawAll(address _to, bool _unwrap) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"withdrawAll(address,bool)",
			_to,
			_unwrap
		));
		require(success);
	}

	/*
		@Description: after the internalMaturity call this function to redeem ZCBs at a ratio of 1:1 with the
			underlying asset, pays out in wrapped asset

		@param address _to: the address that shall receive the wrapped asset
		@param bool _unwrap: if true - wrapped asset will be sent to _to address
			otherwise underlyingAsset will be sent
	*/
	function claimBondPayout(address _to, bool _unwrap) external override {
		(bool success, ) = delegate1Address.delegatecall(abi.encodeWithSignature(
			"claimBondPayout(address,bool)",
			_to,
			_unwrap
		));
		require(success);
	}

	/*
		@Description: after maturity call this funtion to send into payout phase
	*/
	function enterPayoutPhase() external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature("enterPayoutPhase()"));
		require(success);
	}

	/*
		@Description: returns the maximum wrapped amount of the internalWrapper asset that may be withdrawn by an account

		@param address _owner: the account for which to find the maximum wrapped amount that may be withdrawn

		@return uint wrappedTknFree: the maximum wrapped amount of the internalWrapper asset that may be withdawn
	*/
	function wrappedTokenFree(address _owner) external view override returns(uint wrappedTknFree) {
		uint conversionRate = internalInPayoutPhase ? internalMaturityConversionRate : internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		return maxWrappedWithdrawAmt(internalBalanceYield[_owner], internalBalanceBonds[_owner], conversionRate);
	}

    //--------------------M-a-r-g-i-n---F-u-n-c-t-i-o-n-a-l-i-t-y--------------------------------

    /*
		@Description: VaultFactory contract may mint new ZCB against collateral, to mint new ZCB the VaultFactory
			calls this function

		@param address _owner: address to credit new ZCB to
		@param uint _amount: amount of ZCB to credit to _owner
    */
	function mintZCBTo(address _owner, uint _amount) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"mintZCBTo(address,uint256)",
			_owner,
			_amount
		));
		require(success);
	}

	/*
		@Description: when margin position is closed/liquidated VaultFactory contract calls this function to
			remove ZCB from circulation

		@param address _owner: address to take ZCB from
		@param uint _amount: the amount of ZCB to remove from cirulation		
	*/
	function burnZCBFrom(address _owner, uint _amount) external override {
		(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
			"burnZCBFrom(address,uint256)",
			_owner,
			_amount
		));
		require(success);
	}

	/*
		@Description: transfer a ZCB + YT position to another address

		@param address _to: the address that shall receive the position
		@param uint _yield: the amount change in the internalBalanceYield mapping
		@param int _bond: the amount change in the internalBalanceBonds mapping
	*/
	function transferPosition(address _to, uint _yield, int _bond) external override {
		(bool success, ) = delegate1Address.delegatecall(abi.encodeWithSignature(
			"transferPosition(address,uint256,int256)",
			_to,
			_yield,
			_bond
		));
		require(success);
	}

	/*
		@Description: transfer a ZCB + YT position from one address to another address

		@param address _from: the address that shall send the position
		@param address _to: the address that shall receive the position
		@param uint _yield: the amount change in the internalBalanceYield mapping
		@param int _bond: the amount change in the internalBalanceBonds mapping
	*/
	function transferPositionFrom(address _from, address _to, uint _yield, int _bond) external override {
		(bool success, ) = delegate1Address.delegatecall(abi.encodeWithSignature(
			"transferPositionFrom(address,address,uint256,int256)",
			_from,
			_to,
			_yield,
			_bond
		));
		require(success);
	}

	/*
		@Description: approve both ZCB & YT with one function call

		@param address _spender: the spender of the funds to set approval for
		@param uint _allowanceZCB: the new allowance of ZCB
		@param uint _allowanceYT: the new allowance of static YT
	*/
	function dualApprove(address _spender, uint _allowanceZCB, uint _allowanceYT) external override {
		IZeroCouponBond(internalZeroCouponBondAddress).setAllowance(msg.sender, _spender, _allowanceZCB);
		IYieldToken(internalYieldTokenAddress).setAllowance(msg.sender, _spender, _allowanceYT);
	}


	//---------------------------Z-e-r-o---C-o-u-p-o-n---B-o-n-d----------------

	/*
		@Description: this fucntion is used to get balance of ZCB

		@param address _owner: the account for which to find zcb balance

		@return uint: the balance of ZCB of _owner
	*/
	function totalBalanceZCB(address _owner) external view override returns (uint) {
		uint conversionRate = internalInPayoutPhase ? internalMaturityConversionRate : internalWrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		return minimumUnitAmountAtMaturity(internalBalanceYield[_owner], internalBalanceBonds[_owner], conversionRate);
	}

	/*
		@Description: zero coupon bond contract must call this function to transfer zcb between addresses

		@param address _from: the address to deduct ZCB from
		@param address _to: the address to send 
	*/
	function transferZCB(address _from, address _to, uint _amount) external override {
		(bool success, ) = delegate1Address.delegatecall(abi.encodeWithSignature(
			"transferZCB(address,address,uint256)",
			_from,
			_to,
			_amount
		));
		require(success);
	}

	//---------------------------Y-i-e-l-d---T-o-k-e-n-----------------------

	/*
		@Description: yield token contract must call this function to move yield token between addresses

		@param address _from: the address to deduct YT from
		@param address _to: the address to credit YT to
		@param uint _amount: the amount of YT to move between _from and _to
			*denominated in wrapped asset*
	*/
	function transferYT(address _from, address _to, uint _amount) external override {
		(bool success, ) = delegate1Address.delegatecall(abi.encodeWithSignature(
			"transferYT(address,address,uint256)",
			_from,
			_to,
			_amount
		));
		require(success);
	}

	//---------------------------------a-d-m-i-n------------------------------

	/*
		@Description: before isFinalized admin may whitelist a VaultFactory contract address
			whitelisted VaultFactories are allowed to mint and burn ZCB so users should be careful and observant of this

		@param address _vaultFactoryAddress: the address of the new vault factory contract that this fix capital pool whitelist
	*/
	function setVaultFactoryAddress(address _vaultFactoryAddress) external override onlyOwner {
		require(!internalIsFinalized);
		internalWhitelistedVaultFactories[_vaultFactoryAddress] = true;
	}

	/*
		@Description: after this function is called by owner, the vaultFactoryAddress cannot be changed
	*/
	function finalize() external override onlyOwner {
		internalIsFinalized = true;
	}

    /*
		@Description: set the percentage fee that is applied to all flashloans

		@param uint _flashLoanFee: the new fee percentage denominated in superbips which is to be applied to flashloans
    */
    function setFlashLoanFee(uint _flashLoanFee) external onlyOwner {
    	flashLoanFee = _flashLoanFee;
    }

	//------------------------------f-l-a-s-h-l-o-a-n-s--------------------------

	/*
		@Description: get the maximum amount of yield and bond that may be flashloaned

		@return uint256 maxYield: the maximum amount in the internalBalanceYield mapping that may be flashloaned
		@return int256 maxBond; the maximum amount in the internalBalanceBonds mapping that may be flashloaned
	*/
    function maxFlashLoan() external view override returns (uint256 maxYield, int256 maxBond) {
    	maxYield = MAX_YIELD_FLASHLOAN;
    	maxBond = MAX_BOND_FLASHLOAN;
    }

    /*
		@Description: the fee amount of yield and bonds that will be charged given specific amounts flashloaned

		@param uint256 _amountYield: the amount of yield flashloaned
		@param int256 _amountBond: the amount of bond flashloaned

		@return uint256 yieldFee: the fee in terms of yield
		@return int256 bondFee: the fee in bonds
    */
	function flashFee(
		uint256 _amountYield,
		int256 _amountBond
	) external view override returns (uint256 yieldFee, int256 bondFee) {
		require(_amountYield <= MAX_YIELD_FLASHLOAN);
		require(_amountBond <= MAX_BOND_FLASHLOAN);
		uint _flashLoanFee = flashLoanFee;
		yieldFee = _amountYield.mul(_flashLoanFee) / totalSBPS;
		bondFee = _amountBond.mul(int(_flashLoanFee)) / int(totalSBPS);
	}

	/*
		@Description: initiate flashloan

		@param IFCPFlashBorrower: the contract that shall borrow the funds
		@param uint256 _amountYield: the amount of yield to flashborrow
		@param int256 _amountBond: the amount of bond to flashborrow
		@param bytes calldata _data: the data to pass to the flash borrow receiver

		@return bool: true when flashloan is successful
    */
    function flashLoan(
        IFCPFlashBorrower _receiver,
        uint256 _amountYield,
        int256 _amountBond,
        bytes calldata _data
    ) external override returns (bool) {
    	(bool success, ) = delegate2Address.delegatecall(abi.encodeWithSignature(
    		"flashLoan(address,uint256,int256,bytes)",
    		_receiver,
    		_amountYield,
    		_amountBond,
    		_data
    	));
    	require(success);
    }
}