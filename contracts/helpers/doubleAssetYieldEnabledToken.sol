pragma solidity >=0.6.0;
import "../interfaces/ICapitalHandler.sol";
import "../interfaces/IYieldEnabled.sol";
import "../interfaces/IYieldToken.sol";
import "../interfaces/IERC20.sol";
import "./Ownable.sol";

abstract contract doubleAssetYieldEnabledToken is IERC20, Ownable, IYieldEnabled {
	
	address public ZCBaddress;
	address public YTaddress;

	//timestamp of last time this smart contract called optionContract.withdrawFunds()
	uint public lastWithdraw;
	//total amount of smallest denomination units of coin in this smart contract
	uint public override totalSupply;
	//10 ** decimals == the amount of sub units in a whole coin
	uint8 public override decimals = 18;
	//each user's balance of coins
	mapping(address => uint) public override balanceOf;
	//the amount of funds each address has allowed other addresses to spend on the first address's behalf
	//holderOfFunds => spender => amountOfFundsAllowed
	mapping(address => mapping(address => uint)) public override allowance;


	event DividendDistributed(
		address _claimer,
		address _to,
		uint _amtZCB,
		uint _amtYT
	);

	/*
		@Description: Assigns inital values and credits the owner of this contract with all coins
		@param address _ZCBaddress: the address of the ERC0 contract of asset1
		@param address _YTaddress: the address of the ERC20 contract of asset2
	*/
	function init(address _ZCBaddress, address _YTaddress) internal {
		require(contractBalanceAsset1.length == 0);
		ZCBaddress = _ZCBaddress;
		YTaddress = _YTaddress;
		contractBalanceAsset1.push(0);
		contractBalanceAsset2.push(0);
	}

    function transfer(address _to, uint256 _value) public override returns (bool success) {
        require(_value <= balanceOf[msg.sender]);

        claimDividendInternal(msg.sender, msg.sender);
        claimDividendInternal(_to, _to);

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

        claimDividendInternal(_from, _from);
        claimDividendInternal(_to, _to);

    	balanceOf[_from] -= _value;
    	balanceOf[_to] += _value;

        allowance[_from][msg.sender] -= _value;

        emit Transfer(_from, _to, _value);

        return true;
    }

    //-----------------i-m-p-l-e-m-e-n-t-s---y-i-e-l-d----------------

	/*
		@Description: allows token holders to claim their portion of the cashflow
	*/
	function claimDividend(address _to) external override {
		claimDividendInternal(msg.sender, _to);
	}

	/*
		@Description: Calls options.withdrawFunds() from this contract afterwards users may claim their own portion of the funds
			may be called once a day
		@return uint asset1: the amount of asset1 that has been credited to this contract
		@return uint asset2: the amount of asset2 that has been credited to this contract
	*/
	function contractClaimDividend() external virtual override;

	//--------y-i-e-l-d---i-m-p-l-e-m-e-n-t-a-t-i-o-n---h-e-l-p-e-r-s-------------------
	function claimDividendInternal(address _from, address _to) internal {
		uint mostRecent = lastClaim[_from];
		uint lastIndex = contractBalanceAsset1.length-1;	//gas savings
		if (mostRecent == lastIndex) return;
		uint _balanceOf = balanceOf[_from];	//gas savings
		lastClaim[_from] = lastIndex;
		if (_balanceOf == 0) return;
		uint _totalSupply = totalSupply;	//gas savings

		uint totalIncreace = contractBalanceAsset1[lastIndex] - contractBalanceAsset1[mostRecent];
		uint toSendZCB = totalIncreace * _balanceOf / _totalSupply;

		IERC20(ZCBaddress).transfer(_to, toSendZCB);
		ZCBdividendOut += toSendZCB;
		totalIncreace = contractBalanceAsset2[lastIndex] - contractBalanceAsset2[mostRecent];

		uint toSendYT = totalIncreace * _balanceOf / _totalSupply;

		IYieldToken(YTaddress).transfer_2(_to, toSendYT, false);
		YTdividendOut += toSendYT;

		emit DividendDistributed(_from, _to, toSendZCB, toSendYT);
	}

    /*
		every time lastWithdraw is updated another value is pushed to contractBalanceAsset1 as contractBalanceAsset2
		thus the length of contractBalanceAsset1 and contractBalanceAsset2 are always the same
		lastClaim represents the last index of the contractBalance arrays for each address at the most recent time that claimDividendInternal(said address) was called
	*/
	//lastClaim represents the last index of the contractBalance arrays for each address at the most recent time that claimDividendInternal(said address) was called
	mapping(address => uint) lastClaim;
	//holds the total amount of asset1 that this contract has generated in fees
	uint[] public contractBalanceAsset1;
	//holds the total amount of asset2 that this contract has genereated in fees
	uint[] public contractBalanceAsset2;
	//length of contractBalance arrays
	function length() public view returns (uint) {return contractBalanceAsset1.length;}
	uint ZCBdividendOut;
	uint YTdividendOut;
}