pragma solidity >=0.6.5 <0.7.0;
import "./interfaces/IERC20.sol";
import "./libraries/SafeMath.sol";
import "./YieldToken.sol";

contract YieldTokenDeployer {

	/*
		@Description: deploy new YieldToken contract

		@param address _wrapperAddress: the address to pass as the 1st parameter in deployment
			of the new YieldToken contract

		@return address: address of the new YieldToken contract
	*/
	function deploy(address _wrapperAddress) public returns (address) {
		return address(new YieldToken(_wrapperAddress, msg.sender));
	}

}