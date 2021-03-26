pragma solidity >=0.6.5 <0.7.0;
import "./interfaces/ICapitalHandler.sol";
import "./interfaces/IWrapper.sol";
import "./interfaces/IERC20.sol";
import "./ERC20.sol";
import "./YieldTokenDeployer.sol";
import "./libraries/SafeMath.sol";
import "./libraries/SignedSafeMath.sol";
import "./helpers/Ownable.sol";

contract CapitalHandler is ICapitalHandler, Ownable {
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
		underlying asset they must use open a vault with the MarginManager contract to access margin
	*/
	mapping(address => int) public override balanceBonds;
	mapping(address => uint) public override balanceYield;

	address public override yieldTokenAddress;

	address public override marginManagerAddress;

//--------ERC 20 Storage---------------

	uint8 public override decimals;
    mapping(address => mapping(address => uint256)) public override allowance;
    string public override name;
    string public override symbol;


    /*
		init
    */
	constructor(
		address _wrapper,
		uint64 _maturity,
		address _yieldTokenDeployer
	) public {
		IWrapper temp = IWrapper(_wrapper);
		wrapper = temp;
		decimals = temp.decimals();
		IERC20 temp2 = IERC20(temp.underlyingAssetAddress());
		underlyingAssetAddress = address(temp2);
		name = string(abi.encodePacked(temp2.name(),' zero coupon bond'));
		symbol = string(abi.encodePacked(temp2.symbol(), 'zcb'));
		maturity = _maturity;
		yieldTokenAddress = YieldTokenDeployer(_yieldTokenDeployer).deploy(_wrapper);
	}

	/*
		@Description: find the amount of wrapped token that the user may withdraw from the capital handler
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
		@Description: send wrapped asest to this capital handler, receive ZCB & YT

		@param address _to: the address that shall receive the ZCB and YT
		@param uint _amountWrappedTkn: the amount of wrapped asset to deposit
	*/
	function depositWrappedToken(address _to, uint _amountWrappedTkn) external override {
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
	function withdraw(address _to, uint _amountWrappedTkn, bool _unwrap) external override {
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
	function withdrawAll(address _to, bool _unwrap) external override {
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
	*/
	function claimBondPayout(address _to) external override {
		int bondBal = balanceBonds[msg.sender];
		require(inPayoutPhase && bondBal > 0);
		wrapper.withdrawWrappedAmount(_to, uint(bondBal).mul(1 ether)/maturityConversionRate);
		balanceBonds[msg.sender] = 0;
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

//-------------ERC20 Implementation----------------


	function balanceOf(address _owner) public view override returns (uint balance) {
		balance = minimumUnitAmountAtMaturity(_owner);
	}

    function transfer(address _to, uint256 _value) public override returns (bool success) {

        balanceBonds[msg.sender] -= int(_value);
        balanceBonds[_to] += int(_value);

        minimumUnitAmountAtMaturity(msg.sender);

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

    	balanceBonds[_from] -= int(_value);
    	balanceBonds[_to] += int(_value);

        minimumUnitAmountAtMaturity(_from);

        allowance[_from][msg.sender] -= _value;

        emit Transfer(_from, _to, _value);

        return true;
    }

    function totalSupply() public view override returns (uint _supply) {
    	_supply = wrapper.WrappedAmtToUnitAmt_RoundDown(wrapper.balanceOf(address(this)));
    }

    //--------------------M-a-r-g-i-n---F-u-n-c-t-i-o-n-a-l-i-t-y--------------------------------

    /*
		@Description: MarginManager contract may mint new ZCB against collateral, to mint new ZCB the MarginManager
			calls this function
	
		@param address _owner: address to credit new ZCB to
		@param uint _amount: amount of ZCB to credit to _owner
    */
	function mintZCBTo(address _owner, uint _amount) external override {
		require(msg.sender == marginManagerAddress);
		balanceBonds[_owner] += int(_amount);
	}

	/*
		@Description: when margin position is closed/liquidated MarginManager contract calls this function to
			remove ZCB from circulation

		@param address _owner: address to take ZCB from
		@param uint _amount: the amount of ZCB to remove from cirulation		
	*/
	function burnZCBFrom(address _owner, uint _amount) external override {
		require(msg.sender == marginManagerAddress);
		require(minimumUnitAmountAtMaturity(_owner) >= _amount);
		balanceBonds[_owner] -= int(_amount);
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
	//when isFinalized, marginManagerAddress may not be changed
	bool public override isFinalized;

	/*
		@Description: before isFinalized admin may change the MarginManager contract address
			the marginManagerAddress is allowed to mint and burn ZCB so users should be careful and observant of this

		@param address _marginManagerAddress: the address of the new bond minter contract that this capital handler
			will adhere to
	*/
	function setMarginManagerAddress(address _marginManagerAddress) external override onlyOwner {
		require(!isFinalized);
		marginManagerAddress = _marginManagerAddress;
	}

	/*
		@Description: after this function is called by owner, the marginManagerAddress cannot be changed
	*/
	function finalize() external override onlyOwner {
		isFinalized = true;
	}

}