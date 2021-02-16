pragma experimental ABIEncoderV2;
pragma solidity >=0.6.5 <0.7.0;

import "./libraries/SafeMath.sol";
import "./interfaces/ICapitalHandler.sol";
import "./interfaces/IVaultHealth.sol";
import "./interfaces/IERC20.sol";
import "./helpers/Ownable.sol";

contract BondMinter is Ownable {
	using SafeMath for uint;

	struct Vault {
		address assetSupplied;
		address assetBorrowed;
		uint amountSupplied;
		uint amountBorrowed;
	}

	struct Liquidation {
		address assetSupplied;
		address assetBorrowed;
		uint amountSupplied;
		/*
			amountBorrowed is the one value from the Vault object not stored in liquidation
		*/
		address bidder;
		uint bidAmount;
		uint bidTimestamp;
	}

	//underlying asset => short interest
	mapping(address => uint) public shortInterestAllDurations;

	//asset => amount
	mapping(address => uint) public revenue;

	//user => vault index => vault
	mapping(address => Vault[]) public vaults;

	Liquidation[] public Liquidations;

	IVaultHealth public vaultHealthContract;

	address organizerAddress;

	event OpenVault(
		address assetSupplied,
		address assetBorrowed,
		uint amountSupplied,
		uint amountBorrowed		
	);

	event CloseVault(
		address owner,
		uint index
	);

	event Remove (
		address owner,
		uint index,
		uint amount
	);

	event Deposit (
		address owner,
		uint index,
		uint amount
	);

	event Borrow (
		address owner,
		uint index,
		uint amount
	);

	event Repay (
		address owner,
		uint index,
		uint amount
	);

	constructor(address _vaultHealthContract) public {
		vaultHealthContract = IVaultHealth(_vaultHealthContract);
	}

	//-----------------------------------views-------------------------------------

	function vaultsLength(address _owner) external view returns(uint) {
		return vaults[_owner].length;
	}

	function allVaults(address _owner) external view returns(Vault[] memory _vaults) {
		_vaults = vaults[_owner];
	}

	function liquidationsLength() external view returns (uint) {
		return Liquidations.length;
	}

	//-------------------------------------internal------------------------------------------

	function raiseShortInterest(address _capitalHandlerAddress, uint _amount) internal {
		address underlyingAssetAddress = ICapitalHandler(_capitalHandlerAddress).underlyingAssetAddress();
		uint temp = shortInterestAllDurations[underlyingAssetAddress].add(_amount);
		require(vaultHealthContract.maximumShortInterest(underlyingAssetAddress) >= temp);
		shortInterestAllDurations[underlyingAssetAddress] = temp;
	}

	function lowerShortInterest(address _capitalHandlerAddress, uint _amount) internal {
		address underlyingAssetAddress = ICapitalHandler(_capitalHandlerAddress).underlyingAssetAddress();
		shortInterestAllDurations[underlyingAssetAddress] = shortInterestAllDurations[underlyingAssetAddress].sub(_amount);
	}

	//------------------------------------vault management-----------------------------------

	function openVault(address _assetSupplied, address _assetBorrowed, uint _amountSupplied, uint _amountBorrowed) external {
		/*
			users can only borrow ZCBs
		*/
		require(_assetBorrowed != address(0));
		/*
			when chSupplyAddress == _assetSupplied
			the supplied asset is a zcb
		*/
		require(_assetSupplied != address(0));
		require(vaultHealthContract.satisfiesUpperLimit(_assetSupplied, _assetBorrowed, _amountSupplied, _amountBorrowed));

		IERC20(_assetSupplied).transferFrom(msg.sender, address(this), _amountSupplied);
		ICapitalHandler(_assetBorrowed).mintZCBTo(msg.sender, _amountBorrowed);
		raiseShortInterest(_assetBorrowed, _amountBorrowed);

		vaults[msg.sender].push(Vault(_assetSupplied, _assetBorrowed, _amountSupplied, _amountBorrowed));

		emit OpenVault(_assetSupplied, _assetBorrowed, _amountSupplied, _amountBorrowed);
	}

	function closeVault(uint _index, address _to) external {
		uint len = vaults[msg.sender].length;
		require(len > _index);
		Vault memory vault = vaults[msg.sender][_index];

		//burn borrowed ZCB
		if (vault.amountBorrowed > 0) {
			ICapitalHandler(vault.assetBorrowed).burnZCBFrom(msg.sender, vault.amountBorrowed);
			lowerShortInterest(vault.assetBorrowed, vault.amountBorrowed);
		}
		if (vault.amountSupplied > 0)
			IERC20(vault.assetSupplied).transfer(_to, vault.amountSupplied);

		if (len - 1 != _index)
			vaults[msg.sender][_index] = vaults[msg.sender][len - 1];
		delete vaults[msg.sender][len - 1];

		emit CloseVault(msg.sender, _index);
	}

	function remove(uint _index, uint _amount, address _to) external {
		require(vaults[msg.sender].length > _index);
		Vault memory vault = vaults[msg.sender][_index];

		require(vault.amountSupplied >= _amount);
		require(vaultHealthContract.satisfiesUpperLimit(
			vault.assetSupplied,
			vault.assetBorrowed,
			vault.amountSupplied - _amount,
			vault.amountBorrowed
		));

		vaults[msg.sender][_index].amountSupplied -= _amount;

		IERC20(vault.assetSupplied).transfer(_to, _amount);

		emit Remove(msg.sender, _index, _amount);
	}

	function deposit(address _owner, uint _index, uint _amount) external {
		require(vaults[_owner].length > _index);
		IERC20(vaults[_owner][_index].assetSupplied).transferFrom(msg.sender, address(this), _amount);
		vaults[_owner][_index].amountSupplied += _amount;

		emit Deposit(_owner, _index, _amount);
	}

	function borrow(uint _index, uint _amount, address _to) external {
		require(vaults[msg.sender].length > _index);
		Vault memory vault = vaults[msg.sender][_index];

		require(vaultHealthContract.satisfiesUpperLimit(
			vault.assetSupplied,
			vault.assetBorrowed,
			vault.amountSupplied,
			vault.amountBorrowed + _amount
		));

		vaults[msg.sender][_index].amountBorrowed += _amount;

		ICapitalHandler(vault.assetBorrowed).mintZCBTo(_to, _amount);
		raiseShortInterest(vault.assetBorrowed, _amount);

		emit Borrow(msg.sender, _index, _amount);
	}

	function repay(address _owner, uint _index, uint _amount) external {
		require(vaults[_owner].length > _index);
		require(vaults[_owner][_index].amountBorrowed >= _amount);
		address assetBorrowed = vaults[_owner][_index].assetBorrowed;
		ICapitalHandler(assetBorrowed).burnZCBFrom(msg.sender, _amount);
		lowerShortInterest(assetBorrowed, _amount);
		vaults[_owner][_index].amountBorrowed -= _amount;

		emit Repay(_owner, _index, _amount);
	}

	//----------------------------------------------Liquidations------------------------------------------

	function auctionLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _bid, uint _minOut) external {
		require(vaults[_owner].length > _index);
		Vault memory vault = vaults[_owner][_index];
		require(vault.assetBorrowed == _assetBorrowed);
		require(vault.assetSupplied == _assetSupplied);
		require(vault.amountBorrowed <= _bid);
		require(vault.amountSupplied >= _minOut);
		if (vaultHealthContract.satisfiesMiddleLimit(vault.assetSupplied, vault.assetBorrowed, vault.amountSupplied, vault.amountBorrowed)) {
			uint maturity = ICapitalHandler(vault.assetBorrowed).maturity();
			require(maturity < block.timestamp + (7 days));
		}
		//burn borrowed ZCB
		ICapitalHandler(vault.assetBorrowed).burnZCBFrom(msg.sender, vault.amountBorrowed);
		lowerShortInterest(vault.assetBorrowed, vault.amountBorrowed);
		//any surplus in the bid may be added as revenue
		if (_bid > vault.amountBorrowed){
			IERC20(vault.assetBorrowed).transferFrom(msg.sender, address(this), _bid - vault.amountBorrowed);
			revenue[vault.assetBorrowed] += _bid - vault.amountBorrowed;
		}

		delete vaults[_owner][_index];
		Liquidations.push(Liquidation(
			vault.assetSupplied,
			vault.assetBorrowed,
			vault.amountSupplied,
			msg.sender,
			_bid,
			block.timestamp
		));
	}

	function bidOnLiquidation(uint _index, uint _bid) external {
		require(Liquidations.length > _index);
		Liquidation memory liquidation = Liquidations[_index];
		require(_bid > liquidation.bidAmount);

		ICapitalHandler(liquidation.assetBorrowed).burnZCBFrom(msg.sender, _bid);
		ICapitalHandler(liquidation.assetBorrowed).mintZCBTo(liquidation.bidder, liquidation.bidAmount);
		ICapitalHandler(liquidation.assetBorrowed).mintZCBTo(address(this), _bid - liquidation.bidAmount);

		revenue[liquidation.assetBorrowed] += _bid - liquidation.bidAmount;
		Liquidations[_index].bidAmount = _bid;
		Liquidations[_index].bidder = msg.sender;
		Liquidations[_index].bidTimestamp = block.timestamp;
	}

	function claimLiquidation(uint _index, address _to) external {
		require(Liquidations.length > _index);
		Liquidation memory liquidation = Liquidations[_index];
		require(msg.sender == liquidation.bidder);
		require(block.timestamp - liquidation.bidTimestamp >= 10 minutes);

		delete Liquidations[_index];

		IERC20(liquidation.assetSupplied).transfer(_to, liquidation.amountSupplied);
	}

	/*
		@Description: when there is less than 1 day until maturity or vaults are under the lower collateralisation limit vaults may be liquidated instantly without going through the auction process
	*/
	function instantLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _maxBid, uint _minOut, address _to) external {
		require(vaults[_owner].length > _index);
		Vault memory vault = vaults[_owner][_index];
		require(vault.assetBorrowed == _assetBorrowed);
		require(vault.assetSupplied == _assetSupplied);
		require(vault.amountBorrowed <= _maxBid);
		require(vault.amountSupplied >= _minOut);
		require(ICapitalHandler(_assetBorrowed).maturity() < block.timestamp + (1 days) || 
			!vaultHealthContract.satisfiesLowerLimit(vault.assetSupplied, vault.assetBorrowed, vault.amountSupplied, vault.amountBorrowed));

		//burn borrowed ZCB
		ICapitalHandler(_assetBorrowed).burnZCBFrom(_to, vault.amountBorrowed);
		lowerShortInterest(_assetBorrowed, vault.amountBorrowed);
		IERC20(_assetSupplied).transfer(_to, vault.amountSupplied);

		delete vaults[_owner][_index];
	}

	function partialLiquidationSpecificIn(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _in, uint _minOut, address _to) external {
		require(vaults[_owner].length > _index);
		Vault memory vault = vaults[_owner][_index];
		require(vault.assetBorrowed == _assetBorrowed);
		require(vault.assetSupplied == _assetSupplied);
		require(_in <= vault.amountBorrowed);
		uint amtOut = _in*vault.amountSupplied/vault.amountBorrowed;
		require(vault.amountSupplied >= amtOut);
		require(amtOut >= _minOut);
		require(ICapitalHandler(_assetBorrowed).maturity() < block.timestamp + (1 days) || 
			!vaultHealthContract.satisfiesLowerLimit(vault.assetSupplied, vault.assetBorrowed, vault.amountSupplied, vault.amountBorrowed));

		//burn borrowed ZCB

		ICapitalHandler(_assetBorrowed).burnZCBFrom(_to, _in);
		lowerShortInterest(_assetBorrowed, _in);
		IERC20(_assetSupplied).transfer(_to, amtOut);

		vaults[_owner][_index].amountBorrowed -= _in;
		vaults[_owner][_index].amountSupplied -= amtOut;
	}

	function partialLiquidationSpecificOut(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _out, uint _maxIn, address _to) external {
		require(vaults[_owner].length > _index);
		Vault memory vault = vaults[_owner][_index];
		require(vault.assetBorrowed == _assetBorrowed);
		require(vault.assetSupplied == _assetSupplied);
		require(vault.amountSupplied >= _out);
		uint amtIn = _out*vault.amountBorrowed;
		amtIn = amtIn/vault.amountSupplied + (amtIn%vault.amountSupplied == 0 ? 0 : 1);
		require(amtIn <= _maxIn);
		require(ICapitalHandler(_assetBorrowed).maturity() < block.timestamp + (1 days) || 
			!vaultHealthContract.satisfiesLowerLimit(vault.assetSupplied, vault.assetBorrowed, vault.amountSupplied, vault.amountBorrowed));

		//burn borrowed ZCB
		IERC20(_assetBorrowed).transferFrom(msg.sender, address(0), amtIn);
		IERC20(_assetSupplied).transfer(_to, _out);

		vaults[_owner][_index].amountBorrowed -= amtIn;
		vaults[_owner][_index].amountSupplied -= _out;
	}
	//--------------------------------------------management---------------------------------------------

/*
	function setOrganizerAddress(address _organizerAddress) public onlyOwner {
		require(organizerAddress == address(0));
		organizerAddress = _organizerAddress;
	}
*/

	function claimRevenue(address _asset, uint _amount) public onlyOwner {
		require(revenue[_asset] >= _amount);
		IERC20(_asset).transfer(msg.sender, _amount);
		revenue[_asset] -= _amount;
	}
}

