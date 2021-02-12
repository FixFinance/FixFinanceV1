pragma solidity >=0.6.0;

import "../interfaces/IChainlinkAggregator.sol";

contract dummyAggregator is IChainlinkAggregator {

	struct round {
		int answer;
		uint timestamp;
	}

	uint8 public override decimals;
	round[] rounds;

	string public override description;

	constructor(uint8 _decimals, string memory _description) public {
		decimals = _decimals;
		description = _description;
		rounds.push(round(0, block.timestamp));
	}

	function addRound(int _answer) external {
		rounds.push(round(_answer, block.timestamp));
	}

	function getTimestamp(uint _roundId) external view override returns(uint) {
		return rounds[_roundId].timestamp;
	}

	function getAnswer(uint _roundId) external view override returns(int) {
		return rounds[_roundId].answer;
	}

	function latestRound() external view override returns(uint) {
		return rounds.length-1;
	}

	function latestAnswer() external view override returns(int) {
		return rounds[rounds.length-1].answer;
	}


}
