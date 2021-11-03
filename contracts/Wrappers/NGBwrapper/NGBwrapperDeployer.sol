// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "../../interfaces/IWrapperDeployer.sol";
import "./NGBwrapper.sol";

contract NGBwrapperDeployer is IWrapperDeployer {

	constructor(address _infoOracleAddress, address _delegate1Address, address _delegate2Address, address _delegate3Address) public {
		InfoOracleAddress = _infoOracleAddress;
		delegate1Address = _delegate1Address;
		delegate2Address = _delegate2Address;
		delegate3Address = _delegate3Address;
	}

	address public override InfoOracleAddress;
	address delegate1Address;
	address delegate2Address;
	address delegate3Address;
	/*
		100 sbps (super basis points) is 1 bip (basis point)
		1.0 == 100% == 10_000 bips == 1_000_000 sbps

		DEFAULT_SBPS_RETAINED represents the default value (in super basis points) of
		1.0 - annualWrapperFee
		if SBPSRetained == 999_000 == 1_000_000 - 1000, the annual wrapper fee is 1000sbps or 0.1%
	*/
	uint32 private constant DEFAULT_SBPS_RETAINED = 999_000;

	function deploy(address _underlyingAssetAddress, address _owner) external override returns(address wrapperAddress) {
		wrapperAddress = address(new NGBwrapper(
			_underlyingAssetAddress,
			InfoOracleAddress,
			delegate1Address,
			delegate2Address,
			delegate3Address,
			DEFAULT_SBPS_RETAINED
		));
		Ownable(wrapperAddress).transferOwnership(_owner);
	}

}