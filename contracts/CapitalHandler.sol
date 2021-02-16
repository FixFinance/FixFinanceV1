pragma solidity >=0.6.5 <0.7.0;
import "./interfaces/ICapitalHandler.sol";
import "./interfaces/IWrapper.sol";
import "./interfaces/IERC20.sol";
import "./ERC20.sol";
import "./YieldTokenDeployer.sol";
import "./libraries/SafeMath.sol";
import "./libraries/SignedSafeMath.sol";

contract CapitalHandler is ICapitalHandler {
	using SafeMath for uint;
	using SignedSafeMath for int;

	bool public override inPayoutPhase;

	uint64 public override maturity;

	//1e18 * amountUnit / wrappedToken
	uint public override maturityConversionRate;

	IWrapper public override wrapper;

	address public override underlyingAssetAddress;

	mapping(address => int) public override balanceBonds;

	mapping(address => uint) public override balanceYield;

	address public override yieldTokenAddress;

	address public override bondMinterAddress;

//--------ERC 20 Storage---------------

	uint8 public override decimals;
    mapping(address => mapping(address => uint256)) public override allowance;
    string public override name;
    string public override symbol;

//--------------functionality----------

	constructor(
		address _wrapper,
		uint64 _maturity,
		address _yieldTokenDeployer,
		address _bondMinterAddress
		) public {
		IWrapper temp = IWrapper(_wrapper);
		wrapper = temp;
		decimals = temp.decimals();
		IERC20 temp2 = IERC20(temp.underlyingAssetAddress());
		underlyingAssetAddress = address(temp2);
		name = string(abi.encodePacked(temp2.name(),' zero coupon bond'));
		symbol = string(abi.encodePacked(temp2.symbol(), 'zcb'));
		maturity = _maturity;
		(bool success , ) = _yieldTokenDeployer.call(abi.encodeWithSignature("deploy(address)", _wrapper));
		require(success);
		yieldTokenAddress = YieldTokenDeployer(_yieldTokenDeployer).addr();
		bondMinterAddress = _bondMinterAddress;
	}

	function wrappedTokenFree(address _owner) public view override returns (uint wrappedTknFree) {
		wrappedTknFree = balanceYield[_owner];
		int bondBal = balanceBonds[_owner];
		if (bondBal < 0){
			if (inPayoutPhase){
				uint toSub = uint(-bondBal).mul(1e18);
				toSub = toSub/maturityConversionRate + (toSub%maturityConversionRate  == 0 ? 0 : 1);
				wrappedTknFree = wrappedTknFree.sub(toSub);
			}
			else
				wrappedTknFree = wrappedTknFree.sub(wrapper.UnitAmtToWrappedAmt_RoundUp(uint(-bondBal)));
		}
	}

	function depositWrappedToken(address _to, uint _amountWrappedTkn) external override {
		wrapper.transferFrom(msg.sender, address(this), _amountWrappedTkn);
		balanceYield[_to] += _amountWrappedTkn;
	}

	function withdraw(address _to, uint _amountWrappedTkn, bool _unwrap) external override {
		require(wrappedTokenFree(msg.sender) >= _amountWrappedTkn);
		balanceYield[msg.sender] -= _amountWrappedTkn;
		if (_unwrap)
			wrapper.withdrawWrappedAmount(_to, _amountWrappedTkn);
		else
			wrapper.transfer(_to, _amountWrappedTkn);
	}

	function withdrawAll(address _to, bool _unwrap) external override {
		uint freeToMove = wrappedTokenFree(msg.sender);
		balanceYield[msg.sender] -= freeToMove;
		if (_unwrap)
			wrapper.withdrawWrappedAmount(_to, freeToMove);
		else
			wrapper.transfer(_to, freeToMove);
	}

	function claimBondPayout(address _to) external override {
		int bondBal = balanceBonds[msg.sender];
		require(block.timestamp >= maturity && bondBal > 0);
		wrapper.withdrawWrappedAmount(_to, uint(bondBal)*1e18/maturityConversionRate);
		balanceBonds[msg.sender] = 0;
	}

	function enterPayoutPhase() external override {
		require(!inPayoutPhase && block.timestamp >= maturity);
		inPayoutPhase = true;
		maturityConversionRate = wrapper.WrappedAmtToUnitAmt_RoundDown(1e18);
	}

	function minimumUnitAmountAtMaturity(address _owner) internal view returns (uint balance) {
		if (inPayoutPhase)
			balance = balanceYield[_owner]*maturityConversionRate/1e18;
		else
			balance = wrapper.WrappedAmtToUnitAmt_RoundDown(balanceYield[_owner]);
		int bondBal = balanceBonds[_owner];
		if (bondBal > 0)
			balance = balance.add(uint(bondBal));
		else
			balance = balance.sub(uint(-bondBal));
	}

	function mintZCBTo(address _owner, uint _amount) external override {
		require(msg.sender == bondMinterAddress);

		balanceBonds[_owner] += int(_amount);
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

//---------Yield Token--------------------

	function transferYield(address _from, address _to, uint _amount) external override {
		require(msg.sender == yieldTokenAddress);
		require(balanceYield[_from] >= _amount);
		uint _amountATkn = inPayoutPhase ? _amount.mul(maturityConversionRate)/1e18 : wrapper.WrappedAmtToUnitAmt_RoundDown(_amount);
		balanceYield[_from] -= _amount;
		balanceYield[_to] += _amount;
		balanceBonds[_from] += int(_amountATkn);
		balanceBonds[_to] -= int(_amountATkn);
		//ensure that _from address's position may be cashed out to a positive amount of wrappedToken
		//int bonds = balanceBonds[_from];
		//if (bonds >= 0) return;
		//uint bondsToWrappedToken = inPayoutPhase ? uint(-bonds).mul(maturityConversionRate)/1e18 : wrapper.UnitAmtToWrappedAmt_RoundUp(uint(-bonds));
		//require(balanceYield[_from] >= bondsToWrappedToken);
		minimumUnitAmountAtMaturity(_from);
	}


}