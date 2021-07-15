// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;

import "./NGBwrapper.sol";

contract NGBwrapperDeployer {

	constructor(address _infoOracleAddress) public {
		infoOracleAddress = _infoOracleAddress;
	}

	address infoOracleAddress;
	/*
		100 sbps (super basis points) is 1 bip (basis point)
		1.0 == 100% == 10_000 bips == 1_000_000 sbps

		DEFAULT_SBPS_RETAINED represents the default value (in super basis points) of
		1.0 - annualWrapperFee
		if SBPSRetained == 999_000 == 1_000_000 - 1000, the annual wrapper fee is 1000sbps or 0.1%
	*/
	uint32 private constant DEFAULT_SBPS_RETAINED = 999_000;

	function deploy(address _underlyingAssetAddress, address _owner) external returns(address ret) {
		ret = address(new NGBwrapper(_underlyingAssetAddress, infoOracleAddress, DEFAULT_SBPS_RETAINED));
		Ownable(ret).transferOwnership(_owner);
	}

}