pragma solidity >=0.6.5 <0.7.0;
import "./interfaces/IFixCapitalPool.sol";
import "./interfaces/IWrapper.sol";
import "./interfaces/IYieldToken.sol";
import "./interfaces/IZeroCouponBond.sol";
import "./interfaces/IERC20.sol";
import "./ERC20.sol";
import "./ZCB_YT_Deployer.sol";
import "./libraries/SafeMath.sol";
import "./libraries/SignedSafeMath.sol";
import "./helpers/Ownable.sol";
import "./helpers/nonReentrant.sol";

contract FixCapitalPool is IFixCapitalPool, Ownable, nonReentrant {
	using SafeMath for uint;
	using SignedSafeMath for int;

	//set to true after maturity
	//once true users may redeem ZCBs for underlying
	bool public override inPayoutPhase;

	//timestamp at which payout phase may be entered
	uint64 public override maturity;

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

	address public override vaultFactoryAddress;

	//data for flashloans
    bytes32 public constant CALLBACK_SUCCESS = keccak256("FCPFlashBorrower.onFlashLoan");
    uint256 public flashLoanFee; // denominated in super bips
	//SBPS == super bips == 1/100th of a bip
	//100 * 10_000 == 1_000_000
	uint32 private constant totalSBPS = 1_000_000;
    uint256 constant MAX_YIELD_FLASHLOAN = 2**250 / totalSBPS;
    int256 constant MAX_BOND_FLASHLOAN = 2**250 / int(totalSBPS);

    address public override treasuryAddress;

    /*
		init
    */
	constructor(
		address _wrapper,
		uint64 _maturity,
		address _ZCB_YTdeployerAddr,
		address _treasuryAddress
	) public {
		IWrapper temp = IWrapper(_wrapper);
		wrapper = temp;
		IERC20 temp2 = IERC20(temp.underlyingAssetAddress());
		underlyingAssetAddress = address(temp2);
		maturity = _maturity;
		yieldTokenAddress = ZCB_YT_Deployer(_ZCB_YTdeployerAddr).deployYT(_wrapper, _maturity);
		zeroCouponBondAddress = ZCB_YT_Deployer(_ZCB_YTdeployerAddr).deployZCB(_wrapper, _maturity);
		treasuryAddress = _treasuryAddress;
		flashLoanFee = 100; //default flashloan fee of 100 super bips or 1 basis point or 0.01%
	}

	modifier beforePayoutPhase() {
		require(!inPayoutPhase);
		_;
	}

	/*
		@Description: find the amount of wrapped token that the user may withdraw from the fix capital pool
	*/
	function wrappedTokenFree(address _owner) public view override returns (uint wrappedTknFree) {
		wrappedTknFree = balanceYield[_owner];
		int bondBal = balanceBonds[_owner];
		if (bondBal < 0){
			if (inPayoutPhase){
				uint toSub = uint(-bondBal).mul(1 ether);
				toSub = toSub/maturityConversionRate + (toSub%maturityConversionRate  == 0 ? 0 : 1);
				wrappedTknFree = wrappedTknFree.sub(toSub);
			}
			else
				wrappedTknFree = wrappedTknFree.sub(wrapper.UnitAmtToWrappedAmt_RoundUp(uint(-bondBal)));
		}
	}

	/*
		@Description: send wrapped asest to this fix capital pool, receive ZCB & YT

		@param address _to: the address that shall receive the ZCB and YT
		@param uint _amountWrappedTkn: the amount of wrapped asset to deposit
	*/
	function depositWrappedToken(address _to, uint _amountWrappedTkn) external override beforePayoutPhase {
		wrapper.transferFrom(msg.sender, address(this), _amountWrappedTkn);
		balanceYield[_to] += _amountWrappedTkn;
	}

	/*
		@Description: return ZCB & YT and receive wrapped asset

		@param address _to: the address that shall receive the output
		@param uint _amountWrappedTkn: the amount of wrapped asset to withdraw
		@param bool _unwrap: if true - wrapped asset will be sent to _to address
			otherwise underlyingAsset will be sent
	*/
	function withdraw(address _to, uint _amountWrappedTkn, bool _unwrap) external override beforePayoutPhase {
		require(wrappedTokenFree(msg.sender) >= _amountWrappedTkn);
		balanceYield[msg.sender] -= _amountWrappedTkn;
		if (_unwrap)
			wrapper.withdrawWrappedAmount(_to, _amountWrappedTkn);
		else
			wrapper.transfer(_to, _amountWrappedTkn);
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
		uint freeToMove = wrappedTokenFree(msg.sender);
		balanceYield[msg.sender] -= freeToMove;
		if (_unwrap)
			wrapper.withdrawWrappedAmount(_to, freeToMove);
		else
			wrapper.transfer(_to, freeToMove);
	}

	/*
		@Description: after the maturity call this function to redeem ZCBs at a ratio of 1:1 with the
			underlying asset, pays out in wrapped asset

		@param address _to: the address that shall receive the wrapped asset
		@param bool _unwrap: if true - wrapped asset will be sent to _to address
			otherwise underlyingAsset will be sent
	*/
	function claimBondPayout(address _to, bool _unwrap) external override {
		require(inPayoutPhase);
		uint freeToMove = wrappedTokenFree(msg.sender);
		int bondBal = balanceBonds[msg.sender];
		if (bondBal > 0) {
			freeToMove += uint(bondBal).mul(1 ether)/maturityConversionRate;
		}
		if (_unwrap)
			wrapper.withdrawWrappedAmount(_to, freeToMove);
		else
			wrapper.transfer(_to, freeToMove);
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
	}

	/*
		@Description: find the amount of Unwrapped Units an address will be able to claim at maturity
			if no yield is generated in the wrapper from now up to maturity

		@param address _owner: the address whose minimum balance at maturity is in question

		@return uint balance: the minimum possible value (denominated in Unit/Unwrapped amount) of _owner's
			position at maturity
	*/
	function minimumUnitAmountAtMaturity(address _owner) internal view returns (uint balance) {
		if (inPayoutPhase)
			balance = balanceYield[_owner]*maturityConversionRate/(1 ether);
		else
			balance = wrapper.WrappedAmtToUnitAmt_RoundDown(balanceYield[_owner]);
		int bondBal = balanceBonds[_owner];
		if (bondBal > 0)
			balance = balance.add(uint(bondBal));
		else
			balance = balance.sub(uint(-bondBal));
	}

    //--------------------M-a-r-g-i-n---F-u-n-c-t-i-o-n-a-l-i-t-y--------------------------------

    /*
		@Description: VaultFactory contract may mint new ZCB against collateral, to mint new ZCB the VaultFactory
			calls this function
	
		@param address _owner: address to credit new ZCB to
		@param uint _amount: amount of ZCB to credit to _owner
    */
	function mintZCBTo(address _owner, uint _amount) external override {
		require(msg.sender == vaultFactoryAddress);
		balanceBonds[_owner] += int(_amount);
	}

	/*
		@Description: when margin position is closed/liquidated VaultFactory contract calls this function to
			remove ZCB from circulation

		@param address _owner: address to take ZCB from
		@param uint _amount: the amount of ZCB to remove from cirulation		
	*/
	function burnZCBFrom(address _owner, uint _amount) external override {
		require(msg.sender == vaultFactoryAddress);
		require(minimumUnitAmountAtMaturity(_owner) >= _amount);
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
		uint ratio = inPayoutPhase ? maturityConversionRate : wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		require(_bond >= 0 || _yield.mul(ratio)/(1 ether) >= uint(-_bond));
		uint yieldSender = balanceYield[msg.sender].sub(_yield);
		int bondSender = balanceBonds[msg.sender].sub(_bond);
		require(bondSender >= 0 || yieldSender.mul(ratio)/(1 ether) >= uint(-bondSender));
		balanceYield[msg.sender] = yieldSender;
		balanceBonds[msg.sender] = bondSender;
		balanceYield[_to] += _yield;
		balanceBonds[_to] += _bond;
	}

	/*
		@Description: transfer a ZCB + YT position from one address to another address

		@param address _from: the address that shall send the position
		@param address _to: the address that shall receive the position
		@param uint _yield: the amount change in the balanceYield mapping
		@param int _bond: the amount change in the balanceBonds mapping
	*/
	function transferPositionFrom(address _from, address _to, uint _yield, int _bond) external override {
		//ensure position has positive minimum value at maturity
		uint ratio = inPayoutPhase ? maturityConversionRate : wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint unitAmtYield = _yield.mul(ratio)/(1 ether);
		require(_bond >= 0 || unitAmtYield >= uint(-_bond));
		uint yieldFrom = balanceYield[_from].sub(_yield);
		int bondFrom = balanceBonds[_from].sub(_bond);
		require(bondFrom >= 0 || yieldFrom.mul(ratio)/(1 ether) >= uint(-bondFrom));

		//decrement approval of ZCB
		uint unitAmtZCB = _bond > 0 ? unitAmtYield.add(uint(_bond)) : unitAmtYield.sub(uint(-_bond));
		IZeroCouponBond(zeroCouponBondAddress).decrementAllowance(_from, msg.sender, unitAmtZCB);

		//decrement approval of YT
		IYieldToken(yieldTokenAddress).decrementAllowance(_from, msg.sender, _yield);

		balanceYield[_from] = yieldFrom;
		balanceBonds[_from] = bondFrom;
		balanceYield[_to] += _yield;
		balanceBonds[_to] += _bond;
	}

	//---------------------------Z-e-r-o---C-o-u-p-o-n---B-o-n-d----------------

	/*
		@Description: this fucntion is used to get balance of ZCB

		@param address _owner: the account for which to find zcb balance

		@return uint: the balance of ZCB of _owner
	*/
	function totalBalanceZCB(address _owner) external view override returns (uint) {
		return minimumUnitAmountAtMaturity(_owner);
	}

	/*
		@Description: zero coupon bond contract must call this function to transfer zcb between addresses

		@param address _from: the address to deduct ZCB from
		@param address _to: the address to send 
	*/
	function transferZCB(address _from, address _to, uint _amount) external override {
		require(msg.sender == zeroCouponBondAddress);

		int intAmount = int(_amount);
		require(intAmount >= 0);
		balanceBonds[_to] = balanceBonds[_to].add(intAmount);
		balanceBonds[_from] = balanceBonds[_from].sub(intAmount);

		//ensure that _from address's position may be cashed out to a positive amount of wrappedToken
		//if it cannot the following call will revert this tx
		minimumUnitAmountAtMaturity(_from);
	}

	//---------------------------Y-i-e-l-d---T-o-k-e-n-----------------------

	/*
		@Description: yield token contract must call this function to move yield token between addresses

		@param address _from: the address to deduct YT from
		@param address _to: the address to credit YT to
		@param uint _amount: the amount of YT to move between _from and _to
			*denominated in wrapped asset*
	*/
	function transferYield(address _from, address _to, uint _amount) external override {
		require(msg.sender == yieldTokenAddress);
		require(balanceYield[_from] >= _amount);
		uint _amountATkn = inPayoutPhase ? _amount.mul(maturityConversionRate)/(1 ether) : wrapper.WrappedAmtToUnitAmt_RoundDown(_amount);
		balanceYield[_from] -= _amount;
		balanceYield[_to] += _amount;
		balanceBonds[_from] += int(_amountATkn);
		balanceBonds[_to] -= int(_amountATkn);

		//ensure that _from address's position may be cashed out to a positive amount of wrappedToken
		//if it cannot the following call will revert this tx
		minimumUnitAmountAtMaturity(_from);
	}

	//---------------------------------a-d-m-i-n------------------------------
	//when isFinalized, vaultFactoryAddress may not be changed
	bool public override isFinalized;

	/*
		@Description: before isFinalized admin may change the VaultFactory contract address
			the vaultFactoryAddress is allowed to mint and burn ZCB so users should be careful and observant of this

		@param address _vaultFactoryAddress: the address of the new bond minter contract that this fix capital pool
			will adhere to
	*/
	function setVaultFactoryAddress(address _vaultFactoryAddress) external override onlyOwner {
		require(!isFinalized);
		vaultFactoryAddress = _vaultFactoryAddress;
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
		uint ratio = wrapper.WrappedAmtToUnitAmt_RoundDown(1 ether);
		uint effectiveZCB = _amountYield.mul(ratio) / (1 ether);
		if (_amountBond >= 0) {
			effectiveZCB = effectiveZCB.add(uint(_amountBond));
		}
		else {
			effectiveZCB = effectiveZCB.sub(uint(-_amountBond));
		}
		uint _flashLoanFee = flashLoanFee;
		uint yieldFee;
		int bondFee;
		if (_amountYield > 0) {
			yieldFee = _amountYield.mul(_flashLoanFee) / totalSBPS;
			balanceYield[msg.sender] = balanceYield[msg.sender].add(_amountYield);
		}
		if (_amountBond != 0) {
			bondFee = _amountBond.mul(int(_flashLoanFee)) / int(totalSBPS);
			balanceBonds[msg.sender] = balanceBonds[msg.sender].add(_amountBond);
		}

		//decrement allowances
		IZeroCouponBond(zeroCouponBondAddress).decrementAllowance(address(_receiver), msg.sender, effectiveZCB);
		IYieldToken(yieldTokenAddress).decrementAllowance(address(_receiver), msg.sender, _amountYield);

		bytes32 out = _receiver.onFlashLoan(msg.sender, _amountYield, _amountBond, yieldFee, bondFee, _data);
		require(out == CALLBACK_SUCCESS);

		address _owner = owner;
		address _treasuryAddress = treasuryAddress;
		if (_amountYield > 0) {
			balanceYield[msg.sender] = balanceYield[msg.sender].sub(_amountYield).sub(yieldFee);
			uint dividend = yieldFee >> 1;
			balanceYield[_treasuryAddress] = balanceYield[_treasuryAddress].add(dividend);
			balanceYield[_owner] = balanceYield[_owner].add(yieldFee - dividend);
		}
		if (_amountBond != 0) {
			balanceBonds[msg.sender] = balanceBonds[msg.sender].sub(_amountBond).sub(bondFee);
			int dividend = bondFee / 2;
			balanceBonds[_treasuryAddress] = balanceBonds[_treasuryAddress].add(dividend);
			balanceBonds[_owner] = balanceBonds[_owner].add(bondFee - dividend);
		}
	    return true;
    }
}