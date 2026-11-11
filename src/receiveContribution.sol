//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import {Contribution} from "./contribution.sol";

contract receiveContribution{

    Contribution contribution;
    mapping (address => uint) contributorToId;
    mapping (uint => Contribution.contributionGroup) idToGroup;
    mapping (uint => contributionInfo) idToContributionInfo;
    event contributionReceived(address indexed contributor, contributionInfo _contributorInfo, uint indexed id);
    event contributionWithdrawn(uint groupId, uint roundNm);

    error receiveContribution__Insufficient_Contribution_Amount();
    error receiveContribution__Caller_Not_Contribution();
    error receiveContribution__Not_Contributor();
    error receiveContribution__Failed_To_Send_Ether();

    struct contributionInfo{
        uint id;
        uint amount;
        uint timeContributed;
        Contribution.contributionGroup contributionGroup;
        uint payout;
    }


    constructor(address payable _contribution) {
        contribution = Contribution(_contribution);
    } 

    receive() external payable{
    
    }
    

    function receiveContributionData(uint _amount, uint _id, address _contributor) external {
       uint Amount = _amount;
       uint id = _id;
       address contributor = _contributor;
        contributorToId[contributor] = id;
        idToGroup[id] = contribution.getGroupById(id);
       Contribution.contributionGroup memory group = contribution.getGroupById(id);
        contributionInfo memory _contributorInfo = contributionInfo({
            id: contributorToId[contributor],
            amount: Amount,
            timeContributed: block.timestamp,
            contributionGroup: idToGroup[id],
            payout : group.payout
        });
        idToContributionInfo[id] = _contributorInfo;
        emit contributionReceived(contributor, _contributorInfo, id);
        
    }
    modifier onlyContribution(){
        if (msg.sender != address(contribution )){
            revert receiveContribution__Caller_Not_Contribution();
        }
        _;
    }
    
    function withdraw(uint id) external onlyContribution {
       uint roundNumber = contribution.getCurrentRoundNumber(id);
       contributionInfo memory info = idToContributionInfo[id]; 
       uint _value = info.payout;
       (bool success, ) = payable(msg.sender).call{value : _value}("");
       if (!success){
            revert receiveContribution__Failed_To_Send_Ether();
       }
       emit contributionWithdrawn(id, roundNumber); 
    }
}