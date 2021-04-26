pragma solidity >=0.6.0;

contract nonReentrant {
	uint8 entered;

	modifier noReentry {
		require(entered == 0);
		entered = 1;
		_;
		entered = 0;
	}
}