pragma experimental ABIEncoderV2;
pragma solidity >=0.6.5 <0.7.0;

import "./capitalHandler.sol";
import "./interfaces/IVaultHealth.sol";
import "./interfaces/IERC20.sol";
import "./Ownable.sol";

contract BondMinter is Ownable {

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

	//asset => amount
	mapping(address => uint) public revenue;

	//asset => capitalHandler
	mapping(address => address) public assetToCapitalHandler;

	//user => vault index => vault
	mapping(address => Vault[]) public vaults;

	Liquidation[] public Liquidations;

	IVaultHealth public vaultHealthContract;

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

	//------------------------------------vault management-----------------------------------

	function openVault(address _assetSupplied, address _assetBorrowed, uint _amountSupplied, uint _amountBorrowed) external {
		address chBorrowAddress = assetToCapitalHandler[_assetBorrowed];
		/*
			users can only borrow ZCBs
		*/
		require(chBorrowAddress != address(0) && chBorrowAddress == _assetBorrowed);
		/*
			when chSupplyAddress == _assetSupplied
			the supplied asset is a zcb
		*/
		address chSupplyAddress = assetToCapitalHandler[_assetSupplied];
		require(chSupplyAddress != address(0));
		require(vaultHealthContract.upperLimitSuppliedAsset(_assetSupplied, _assetBorrowed, _amountSupplied, _amountBorrowed));

		IERC20(_assetSupplied).transferFrom(msg.sender, address(this), _amountSupplied);
		capitalHandler(chBorrowAddress).mintZCBTo(msg.sender, _amountBorrowed);

		vaults[msg.sender].push(Vault(_assetSupplied, _assetBorrowed, _amountSupplied, _amountBorrowed));

		emit OpenVault(_assetSupplied, _assetBorrowed, _amountSupplied, _amountBorrowed);
	}

	function closeVault(uint _index, address _to) external {
		uint len = vaults[msg.sender].length;
		require(len > _index);
		Vault memory vault = vaults[msg.sender][_index];

		//burn borrowed ZCB
		if (vault.amountBorrowed > 0)
			IERC20(vault.assetBorrowed).transferFrom(msg.sender, address(0), vault.amountBorrowed);
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
		require(vaultHealthContract.upperLimitSuppliedAsset(
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

		require(vaultHealthContract.upperLimitSuppliedAsset(
			vault.assetSupplied,
			vault.assetBorrowed,
			vault.amountSupplied,
			vault.amountBorrowed + _amount
		));

		vaults[msg.sender][_index].amountBorrowed += _amount;

		capitalHandler(vault.assetBorrowed).mintZCBTo(_to, _amount);

		emit Borrow(msg.sender, _index, _amount);
	}

	function repay(address _owner, uint _index, uint _amount) external {
		require(vaults[_owner].length > _index);
		require(vaults[_owner][_index].amountBorrowed >= _amount);
		//burn borrowed ZCB
		IERC20(vaults[_owner][_index].assetBorrowed).transferFrom(msg.sender, address(0), _amount);
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
		if (vaultHealthContract.lowerLimitSuppliedAsset(vault.assetSupplied, vault.assetBorrowed, vault.amountSupplied, vault.amountBorrowed)) {
			uint maturity = capitalHandler(assetToCapitalHandler[vault.assetBorrowed]).maturity();
			require(maturity < block.timestamp + (7 days));
		}
		//burn borrowed ZCB
		IERC20(vault.assetBorrowed).transferFrom(msg.sender, address(0), vault.amountBorrowed);
		//any surplus in the bid may be added as revenue
		if (_bid > vault.amountBorrowed){
			IERC20(vault.assetBorrowed).transferFrom(msg.sender, address(this), _bid - vault.amountBorrowed);
			revenue[vault.assetBorrowed] += vault.amountBorrowed - _bid;
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
		require(block.timestamp - liquidation.bidTimestamp < 30 minutes);
		IERC20(liquidation.assetBorrowed).transferFrom(msg.sender, address(this), _bid);
		IERC20(liquidation.assetBorrowed).transfer(liquidation.bidder, liquidation.bidAmount);
		revenue[liquidation.assetBorrowed] += _bid - liquidation.bidAmount;
		Liquidations[_index].bidAmount = _bid;
		Liquidations[_index].bidder = msg.sender;
		Liquidations[_index].bidTimestamp = block.timestamp;
	}

	function claimLiquidation(uint _index) external {
		require(Liquidations.length > _index);
		Liquidation memory liquidation = Liquidations[_index];
		require(msg.sender == liquidation.bidder);
		require(liquidation.bidTimestamp - block.timestamp >= 30 minutes);

		delete Liquidations[_index];

		IERC20(liquidation.assetSupplied).transfer(msg.sender, liquidation.amountSupplied);
	}

	/*
		@Description: when there is less than 1 day until maturity vaults may be liquidated instantly without going through the auction process
	*/
	function instantLiquidation(address _owner, uint _index, address _assetBorrowed, address _assetSupplied, uint _maxBid, uint _minOut, address _to) external {
		require(vaults[_owner].length > _index);
		Vault memory vault = vaults[_owner][_index];
		require(vault.assetBorrowed == _assetBorrowed);
		require(vault.assetSupplied == _assetSupplied);
		require(vault.amountBorrowed <= _maxBid);
		require(vault.amountSupplied >= _minOut);

		require(capitalHandler(assetToCapitalHandler[_assetBorrowed]).maturity() < block.timestamp + (1 days));

		//burn borrowed ZCB
		IERC20(_assetBorrowed).transferFrom(msg.sender, address(0), vault.amountBorrowed);
		IERC20(_assetSupplied).transfer(_to, vault.amountSupplied);
		delete vaults[_owner][_index];
	}

	//--------------------------------------------management---------------------------------------------

	function setCapitalHandler(address _capitalHandlerAddress) public onlyOwner {
		assetToCapitalHandler[address(capitalHandler(_capitalHandlerAddress).aw())] = _capitalHandlerAddress;
		assetToCapitalHandler[_capitalHandlerAddress] = _capitalHandlerAddress;
	}

	function claimRevenue(address _asset, uint _amount) public onlyOwner {
		require(revenue[_asset] >= _amount);
		IERC20(_asset).transfer(msg.sender, _amount);
	}
}

