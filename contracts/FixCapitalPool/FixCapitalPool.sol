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

contract FixCapitalPool is IFixCapitalPool, Ownable, nonReentrant {
	using SafeMath for uint;
	using SignedSafeMath for int;

	//set to true after maturity
	//once true users may redeem ZCBs for underlying
	bool public override inPayoutPhase;

	//timestamp at which payout phase may be entered
	uint40 public override maturity;

	//(1 ether) * amountUnit / wrappedToken
	uint public override maturityConversionRate;

	IWrapper public override wrapper;

	address public override underlyingAssetAddress;

	/*
		These 2 mappings along with the conversion ratio between Unit amounts and
		wrapped amounts keep track of a user's balance of ZCB and YT

		balanceYield refers to the amount of wrapped assets which have been credited to a user.
		When a user depsoits X amount of wrapped asset balanceYield[user] += X;
		balanceYield is denominated in wrapped asset amounts
		balanceBonds refers to the amount of ZCBs that a user is indebted against their 
		position of wrapped assets stored in balanceYield.
		The values in balanceBonds may be positive or negative.
		A positive balance in balanceBonds indicates that a user extra ZCB ontop of
		how ever much wrapped asset they own in balanceYield.
		A negative balance in balanceBonds indicates that a user is indebted ZCB against their
		wrapped assets held in balanceYield.
		The current value in Uint amount of a user's balance of wrapped asset stored in balanceYield 
		may never be greater than a user's negatie balance in balanceBonds

		If a user would like to sell more ZCB against the underlying asset than the face unit value of
		underlying asset they must use open a vault with the VaultFactory contract to access margin
	*/
	mapping(address => int) public override balanceBonds;
	mapping(address => uint) public override balanceYield;

	address public override yieldTokenAddress;
	address public override zeroCouponBondAddress;

	mapping(address => bool) public override whitelistedVaultFactories;

	//data for flashloans
    bytes32 public constant CALLBACK_SUCCESS = keccak256("FCPFlashBorrower.onFlashLoan");
    uint256 public flashLoanFee; // denominated in super bips
	//SBPS == super bips == 1/100th of a bip
	//100 * 10_000 == 1_000_000
	uint32 private constant totalSBPS = 1_000_000;
    uint256 constant MAX_YIELD_FLASHLOAN = 2**250 / totalSBPS;
    int256 constant MAX_BOND_FLASHLOAN = 2**250 / int(totalSBPS);

    address public override infoOracleAddress;

    uint[] public override TotalRewardsPerWassetAtMaturity;

    /*
		init
    */
	constructor(
		address _wrapper,
		uint40 _maturity,
		address _ZCB_YTdeployerAddr,
		address _infoOracleAddress
	) public {
		IWrapper temp = IWrapper(_wrapper);
		wrapper = temp;
		temp.registerAsDistributionAccount();
		IERC20 temp2 = IERC20(temp.underlyingAssetAddress());
		underlyingAssetAddress = address(temp2);
		maturity = _maturity;
		yieldTokenAddress = ZCB_YT_Deployer(_ZCB_YTdeployerAddr).deployYT(_wrapper, _maturity);
		zeroCouponBondAddress = ZCB_YT_Deployer(_ZCB_YTdeployerAddr).deployZCB(_wrapper, _maturity);
		infoOracleAddress = _infoOracleAddress;
		flashLoanFee = 100; //default flashloan fee of 100 super bips or 1 basis point or 0.01%
	}

	modifier beforePayoutPhase() {
		require(!inPayoutPhase);
		_;
	}

	modifier isInPayoutPhase() {
		require(inPayoutPhase);
		_;
	}

	/*
		@Description: allow easy access to last update without going to wrapper contract directly
	*/
	function lastUpdate() external view override returns(uint) {
		return wrapper.lastUpdate();
	}

	/*
		@Description: return the amount of the bond value for which the ZCB contained is equal to
			the ZCB contained in (1 ether) of the yield value
	*/
	function currentConversionRate() external view override returns(uint conversionRate) {
		return inPayoutPhase ? maturityConversionRate : wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
	}

	/*
		@Description: send wrapped asest to this fix capital pool, receive ZCB & YT

		@param address _to: the address that shall receive the ZCB and YT
		@param uint _amountWrappedTkn: the amount of wrapped asset to deposit
	*/
	function depositWrappedToken(address _to, uint _amountWrappedTkn) external override beforePayoutPhase {
		IWrapper wrp = wrapper;
		uint yield = balanceYield[_to];
		wrp.transferFrom(msg.sender, address(this), _amountWrappedTkn);
		wrp.FCPDirectClaimSubAccountRewards(false, false, _to, yield, yield);
		balanceYield[_to] = yield.add(_amountWrappedTkn);
	}

	/*
		@Description: return ZCB & YT and receive wrapped asset

		@param address _to: the address that shall receive the output
		@param uint _amountWrappedTkn: the amount of wrapped asset to withdraw
		@param bool _unwrap: if true - wrapped asset will be sent to _to address
			otherwise underlyingAsset will be sent
	*/
	function withdraw(address _to, uint _amountWrappedTkn, bool _unwrap) external override beforePayoutPhase {
		IWrapper wrp = wrapper;
		uint yield = balanceYield[msg.sender];
		int bond = balanceBonds[msg.sender];
		//conversionRate doesn't matter if bond >= 0, save gas if we can by not fetching the conv rate
		uint conversionRate = bond < 0 ? wrp.WrappedAmtToUnitAmt_RoundDown(1 ether) : 0;
		require(maxWrappedWithdrawAmt(yield, bond, conversionRate) >= _amountWrappedTkn);
		if (_unwrap)
			wrp.withdrawWrappedAmount(_to, _amountWrappedTkn, true);
		else
			wrp.transfer(_to, _amountWrappedTkn);

		wrp.FCPDirectClaimSubAccountRewards(false, false, msg.sender, yield, yield);
		balanceYield[msg.sender] = yield.sub(_amountWrappedTkn);
	}

	/*
		@Description: return Min(balanceZCB, balanceYT) of both ZCB & YT and receive the corresponding
			amount of wrapped asset.
			Essentially this function is like withdraw except it always withdraws as much as possible

		@param address _to: the address that shall receive the output
		@param bool _unwrap: if true - wrapped asset will be sent to _to address
			otherwise underlyingAsset will be sent
	*/
	function withdrawAll(address _to, bool _unwrap) external override beforePayoutPhase {
		IWrapper wrp = wrapper;
		uint yield = balanceYield[msg.sender];
		int bond = balanceBonds[msg.sender];
		//conversionRate doesn't matter if bond >= 0, save gas if we can by not fetching the conv rate
		uint conversionRate = bond < 0 ? wrp.WrappedAmtToUnitAmt_RoundDown(1 ether) : 0;
		uint freeToMove = maxWrappedWithdrawAmt(yield, bond, conversionRate);
		if (_unwrap)
			wrp.withdrawWrappedAmount(_to, freeToMove, true);
		else
			wrp.transfer(_to, freeToMove);

		wrp.FCPDirectClaimSubAccountRewards(false, false, msg.sender, yield, yield);
		balanceYield[msg.sender] = yield.sub(freeToMove);
	}

	/*
		@Description: after the maturity call this function to redeem ZCBs at a ratio of 1:1 with the
			underlying asset, pays out in wrapped asset

		@param address _to: the address that shall receive the wrapped asset
		@param bool _unwrap: if true - wrapped asset will be sent to _to address
			otherwise underlyingAsset will be sent
	*/
	function claimBondPayout(address _to, bool _unwrap) external override isInPayoutPhase {
		IWrapper wrp = wrapper;
		uint yield = balanceYield[msg.sender];
		int bond = balanceBonds[msg.sender];
		uint payout = payoutAmount(yield, bond, maturityConversionRate);
		wrp.FCPDirectClaimSubAccountRewards(true, true, msg.sender, yield, payout);
		if (_unwrap)
			wrp.withdrawWrappedAmount(_to, payout, false);
		else
			wrp.transfer(_to, payout);
		delete balanceYield[msg.sender];
		delete balanceBonds[msg.sender];
	}

	/*
		@Description: after maturity call this funtion to send into payout phase
	*/
	function enterPayoutPhase() external override {
		require(!inPayoutPhase && block.timestamp >= maturity);
		inPayoutPhase = true;
		maturityConversionRate = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint len = wrapper.numRewardsAssets();
		len = len > type(uint8).max ? type(uint8).max : len;
		for (uint8 i = 0; i < len; i++) {
			TotalRewardsPerWassetAtMaturity.push(wrapper.totalRewardsPerWasset(i));
		}
	}

	/*
		@Description: returns the maximum wrapped amount of the wrapper asset that may be withdrawn by an account

		@param address _owner: the account for which to find the maximum wrapped amount that may be withdrawn

		@return uint wrappedTknFree: the maximum wrapped amount of the wrapper asset that may be withdawn
	*/
	function wrappedTokenFree(address _owner) external view override returns(uint wrappedTknFree) {
		uint conversionRate = inPayoutPhase ? maturityConversionRate : wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		return maxWrappedWithdrawAmt(balanceYield[_owner], balanceBonds[_owner], conversionRate);
	}

	/*
		@Description: find the amount of Unwrapped Units an address will be able to claim at maturity
			if no yield is generated in the wrapper from now up to maturity,
			if in payout phase the value returned will be the unit amount that could be claimed at maturity

		@param uint _yield: the yield amount associated with the ZCB & YT position
		@param int _bond: the bond amount associated with the ZCB & YT position
		@param uint _conversionRate: if before payout phase pass the value of the current conversion rate
			if in payout phase pass the value of the contract 'maturityConversionRate' variable

		@return uint balance: the minimum possible value (denominated in Unit/Unwrapped amount) of _owner's
			position at maturity
	*/
	function minimumUnitAmountAtMaturity(uint _yield, int _bond, uint _conversionRate) internal pure returns (uint balance) {
		require(_conversionRate > 0);
		balance = _yield.mul(_conversionRate) / (1 ether);
		balance = _bond > 0 ? balance.add(uint(_bond)) : balance.sub(uint(_bond.abs()));
	}

	/*
		@Description: find the amount of the IWrapper asset to payout based on the balance of yield and bond
			assumes that the FCP contract is in the payout phase

		@param uint _yield: the yield amount associated with the ZCB & YT position
		@param int _bond: the bond amount associated with the ZCB & YT position
		@param uint _maturityConversionRate: pass the value of the contract variable 'maturityConversionRate'

		@return uint: the amount of wrapped asset that should be paid out
	*/
	function payoutAmount(uint _yield, int _bond, uint _maturityConversionRate) internal pure returns(uint) {
		require(_maturityConversionRate > 0);
		uint ZCB = _yield.mul(_maturityConversionRate) / (1 ether);
		ZCB = _bond > 0 ? ZCB.add(uint(_bond)) : ZCB.sub(uint(_bond.abs()));
		return ZCB.mul(1 ether) / _maturityConversionRate;
	}

	/*
		@Description: find the amount of wrapped token that the user may withdraw from the fix capital pool

		@param uint _yield: the yield amount associated with the ZCB & YT position
		@param int _bond: the bond amount associated with the ZCB & YT position
		@param uint _conversionRate: if before payout phase pass the value of the current conversion rate
			if in payout phase pass the value of the contract 'maturityConversionRate' variable

		@return uint: the maximum wrapped amount of the wrapper asset that may be withdrawn
			for the owner of the ZCB & YT position
	*/
	function maxWrappedWithdrawAmt(uint _yield, int _bond, uint _conversionRate) internal pure returns(uint) {
		if (_bond < 0){
			uint unitAmtFree = (_yield.mul(_conversionRate) / (1 ether)).sub(uint(_bond.abs()));
			return unitAmtFree.mul(1 ether) / (_conversionRate);
		}
		else {
			return _yield;
		}
	}

    //--------------------M-a-r-g-i-n---F-u-n-c-t-i-o-n-a-l-i-t-y--------------------------------

    /*
		@Description: VaultFactory contract may mint new ZCB against collateral, to mint new ZCB the VaultFactory
			calls this function
	
		@param address _owner: address to credit new ZCB to
		@param uint _amount: amount of ZCB to credit to _owner
    */
	function mintZCBTo(address _owner, uint _amount) external override {
		require(whitelistedVaultFactories[msg.sender]);
		if (inPayoutPhase) {
			uint yield = balanceYield[_owner];
			int bond = balanceBonds[_owner];
			uint payout = payoutAmount(yield, bond, maturityConversionRate);
			wrapper.FCPDirectClaimSubAccountRewards(true, true, _owner, yield, payout);
		}
		balanceBonds[_owner] += int(_amount);
	}

	/*
		@Description: when margin position is closed/liquidated VaultFactory contract calls this function to
			remove ZCB from circulation

		@param address _owner: address to take ZCB from
		@param uint _amount: the amount of ZCB to remove from cirulation		
	*/
	function burnZCBFrom(address _owner, uint _amount) external override {
		require(whitelistedVaultFactories[msg.sender]);
		IWrapper wrp = wrapper;
		bool _inPayoutPhase = inPayoutPhase;
		uint yield = balanceYield[_owner];
		int bond = balanceBonds[_owner];
		uint conversionRate = _inPayoutPhase ? maturityConversionRate : wrp.WrappedAmtToUnitAmt_RoundDown(1 ether);
		require(minimumUnitAmountAtMaturity(yield, bond, conversionRate) >= _amount);
		if (_inPayoutPhase) {
			uint payout = payoutAmount(yield, bond, maturityConversionRate);
			wrapper.FCPDirectClaimSubAccountRewards(true, true, _owner, yield, payout);
		}
		balanceBonds[_owner] -= int(_amount);
	}

	/*
		@Description: transfer a ZCB + YT position to another address

		@param address _to: the address that shall receive the position
		@param uint _yield: the amount change in the balanceYield mapping
		@param int _bond: the amount change in the balanceBonds mapping
	*/
	function transferPosition(address _to, uint _yield, int _bond) external override {
		//ensure position has positive minimum value at maturity
		IWrapper wrp = wrapper; //gas savings
		bool _inPayoutPhase = inPayoutPhase; //gas savings
		uint ratio = _inPayoutPhase ? maturityConversionRate : wrp.WrappedAmtToUnitAmt_RoundDown(1 ether);
		require(_bond >= 0 || _yield.mul(ratio)/(1 ether) >= uint(-_bond));

		int bondSender = balanceBonds[msg.sender];
		int bondRec = balanceBonds[_to];

		uint[2] memory prevYields = [balanceYield[msg.sender], balanceYield[_to]];
		uint[2] memory wrappedClaims;

		if (_inPayoutPhase) {
			uint mcr = maturityConversionRate;
			wrappedClaims = [payoutAmount(prevYields[0], bondSender, mcr), payoutAmount(prevYields[1], bondRec, mcr)];
		}
		else {
			wrappedClaims = prevYields;
		}
		address[2] memory subAccts = [msg.sender, _to];
		wrp.FCPDirectDoubleClaimSubAccountRewards(_inPayoutPhase, true, subAccts, prevYields, wrappedClaims);
		require(bondSender >= _bond || prevYields[0].sub(_yield).mul(ratio)/(1 ether) >= uint(bondSender.sub(_bond).abs()));
		balanceYield[msg.sender] = prevYields[0] - _yield;
		balanceBonds[msg.sender] = bondSender - _bond;
		balanceYield[_to] = prevYields[1].add(_yield);
		balanceBonds[_to] = bondRec.add(_bond);
	}

	/*
		@Description: transfer a ZCB + YT position from one address to another address

		@param address _from: the address that shall send the position
		@param address _to: the address that shall receive the position
		@param uint _yield: the amount change in the balanceYield mapping
		@param int _bond: the amount change in the balanceBonds mapping
	*/
	function transferPositionFrom(address _from, address _to, uint _yield, int _bond) external override {
		IWrapper wrp = wrapper;
		bool _inPayoutPhase = inPayoutPhase;//gas savings
		uint[2] memory prevYields = [balanceYield[_from], balanceYield[_to]];
		int[2] memory prevBonds = [balanceBonds[_from], balanceBonds[_to]];
		uint ratio = _inPayoutPhase ? maturityConversionRate : wrp.WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint[2] memory wrappedClaims = _inPayoutPhase ? 
			[payoutAmount(prevYields[0], prevBonds[0], ratio), payoutAmount(prevYields[1], prevBonds[1], ratio)]
			: prevYields;
		address[2] memory subAccts = [_from, _to];
		wrp.FCPDirectDoubleClaimSubAccountRewards(_inPayoutPhase, true, subAccts, prevYields, wrappedClaims);

		require(prevBonds[0] >= _bond || prevYields[0].sub(_yield).mul(ratio)/(1 ether) >= uint(prevBonds[0].sub(_bond).abs()));

		if (_yield > 0) {
			//decrement approval of YT
			IYieldToken(yieldTokenAddress).decrementAllowance(_from, msg.sender, _yield);
			balanceYield[_from] = prevYields[0].sub(_yield);
			balanceYield[_to] = prevYields[1].add(_yield);
		}

		uint unitAmtYield = _yield.mul(ratio)/(1 ether);
		require(_bond >= 0 || unitAmtYield >= uint(-_bond));
		//decrement approval of ZCB
		uint unitAmtZCB = _bond > 0 ? unitAmtYield.add(uint(_bond)) : unitAmtYield.sub(uint(_bond.abs()));
		IZeroCouponBond(zeroCouponBondAddress).decrementAllowance(_from, msg.sender, unitAmtZCB);
		if (_bond != 0) {
			balanceBonds[_from] = prevBonds[0].sub(_bond);
			balanceBonds[_to] = prevBonds[1].add(_bond);
		}
	}

	//---------------------------Z-e-r-o---C-o-u-p-o-n---B-o-n-d----------------

	/*
		@Description: this fucntion is used to get balance of ZCB

		@param address _owner: the account for which to find zcb balance

		@return uint: the balance of ZCB of _owner
	*/
	function totalBalanceZCB(address _owner) external view override returns (uint) {
		uint conversionRate = inPayoutPhase ? maturityConversionRate : wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		return minimumUnitAmountAtMaturity(balanceYield[_owner], balanceBonds[_owner], conversionRate);
	}

	/*
		@Description: zero coupon bond contract must call this function to transfer zcb between addresses

		@param address _from: the address to deduct ZCB from
		@param address _to: the address to send 
	*/
	function transferZCB(address _from, address _to, uint _amount) external override {
		require(_amount <= uint(type(int256).max));
		uint conversionRate;
		int[2] memory prevBonds = [balanceBonds[_from], balanceBonds[_to]];
		if (inPayoutPhase) {
			conversionRate = maturityConversionRate;
			address[2] memory subAccts = [_from, _to];
			uint[2] memory prevYields = [balanceYield[_from], balanceYield[_to]];
			uint[2] memory wrappedClaims = [payoutAmount(prevYields[0], prevBonds[0], conversionRate), payoutAmount(prevYields[1], prevBonds[1], conversionRate)];
			wrapper.FCPDirectDoubleClaimSubAccountRewards(true, true, subAccts, prevYields, wrappedClaims);
		}
		else {
			conversionRate = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		}

		if (msg.sender != _from && msg.sender != zeroCouponBondAddress) {
			IZeroCouponBond(zeroCouponBondAddress).decrementAllowance(_from, msg.sender, _amount);
		}
		int intAmount = int(_amount);
		require(intAmount >= 0);
		int newFromBond = balanceBonds[_from].sub(intAmount);

		//ensure that _from address's position may be cashed out to a positive amount of wrappedToken
		//if it cannot the following call will revert this tx
		minimumUnitAmountAtMaturity(balanceYield[_from], newFromBond, conversionRate);

		balanceBonds[_to] = balanceBonds[_to].add(intAmount);
		balanceBonds[_from] = newFromBond;
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
		IWrapper wrp = wrapper;
		bool _inPayoutPhase = inPayoutPhase; //gas savings
		if (msg.sender != _from && msg.sender != yieldTokenAddress) {
			IYieldToken(yieldTokenAddress).decrementAllowance(_from, msg.sender, _amount);
		}
		uint conversionRate = _inPayoutPhase ? maturityConversionRate : wrp.WrappedAmtToUnitAmt_RoundDown(1 ether);
		int[2] memory prevBonds = [balanceBonds[_from], balanceBonds[_to]];
		address[2] memory subAccts = [_from, _to];
		uint[2] memory prevYields = [balanceYield[_from], balanceYield[_to]];
		uint[2] memory wrappedClaims = _inPayoutPhase ? 
			[payoutAmount(prevYields[0], prevBonds[0], conversionRate), payoutAmount(prevYields[1], prevBonds[1], conversionRate)]
			: prevYields;
		wrp.FCPDirectDoubleClaimSubAccountRewards(_inPayoutPhase, true, subAccts, prevYields, wrappedClaims);

		int amountBondChange = int(_amount.mul(conversionRate) / (1 ether)); //can be casted to int without worry bc '/ (1 ether)' ensures it fits

		//ensure that _from address's position may be cashed out to a positive amount of wrappedToken
		//if it cannot the following call will revert this tx
		minimumUnitAmountAtMaturity(prevYields[0].sub(_amount), prevBonds[0].add(amountBondChange), conversionRate);

		balanceYield[_from] = prevYields[0].sub(_amount);
		balanceBonds[_from] = prevBonds[0].add(amountBondChange);
		balanceYield[_to] = prevYields[1].add(_amount);
		balanceBonds[_to] = prevBonds[1].sub(amountBondChange);

	}

	//---------------------------------a-d-m-i-n------------------------------
	//when isFinalized, whitelistedVaultFactories mapping may not be changed
	bool public override isFinalized;

	/*
		@Description: before isFinalized admin may whitelist a VaultFactory contract address
			whitelisted VaultFactories are allowed to mint and burn ZCB so users should be careful and observant of this

		@param address _vaultFactoryAddress: the address of the new vault factory contract that this fix capital pool whitelist
	*/
	function setVaultFactoryAddress(address _vaultFactoryAddress) external override onlyOwner {
		require(!isFinalized);
		whitelistedVaultFactories[_vaultFactoryAddress] = true;
	}

	/*
		@Description: after this function is called by owner, the vaultFactoryAddress cannot be changed
	*/
	function finalize() external override onlyOwner {
		isFinalized = true;
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

		@return uint256 maxYield: the maximum amount in the balanceYield mapping that may be flashloaned
		@return int256 maxBond; the maximum amount in the balanceBonds mapping that may be flashloaned
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
    ) external override beforePayoutPhase noReentry returns (bool) {
		require(_amountYield <= MAX_YIELD_FLASHLOAN);
		require(_amountBond <= MAX_BOND_FLASHLOAN);
		uint ratio;
		uint _flashLoanFee = flashLoanFee;
		uint yieldFee;
		int bondFee;
		{
			uint prevYield = balanceYield[msg.sender];
			IWrapper wrp = wrapper;
			wrp.FCPDirectClaimSubAccountRewards(false, true, msg.sender, prevYield, prevYield);
			ratio = wrp.WrappedAmtToUnitAmt_RoundDown(1 ether);

			if (_amountYield > 0) {
				yieldFee = _amountYield.mul(_flashLoanFee) / totalSBPS;
				balanceYield[msg.sender] = prevYield.add(_amountYield);
			}
			if (_amountBond != 0) {
				bondFee = _amountBond.mul(int(_flashLoanFee)) / int(totalSBPS);
				balanceBonds[msg.sender] = balanceBonds[msg.sender].add(_amountBond);
			}
		}
		uint effectiveZCB = _amountYield.mul(ratio) / (1 ether);
		if (_amountBond >= 0) {
			effectiveZCB = effectiveZCB.add(uint(_amountBond));
		}
		else {
			effectiveZCB = effectiveZCB.sub(uint(-_amountBond));
		}

		//decrement allowances
		IZeroCouponBond(zeroCouponBondAddress).decrementAllowance(address(_receiver), msg.sender, effectiveZCB);
		IYieldToken(yieldTokenAddress).decrementAllowance(address(_receiver), msg.sender, _amountYield);

		bytes32 out = _receiver.onFlashLoan(msg.sender, _amountYield, _amountBond, yieldFee, bondFee, _data);
		require(out == CALLBACK_SUCCESS);

		address _owner = owner;
		address sendTo = IInfoOracle(infoOracleAddress).sendTo();
		if (_amountYield > 0) {
			balanceYield[msg.sender] = balanceYield[msg.sender].sub(_amountYield).sub(yieldFee);
			uint dividend = yieldFee >> 1;
			balanceYield[sendTo] = balanceYield[sendTo].add(dividend);
			balanceYield[_owner] = balanceYield[_owner].add(yieldFee - dividend);
		}
		if (_amountBond != 0) {
			balanceBonds[msg.sender] = balanceBonds[msg.sender].sub(_amountBond).sub(bondFee);
			int dividend = bondFee / 2;
			balanceBonds[sendTo] = balanceBonds[sendTo].add(dividend);
			balanceBonds[_owner] = balanceBonds[_owner].add(bondFee - dividend);
		}
	    return true;
    }
}