pragma solidity >=0.6.5 <0.7.0;
import '../interfaces/IVaultHealth.sol';
import '../interfaces/IAaveWrapper.sol';

contract DummyVaultHealth is IVaultHealth {

	/*
		In this contract we assume that all assets being supplied are wrapped A Tokens
		
		all assets being borrowed are zcbs
	*/

	//asset supplied => asset borrowed => ratio
	mapping(address => mapping(address => uint)) public upperRatio;
	mapping(address => mapping(address => uint)) public middleRatio;
	mapping(address => mapping(address => uint)) public lowerRatio;

	//collateral above return value of this function may be withdrawn from vault
	function upperLimitSuppliedAsset(
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed
		) external view override returns (bool) {

		return upperRatio[_assetSupplied][_assetBorrowed] * _amountBorrowed / 1e18 < IAaveWrapper(_assetSupplied).WrappedTokenToAToken_RoundDown(_amountSupplied);
	}
	//collateral above return value of this function may be withdrawn from vault
	function middleLimitSuppliedAsset(
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed
		) external view override returns (bool) {

		return middleRatio[_assetSupplied][_assetBorrowed] * _amountBorrowed / 1e18 < IAaveWrapper(_assetSupplied).WrappedTokenToAToken_RoundDown(_amountSupplied);
	}
	//collateral must be greater than or equal to the return value to avoid liquidation
	function lowerLimitSuppliedAsset(
		address _assetSupplied,
		address _assetBorrowed,
		uint _amountSupplied,
		uint _amountBorrowed
		) external view override returns (bool) {

		return lowerRatio[_assetSupplied][_assetBorrowed] * _amountBorrowed / 1e18 < IAaveWrapper(_assetSupplied).WrappedTokenToAToken_RoundDown(_amountSupplied);
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
}