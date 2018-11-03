pragma solidity 0.4.24;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

library ExtendedMath {


    //return the smaller of the two inputs (a or b)
    function limitLessThan(uint a, uint b) internal pure returns (uint c) {

        if(a > b) return b;

        return a;

    }
}


contract _0xBitcoinCloneToken is ERC20 {

    using SafeMath for uint256;
    using ExtendedMath for uint256;

    string public symbol;

    string public  name;

    uint8 public decimals;

    uint256 public maxMining;

    uint public latestDifficultyPeriodStarted;

    uint public epochCount;//number of 'blocks' mined

    uint public _BLOCKS_PER_READJUSTMENT = 1024;

    //a little number
    uint public  _MINIMUM_TARGET = 2**16;


      //a big number is easier ; just find a solution that is smaller
    //uint public  _MAXIMUM_TARGET = 2**224;  bitcoin uses 224
    uint public  _MAXIMUM_TARGET = 2**234;


    uint public miningTarget;

    //generate a new one when a new reward is minted
    bytes32 public challengeNumber;

    uint public rewardEra;
    uint public maxSupplyForEra;

    address public lastRewardTo;
    uint public lastRewardAmount;
    uint public lastRewardEthBlockNumber;

    mapping(bytes32 => bytes32) solutionForChallenge;

    uint public tokensMinted;

    event Mint(
        address indexed from, 
        uint reward_amount, 
        uint epochCount, 
        bytes32 newChallengeNumber
    );

    // ------------------------------------------------------------------------

    // Constructor

    // ------------------------------------------------------------------------

    constructor () public{

        symbol = "0xBTC";

        name = "0xBitcoin Token";

        decimals = 8;

        maxMining = 21000000 * (10 ** uint(decimals));

        tokensMinted = 0;

        rewardEra = 0;
        maxSupplyForEra = maxMining.div(2);

        miningTarget = _MAXIMUM_TARGET;

        latestDifficultyPeriodStarted = block.number;
        
        //1 million pre-mined coins
        _mint(msg.sender, 1000000 * (10 ** uint256(decimals)));

        _startNewMiningEpoch();
    }




    function mint(
        uint256 nonce, 
        bytes32 challenge_digest
    ) 
        public 
        returns (bool success) 
    {


        //the PoW must contain work that includes a recent ethereum block hash (challenge number) and the msg.sender's address to prevent MITM attacks
        bytes32 digest = keccak256(
            abi.encodePacked(
                challengeNumber, 
                msg.sender, 
                nonce 
            )
        );

        //the challenge digest must match the expected
        require(digest == challenge_digest);

        //the digest must be smaller than the target
        require(uint256(digest) <= miningTarget);


        //only allow one reward for each challenge
        bytes32 solution = solutionForChallenge[challengeNumber];
        solutionForChallenge[challengeNumber] = digest;

        //prevent the same answer from awarding twice
        require(solution == 0x0);  


        uint reward_amount = getMiningReward();
        _mint(msg.sender, reward_amount);
        tokensMinted = tokensMinted.add(reward_amount);


        //Cannot mint more tokens than there are
        assert(tokensMinted <= maxSupplyForEra);

        //set readonly diagnostics data
        lastRewardTo = msg.sender;
        lastRewardAmount = reward_amount;
        lastRewardEthBlockNumber = block.number;


        _startNewMiningEpoch();

        emit Mint(
            msg.sender, 
            reward_amount, 
            epochCount, 
            challengeNumber 
        );

        return true;

    }


    //a new 'block' to be mined
    function _startNewMiningEpoch() internal {

      //if max supply for the era will be exceeded next reward round then enter the new era before that happens

      //40 is the final reward era, almost all tokens minted
      //once the final era is reached, more tokens will not be given out because the assert function
        if( 
            tokensMinted.add(getMiningReward()) > maxSupplyForEra && rewardEra < 39
        )
        {
            rewardEra = rewardEra + 1;
        }

        //set the next minted supply at which the era will change
        // Max mining is 2100000000000000  because of 8 decimal places
        maxSupplyForEra = maxMining - maxMining.div( 2**(rewardEra + 1));

        epochCount = epochCount.add(1);

        //every so often, readjust difficulty. Dont readjust when deploying
        if(epochCount % _BLOCKS_PER_READJUSTMENT == 0)
        {
            _reAdjustDifficulty();
        }


        //make the latest ethereum block hash a part of the next challenge for PoW to prevent pre-mining future blocks
        //do this last since this is a protection mechanism in the mint() function
        challengeNumber = blockhash(block.number - 1);
    }




    //https://en.bitcoin.it/wiki/Difficulty#What_is_the_formula_for_difficulty.3F
    //as of 2017 the bitcoin difficulty was up to 17 zeroes, it was only 8 in the early days

    //readjust the target by 5 percent
    function _reAdjustDifficulty() internal {


        uint ethBlocksSinceLastDifficultyPeriod = (
            block.number - latestDifficultyPeriodStarted
        );        //assume 360 ethereum blocks per hour

        //we want miners to spend 10 minutes to mine each 'block', about 60 ethereum blocks = one 0xbitcoin epoch
        uint epochsMined = _BLOCKS_PER_READJUSTMENT; //256

        //should be 60 times slower than ethereum
        uint targetEthBlocksPerDiffPeriod = epochsMined * 60; 

        //if there were less eth blocks passed in time than expected
        if( ethBlocksSinceLastDifficultyPeriod < targetEthBlocksPerDiffPeriod )
        {
            uint256 excess_block_pct = (
              targetEthBlocksPerDiffPeriod.mul(100)
            ).div( ethBlocksSinceLastDifficultyPeriod );

            uint excess_block_pct_extra = excess_block_pct.sub(100).limitLessThan(1000);
            
            // If there were 5% more blocks mined than expected then this is 5.  If there were 100% more blocks mined than expected then this is 100.

            //make it harder
            miningTarget = miningTarget.sub(miningTarget.div(2000).mul(excess_block_pct_extra));   //by up to 50 %
        }else{
            uint shortage_block_pct = (ethBlocksSinceLastDifficultyPeriod.mul(100)).div( targetEthBlocksPerDiffPeriod );

            uint shortage_block_pct_extra = shortage_block_pct.sub(100).limitLessThan(1000); //always between 0 and 1000

            //make it easier
            miningTarget = miningTarget.add(miningTarget.div(2000).mul(shortage_block_pct_extra));   //by up to 50 %
        }



        latestDifficultyPeriodStarted = block.number;

        if(miningTarget < _MINIMUM_TARGET) //very difficult
        {
            miningTarget = _MINIMUM_TARGET;
        }

        if(miningTarget > _MAXIMUM_TARGET) //very easy
        {
            miningTarget = _MAXIMUM_TARGET;
        }
    }


    //this is a recent ethereum block hash, used to prevent pre-mining future blocks
    function getChallengeNumber() public view returns (bytes32) {
        return challengeNumber;
    }

    //the number of zeroes the digest of the PoW solution requires.  Auto adjusts
    function getMiningDifficulty() public view returns (uint) {
        return _MAXIMUM_TARGET.div(miningTarget);
    }

    function getMiningTarget() public view returns (uint) {
        return miningTarget;
    }



    //21m coins total
    //reward begins at 50 and is cut in half every reward era (as tokens are mined)
    function getMiningReward() public view returns (uint) {
        //once we get half way thru the coins, only get 25 per block

         //every reward era, the reward amount halves.

        return (50 * 10**uint(decimals) ).div( 2**rewardEra ) ;

    }

    //help debug mining software
    function getMintDigest(
        uint256 nonce, 
        bytes32 challenge_number
    ) 
        public 
        view 
        returns (bytes32 digesttest) 
    {

        bytes32 digest = keccak256(
            abi.encodePacked(
                challenge_number,
                msg.sender,
                nonce
            )
        );

        return digest;

    }

        //help debug mining software
    function checkMintSolution(
        uint256 nonce, 
        bytes32 challenge_digest, 
        bytes32 challenge_number, 
        uint testTarget
    ) 
        public 
        view 
        returns (bool success) 
    {

        bytes32 digest = keccak256(
            abi.encodePacked(
                challenge_number,
                msg.sender,
                nonce
            )
        );

        require(uint256(digest) <= testTarget);

        return (digest == challenge_digest);

    }

}
