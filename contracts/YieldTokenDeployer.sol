pragma solidity >=0.6.5 <0.7.0;
import "./interfaces/IERC20.sol";
import "./libraries/SafeMath.sol";
import "./YieldToken.sol";

contract YieldTokenDeployer {
	address public addr;

	function deploy(address _aToken) public {
		addr = address(new YieldToken(_aToken, msg.sender));
	}
}