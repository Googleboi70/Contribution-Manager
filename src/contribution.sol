//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {receiveContribution} from "./receiveContribution.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {Script, console} from "lib/forge-std/src/Script.sol";

contract Contribution is VRFConsumerBaseV2Plus, AutomationCompatibleInterface {
  //  uint private s_lastTimeStamp; // stored in first slot
   // uint private immutable i_interval; // stored in second slot
    contributionGroup[] public s_contributionGroups; //Array length stored in third slot, but elements stored in slot starting from keccak256(third_slot_number)
    uint public immutable i_entranceFee;  //not stored in storage
    uint public requestId; //stord in fourth slot
    uint[] private s_UpkeepNeededGroupIds; //array length stored in fifth slot but elements stored in slot starting from keccak256(fifth_slot_number) 
    bytes32 private immutable i_keyHash; //not stored in storage, stored directly as part of contract's bytecode
    uint32 private callbackGasLimit; //stored in sixth slot
    uint16 private constant REQUEST_CONFIRMATIONS = 3; //not stored in storage, stored directly as part of contract's bytecode 
    uint32 private constant NUM_wORDS = 1; //Not stored in storage, stored directly as part of contract's bytecode
    uint256 public immutable i_subscriptionId;//Not stored in storage
    bool private enableNativePayment = false; //stored in storage in seventh slot, padded with  zeros  
    address payable public s_contributionAddress; //stored in seventh slot with the boolen coz they're both not upto 32 bytes
    receiveContribution private receiveContributionContract; //stored in eigth slot
    address public immutable i_owner; 
    uint private count;


    error Contribution__InsufficientFee();
    error Contribution__Contribution_Not_Open();
    error Contribution__senderNotInGroup();
    error Contribution__AddressZeroNotAllowed();
    error Contribution__ZeroValueNotAllowed();
    error Contribution__OutOfRound();
    error Contribution__UpKeep_Not_Yet_Needed();
    error Contribution__All_Contributors_Have_Been_Picked();
    error Contribution__Caller_Not_Owner();
    error Contribution__Group_Not_Active();
    error Contribution__Cannot_Create_More_Than_One_Group();

    mapping(uint => contributionGroup) public idToGroup;
    mapping(uint => uint) idToCurrentRound;
    mapping(uint => uint) idToNumberOfRounds;
    mapping(address => uint) contributorToId;
    mapping(uint => uint) vrfRequestIdToGroupId;
    mapping(address => mapping(uint => bool)) hasContributed;
    mapping(address => mapping(uint => uint)) hasContributedTime;
    mapping(uint => bool) allContributed;
    mapping(uint => bool) winnerSelected;
    mapping(uint => bool) UpkeepNeededForGroups;
    mapping(uint => address) groupToLastRoundWinner;
    mapping(uint => mapping(address => bool)) hasWon;
    mapping(address => uint) senderToCount;
    mapping(uint => bool) roundEnded;

    event groupCreated(address payable[2] _contributors, uint _amount, uint _interval, uint _numberOfContributors);
    event RequestedRoundWinner(uint requestId, uint groupId);
    event currentRoundWinnerPicked(uint groupId, address payable contributor);
    event ContributionEnded(uint groupId);
     

    enum ContributionState {
        OPEN,
        CALCULATING,
        CREATING_GROUP,
        ENDED
    }

    ContributionState Default_State = ContributionState.OPEN;
    ContributionState public s_ContributionState;

    //Group struct
    struct contributionGroup {
        address payable[2] contributors;
        uint amount;
        uint contributionStartTime;
        uint contributionStopTime;
        uint interval;
        uint numberOfContributors;
        address payable contributionAddress;
        uint groupId;
        uint numberOfContributionRounds;
        address payable[] currentRoundContributedContributors;
        address payable lastRoundWinner;
        address payable[] prevWinners;
        uint payout;
        bool isActive;
    }

    constructor( 
        uint _entranceFee,
        uint32 _callbackGasLimit,
        bytes32 keyHash,
        uint256 _subscriptionId,
        address _vrfCoordinator
    ) VRFConsumerBaseV2Plus(_vrfCoordinator) {
        i_entranceFee = _entranceFee;
        s_ContributionState = Default_State;
        i_entranceFee = _entranceFee;
        i_subscriptionId = _subscriptionId;
        i_keyHash = keyHash;
        callbackGasLimit = _callbackGasLimit;
        i_owner = msg.sender;
    }

    //gets the start and stop time of current round
    function getCurrentRoundStartTime( uint _id, uint _roundNumber) public view returns (uint ) {
        contributionGroup memory group = idToGroup[_id]; 
        if (_roundNumber == 0) return group.contributionStartTime;
        else return (group.contributionStartTime + ((group.interval) * (_roundNumber - 1)));
    }


    function getCurrentRoundStopTime (uint _id, uint _roundNumber) public view returns(uint) {
        contributionGroup memory group = idToGroup[_id]; 
        if (_roundNumber == 0) return group.contributionStartTime + group.interval;
        else return (group.contributionStartTime + (group.interval * _roundNumber));
    }

    //gets the number of curent round
    function getCurrentRoundNumber(uint id) public view returns (uint) {
        contributionGroup memory group = idToGroup[id];
        uint256 elapsed = (block.timestamp - group.contributionStartTime);
        uint currentRoundNumber = (elapsed / group.interval) + 1;
        if (currentRoundNumber > group.numberOfContributionRounds) {
            currentRoundNumber = group.numberOfContributionRounds;
        }
        return currentRoundNumber;
    }

    function generateContributionId(address payable[2] memory _contributors, uint _amount, uint _interval, uint _count) private view returns (uint) {
        return uint(keccak256(abi.encodePacked(block.timestamp, _contributors, _amount, _interval, _count)));
    }

    //Creates the contribution group
    function createContributionGroup(address payable[2] memory _contributors, uint _contributionAmount, uint _interval) external payable returns (uint) {
        
        if (senderToCount[msg.sender] > 0){
            revert Contribution__Cannot_Create_More_Than_One_Group();
        }
        
        
        if (s_ContributionState != Default_State) {
            revert Contribution__Contribution_Not_Open();
        }

        if (msg.value < i_entranceFee) {
            revert Contribution__InsufficientFee();
        }
        
        count += 555555;
        //memory variables
        uint _numberOfContributionRounds = _contributors.length;
        uint _numberOfContributors = _contributors.length;
        uint _startTime = block.timestamp;
        uint _endTime = _startTime + _interval * _numberOfContributors;
        uint _id = generateContributionId(_contributors, _contributionAmount, _interval, count);
        uint _payout = _contributionAmount * _numberOfContributors;

        //revert if any contributor is address(0)
        for (uint i = 0; i < _contributors.length; i++) {
            if (_contributors[i] == address(0)) {
                revert Contribution__AddressZeroNotAllowed();
            }
        }
        
        //populating group struct
        contributionGroup memory group = contributionGroup({
            contributors: _contributors,
            amount: _contributionAmount,
            contributionStartTime: _startTime,
            interval: _interval,
            contributionStopTime: _endTime,
            numberOfContributors: _numberOfContributors,
            contributionAddress: s_contributionAddress,
            groupId: _id,
            numberOfContributionRounds: _numberOfContributionRounds,
            currentRoundContributedContributors: new address payable[](0),
            lastRoundWinner : payable(address(0)),
            prevWinners : new address payable[](_contributors.length),
            payout : _payout,
            isActive : true
        });

        emit groupCreated(
            _contributors,
            _contributionAmount,
            _interval,
            _numberOfContributors
        );

        //update mappings
        s_contributionGroups.push(group);
        idToGroup[group.groupId] = group;
        idToNumberOfRounds[group.groupId] = _numberOfContributionRounds;
        idToCurrentRound[group.groupId] = getCurrentRoundNumber(group.groupId);
        senderToCount[msg.sender] += 1;

        for (uint i = 0; i < _contributors.length; i++) {
            contributorToId[_contributors[i]] = group.groupId;
        }
        return (group.groupId);
    }

   //To know if any contributor in any group has contributed for the current round
    function hasContributedForCurrentRound(address contributor,uint id) external view returns (bool) {
        uint currentRound = getCurrentRoundNumber(id);
        if (currentRound == 0) return false;
        uint rStart = getCurrentRoundStartTime(id, currentRound);
        uint rStop = getCurrentRoundStopTime(id, currentRound); 
        if (hasContributed[contributor][id] &&(hasContributedTime[contributor][id] >= rStart && hasContributedTime[contributor][id] < rStop)) {
            return true;
        } else {
            return false;
        }
    }
    
    //To know if  all contributors in any group havecontributed for the current round
    function AllContributedForCurrentRound(uint id) public view returns (bool) {
        contributionGroup memory group = idToGroup[id];
        if (
            group.contributors.length ==
            group.currentRoundContributedContributors.length
        ) {
            return true;
        } else {
            return false;
        }
    }

    function contribute(uint id) external payable {
        //check if msg.sender has a group
        //check if id matches msg.sender's group
        //check if group is Active
        //check if msg.sender is address(0)
        //check if msg.value == group.amount
        //check if current timestamp is within range for the group's current round
        //send msg.value to receiveContribution contract
        //update mappings
        contributionGroup storage group = idToGroup[id];
        address payable[2] storage _contributors = group.contributors;
        bool isMember = false;
        uint amount = msg.value;
        for (uint i = 0; i < _contributors.length; i++) {
            if (_contributors[i] == msg.sender) {
                isMember = true;
                break;
            }
        }
        if (!isMember) {
            revert Contribution__senderNotInGroup();
        }
        if (!group.isActive){
            revert Contribution__Group_Not_Active();
        }
        if (msg.sender == address(0)) {
            revert Contribution__AddressZeroNotAllowed();
        }

        if (msg.value == 0 && msg.value < group.amount) {
            revert Contribution__ZeroValueNotAllowed();
        }
        uint currentRoundNumber = getCurrentRoundNumber(id);       
        uint rStart = getCurrentRoundStartTime(id, currentRoundNumber);
        uint rStop = getCurrentRoundStopTime(id, currentRoundNumber); 

        if (block.timestamp >= rStart && block.timestamp < rStop) {
            receiveContributionContract = receiveContribution(group.contributionAddress);
            (bool success, ) = group.contributionAddress.call{value: amount}("");
            receiveContributionContract.receiveContributionData(amount, id, msg.sender);

            require(success, "Contribution failed");
            //update mappings
            hasContributed[msg.sender][id] = true;
            hasContributedTime[msg.sender][id] = block.timestamp;

            group.currentRoundContributedContributors.push(payable(msg.sender));

            if (AllContributedForCurrentRound(id)) {
                allContributed[id] = true;
                UpkeepNeededForGroups[id] = true;
                s_UpkeepNeededGroupIds.push(id);

            }

        } else {
            revert Contribution__OutOfRound();
        }
    }

    function checkUpkeep(bytes memory /**checkData**/) public view override returns (bool upKeepNeeded, bytes memory performData) {
        uint len = s_UpkeepNeededGroupIds.length;
        if (len > 0) {
           upKeepNeeded = true;
           uint groupId = s_UpkeepNeededGroupIds[0];
           performData = abi.encode(groupId);
          
        }
        return (upKeepNeeded, performData);
    }

    function performUpkeep(bytes calldata performData) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");
        console.log(upkeepNeeded);
        if (!upkeepNeeded) {
            revert Contribution__UpKeep_Not_Yet_Needed();
        }
        uint groupId = abi.decode(performData,(uint));
        uint len = s_UpkeepNeededGroupIds.length;
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                    keyHash: i_keyHash,
                    subId: i_subscriptionId,
                    requestConfirmations: REQUEST_CONFIRMATIONS,
                    callbackGasLimit: callbackGasLimit,
                    numWords: NUM_wORDS,
                    extraArgs: VRFV2PlusClient._argsToBytes(
                        VRFV2PlusClient.ExtraArgsV1({
                           nativePayment: enableNativePayment
                        })
                    )
                })
            );
        vrfRequestIdToGroupId[requestId] = groupId;
        emit RequestedRoundWinner(requestId, groupId);
         s_UpkeepNeededGroupIds[0] = s_UpkeepNeededGroupIds[len - 1];
        s_UpkeepNeededGroupIds.pop();
    }

    function fulfillRandomWords (uint256 _requestId, uint256[] calldata randomWords) internal override  {
        uint groupId = vrfRequestIdToGroupId[_requestId];
        contributionGroup storage group = idToGroup[groupId];
        uint totalContributors = group.contributors.length;
        uint indexOfWinner = randomWords[0] % totalContributors;
        uint tries = 0;
        while (hasWon[groupId][group.contributors[indexOfWinner]]){
            indexOfWinner = (indexOfWinner + 1) % totalContributors;
            tries++;
            if (tries > totalContributors) revert Contribution__All_Contributors_Have_Been_Picked();
        }
        address payable winner = group.contributors[indexOfWinner];
        group.lastRoundWinner = winner;
        groupToLastRoundWinner[groupId] = winner;
        group.prevWinners.push(winner);

        //pay the winner
        (receiveContribution _contract) = callReceiveContribution();
        _contract.withdraw(groupId);
        (bool success, ) = winner.call{value : group.payout}("");
        require(success, "payout not successful");
        //reset currentRoundcontributedcontributors
        group.currentRoundContributedContributors = new address payable[](0);
        //emit events, update mappings
        emit currentRoundWinnerPicked(groupId, winner);
        address payable[2] memory _contributors;
        //After the last round or After the last contributor has been paid
        //to continue, they'll have to create another group
        if (block.timestamp >  group.contributionStopTime){
           group.isActive = false;
           group.contributors = _contributors;
           emit ContributionEnded(groupId); 
        }
    }



    function getIdByContributor(address _contributor) external view returns (uint){
         return contributorToId[_contributor];
    }

    function getGroupById(uint id) external view returns (contributionGroup memory group){
           group = idToGroup[id];
    }

    function isContributor(uint id, address contributor) external view returns (bool){
        contributionGroup memory group = idToGroup[id];
        for(uint i = 0; i < group.contributors.length; i++){
            if (group.contributors[i] == contributor) return true;
        }
        return false;
    }
    
    modifier _onlyOwner(){
        if (msg.sender != i_owner ){
            revert Contribution__Caller_Not_Owner();
        }
        _;
    }

    function withdraw() public _onlyOwner{
        (bool sent, ) = payable(msg.sender).call{value : address(this).balance}("");
        require(sent);
    }
    function setAddress(address payable _address) public _onlyOwner{
        s_contributionAddress = _address;
    }

    function callReceiveContribution() internal returns (receiveContribution){
        receiveContributionContract = receiveContribution(s_contributionAddress);
        return receiveContributionContract;   
    }

    fallback() external payable {}
    receive() external payable {}
    function getContributionAmount(uint id) external view returns (uint){
        return idToGroup[id].amount;
    }

    function getContributionStartTime(uint id) external view returns (uint){
        return idToGroup[id].contributionStartTime;
    }

    function getContributionStopTime(uint id) external view returns (uint){
        return idToGroup[id].contributionStopTime;
    }

    function getAllcontributed(uint id) external view returns (bool){
        return allContributed[id];
    } 

    function getRoundEnded(uint id) external view returns (bool){
        return roundEnded[id];
    }

    function getUpkeepNeededId(uint index) external view returns (uint){
          return s_UpkeepNeededGroupIds[index];
    } 
}
