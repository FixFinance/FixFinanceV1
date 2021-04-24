pragma solidity >=0.6.5 <0.7.0;
import '../interfaces/IVaultHealth.sol';
import '../interfaces/IWrapper.sol';

contract DummyVaultHealth is IVaultHealth {

	/*
		In this contract we assume that all assets being supplied are wrapped A Tokens
		
		all assets being borrowed are zcbs
	*/

	//underlyingAsset => maximum amount of short interest *all duations combined*
	mapping(address => uint) public override maximumShortInterest;

	//asset supplied => asset borrowed => ratio
	mapping(address => mapping(address => uint)) public upperRatio;
	mapping(address => mapping(address => uint)) public middleRatio;
	mapping(address => mapping(address => uint)) public lowerRatio;

	//collateral above return value of this function may be withdrawn from vault
	function satisfiesUpperLimit(
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed
		) external view override returns (bool) {

		return upperRatio[_assetSupplied][_assetBorrowed] * _amountBorrowed / 1e18 < _amountSupplied;
	}
	//collateral must be greater than or equal to the return value to avoid liquidation
	function satisfiesLowerLimit(
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed
		) external view override returns (bool) {

		return lowerRatio[_assetSupplied][_assetBorrowed] * _amountBorrowed / 1e18 < _amountSupplied;
	}

	function amountSuppliedAtUpperLimit(address _assetSupplied, address _assetBorrowed, uint _amountBorrowed) external view override returns (uint) {
		return upperRatio[_assetSupplied][_assetBorrowed] * _amountBorrowed / 1e18;
	}
	function amountSuppliedAtLowerLimit(address _assetSupplied, address _assetBorrowed, uint _amountBorrowed) external view override returns (uint) {
		return lowerRatio[_assetSupplied][_assetBorrowed] * _amountBorrowed / 1e18;
	}

	function amountBorrowedAtUpperLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied) external view override returns (uint) {
		return _amountSupplied * 1e18 / upperRatio[_assetSupplied][_assetBorrowed];
	}
	function amountBorrowedAtLowerLimit(address _assetSupplied, address _assetBorrowed, uint _amountSupplied) external view override returns (uint) {
		return _amountSupplied * 1e18 / lowerRatio[_assetSupplied][_assetBorrowed];
	}

	function YTvaultAmountBorrowedAtUpperLimit(address _FCPsupplied, address _FCPborrowed, uint _amountYield, int _amountBond) external view override returns (uint) {
		if (
			_FCPsupplied == address(0) ||
			_FCPborrowed == address(0) ||
			_amountYield == 0 ||
			_amountBond == 0
			)
			return 0;
		return 1;
	}
	function YTvaultAmountBorrowedAtLowerLimit(address _FCPsupplied, address _FCPborrowed, uint _amountYield, int _amountBond) external view override returns (uint) {
		if (
			_FCPsupplied == address(0) ||
			_FCPborrowed == address(0) ||
			_amountYield == 0 ||
			_amountBond == 0
			)
			return 0;
		return 1;
	}

	function YTvaultSatisfiesUpperLimit(address _FCPsupplied, address _FCPborrowed, uint _amountYield, int _amountBond, uint _amountBorrowed) external view override returns (bool) {
		if (
			_FCPsupplied	== address(0) ||
			_FCPborrowed == address(0) ||
			_amountYield == 0 ||
			_amountBond == 0 ||
			_amountBorrowed == 0
			)
			return false || toReturn;
		return true && toReturn;
	}
	function YTvaultSatisfiesLowerLimit(address _FCPsupplied, address _FCPborrowed, uint _amountYield, int _amountBond, uint _amountBorrowed) external view override returns (bool) {
		if (
			_FCPsupplied	== address(0) ||
			_FCPborrowed == address(0) ||
			_amountYield == 0 ||
			_amountBond == 0 ||
			_amountBorrowed == 0
			)
			return false || toReturn;
		return true && toReturn;
	}



	bool toReturn;
	function setToReturn(bool _toReturn) external {
		toReturn = _toReturn;
	}
	/*
		This is a dummy contract and we don't plan on calling the function below ever so
		we just return false/true without really looking into if it is doing the right thing
		this way this dummy contract implements the IVaultHealth interface
	*/
	function vaultWithstandsChange(
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed,
		uint _pctPriceChange,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
		) external view override returns (bool) {
		/*
			silence warnings about not using parameters
		*/
		if (
			_assetSupplied == address(0) ||
			_assetBorrowed == address(0) ||
			_amountSupplied == 0 ||
			_amountBorrowed == 0 ||
			_pctPriceChange == 0 ||
			_suppliedRateChange == 0 ||
			_borrowRateChange == 0
			)
			return false || toReturn;
		return true && toReturn;
	}

	function YTvaultWithstandsChange(
		address _FCPsupplied,
		address _FCPborrowed,
		uint _amountYield,
		int _amountBond,
		uint _amountBorrowed,
		uint _pctPriceChange,
		int128 _suppliedRateChange,
		int128 _borrowRateChange
	) external view override returns (bool) {
		/*
			silence warnings about not using parameters
		*/
		if (
			_FCPsupplied == address(0) ||
			_FCPborrowed == address(0) ||
			_amountYield == 0 ||
			_amountBond == 0 ||
			_amountBorrowed == 0 ||
			_pctPriceChange == 0 ||
			_suppliedRateChange == 0 ||
			_borrowRateChange == 0
			)
			return false || toReturn;
		return true && toReturn;		
	}


	function setUpper(
		address _assetSupplied,
		address _assetBorrowed,
		uint _ratio
		) public {

		upperRatio[_assetSupplied][_assetBorrowed] = _ratio;

	}

	function setMiddle(
		address _assetSupplied,
		address _assetBorrowed,
		uint _ratio
		) public {

		middleRatio[_assetSupplied][_assetBorrowed] = _ratio;

	}

	function setLower(
		address _assetSupplied,
		address _assetBorrowed,
		uint _ratio
		) public {

		lowerRatio[_assetSupplied][_assetBorrowed] = _ratio;

	}

	function setMaximumShortInterest(address _underlyingAssetAddress, uint _maximumShortInterest) external {
		maximumShortInterest[_underlyingAssetAddress] = _maximumShortInterest;
	}
}