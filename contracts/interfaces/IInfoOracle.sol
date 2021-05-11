// SPDX-License-Identifier: MIT
pragma solidity >=0.6.8 <0.8.0;

interface IInfoOracle {
	function bipsToTreasury() external view returns(uint16);
	function sendTo() external view returns(address);
	function WrapperToYTSlippageConst(address _wrapperAddr) external view returns(uint);
	function WrapperToZCBFeeConst(address _wrapperAddr) external view returns(uint);
	function WrapperToYTFeeConst(address _wrapperAddr) external view returns(uint);
	function YTammSlippageConstants(address _FCPaddress) external view returns(uint);
	function ZCBammFeeConstants(address _FCPaddress) external view returns(uint);
	function YTammFeeConstants(address _FCPaddress) external view returns(uint);
	function treasuryFee(uint larger, uint smaller) external view returns (uint toTreasury, address _sendTo);
	function getZCBammFeeConstant(address _fixCapitalPoolAddress) external view returns (uint FeeConstant);
	function getYTammFeeConstant(address _fixCapitalPoolAddress) external view returns (uint FeeConstant);
	function getSlippageConstant(address _fixCapitalPoolAddress) external view returns (uint SlippageConstant);

	//---------management--------------

	function wrapperSetFeeConstants(address _wrapper, uint _ZCBammFeeConstant, uint _YTammFeeConstant) external;
	function wrapperSetSlippageConst(address _wrapper, uint _SlippageConstant) external;
	function setFeeConstants(address _fixCapitalPoolAddress, uint _ZCBammFeeConstant, uint _YTammFeeConstant) external;
	function setSlippageConstant(address _fixCapitalPoolAddress, uint256 _SlippageConstant) external;

	//---------InfoOracle-Admin--------

	function setToTreasuryFee(uint16 _bipsToTreasury) external;
	function setSendTo(address _sendTo) external;

}