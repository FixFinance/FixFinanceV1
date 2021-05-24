// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.7.0;
import "./interfaces/IERC20.sol";
import "./libraries/SafeMath.sol";
import "./YieldToken.sol";
import "./ZeroCouponBond.sol";

contract ZCB_YT_Deployer {

	/*
		@Description: deploy new YieldToken contract

		@param address _wrapperAddress: the address to pass as the 1st parameter in deployment
			of the new YieldToken contract
		@param uint _maturity: the maturity date of the new YT we are deploying a contract for

		@return address: address of the new YieldToken contract
	*/
	function deployYT(address _wrapperAddress, uint _maturity) public returns (address) {
		return address(new YieldToken(_wrapperAddress, msg.sender, _maturity));
	}

	/*
		@Description: deploy new ZeroCouponBond contract

		@param address _wrapperAddress: the address to pass as the 1st parameter in deployment
			of the new ZeroCouponBond contract
		@param uint _maturity: the maturity date of the new ZCB we are deploying a contract for

		@return address: address of the new ZeroCouponBond contract
	*/
	function deployZCB(address _wrapperAddress, uint _maturity) public returns (address) {
		return address(new ZeroCouponBond(_wrapperAddress, msg.sender, _maturity));
	}
}