//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {Contribution} from "src/contribution.sol";
import {Test, console} from "lib/forge-std/src/Test.sol";
import {DeployContribution} from "script/contribution.s.sol";
import {HelperConfig} from "script/helperConfig.s.sol";
import {receiveContribution} from "src/receiveContribution.sol";
import {VRFCoordinatorV2_5Mock} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
contract testContribution is Test {
    uint256 entranceFee;
    uint32 callbackGasLimit;
    bytes32 keyHash;
    uint256 subscriptionId;
    address vrfCoordinator;
    address payable[2] contributors;
    uint interval = 10 ;
    address account;
    uint amount = 1 ether;
    event groupCreated(address payable[2] _contributors, uint _amount, uint _interval, uint _numberOfContributors);
    
    Contribution contribution;
    HelperConfig helperConfig;
    receiveContribution receive_Contribution;
    address DEFAULT__SENDER;
    address ADMIN = makeAddr("ADMIN");
    address payable ALICE = payable(makeAddr("Alice"));  
    address payable BOB = payable(makeAddr("Bob"));
    function setUp() public{
        vm.deal(ADMIN, 5 ether);
        vm.deal(ALICE, 5 ether);
        vm.deal(BOB, 5 ether);
        DeployContribution deployContribution = new DeployContribution();
        (contribution, helperConfig, receive_Contribution) = deployContribution.run();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config._entranceFee;
        callbackGasLimit = config._callbackGasLimit;
        keyHash = config.keyHash;
        subscriptionId = config._subscriptionId;
        vrfCoordinator = config._vrfCoordinator;
        account = config.account;
    }
    
    //createContribution tests
    function testContributionStateIsOpenByDefault() public {
        vm.prank(ADMIN);
       Contribution.ContributionState state = contribution.s_ContributionState();
       assert(state == Contribution.ContributionState.OPEN);
    }
     
     modifier ifFork(){
        if (block.chainid != 31337){
            DEFAULT__SENDER = account;
        }else{
            DEFAULT__SENDER = DEFAULT_SENDER;
        }
        
        _;
     }
    function testOwnerIsMsgSender() public ifFork{
        vm.prank(ADMIN);
        address sender = contribution.i_owner();
        assert(sender == DEFAULT__SENDER); 
    }


    function testRevertsOnInsufficientEntranceFee() public {
        vm.prank(ADMIN);
        contributors = [ALICE, BOB];
        vm.expectRevert(Contribution.Contribution__InsufficientFee.selector);
        contribution.createContributionGroup(contributors, 0.0001 ether, 30 seconds);
    }

    function testGroupIdVariesOnMultipleCreationAtOnce() public {
        vm.prank(ADMIN); 
        contributors = [ALICE, BOB];
        contribution.createContributionGroup{value : entranceFee}(contributors, 0.001 ether, 55 seconds);
        vm.prank(ALICE);
        contribution.createContributionGroup{value : entranceFee}(contributors, 0.001 ether, 55 seconds);
        vm.prank(BOB);
        contribution.createContributionGroup{value : entranceFee}(contributors, 0.001 ether, 55 seconds);
        //sent by DEFAULT_SENDER
        contribution.createContributionGroup{value : entranceFee}(contributors, 0.001 ether, 55 seconds);     
    }   
    
    function testRevertsIfSenderIsTryingToCreateMultipleGroups() public {
        vm.startPrank(ADMIN);
        contributors = [ALICE, BOB];
        contribution.createContributionGroup{value : entranceFee}(contributors, 0.001 ether, 55 seconds);
        vm.expectRevert(Contribution.Contribution__Cannot_Create_More_Than_One_Group.selector);
        contribution.createContributionGroup{value : entranceFee}(contributors, 0.001 ether, 55 seconds);
        vm.stopPrank();  
    }

    function testRevertsOnAddressZeroMembership() public {
        vm.prank(ADMIN);
        contributors = [ALICE, payable(address(0))];
        vm.expectRevert(Contribution.Contribution__AddressZeroNotAllowed.selector);
        contribution.createContributionGroup{value : entranceFee}(contributors, 0.001 ether, 55 seconds);
        
    }

    function testEmitsEventUponGroupCreation() public{
        vm.prank(ADMIN);
        contributors = [ALICE, BOB];
        vm.expectEmit(false, false, false, false);
        emit groupCreated(contributors, 0.001 ether, 55 , 2);
        contribution.createContributionGroup{value : entranceFee}(contributors, 0.001 ether, 55 seconds);
    }

    function testIdIsMappedToGroupUponCreation() public{
        vm.prank(ADMIN);
        contributors = [ALICE, BOB];
        (uint id) = contribution.createContributionGroup{value : entranceFee}(contributors, 0.001 ether, 55 seconds);
        address alice = contribution.getGroupById(id).contributors[0];
        address bob = contribution.getGroupById(id).contributors[1];
        assertEq(alice, ALICE);
        assertEq(bob, BOB);
    }
   //Contribute tests
    function testCanContribute() public {
        vm.prank(ADMIN);
        contributors = [ALICE, BOB];
        uint id = contribution.createContributionGroup{value : entranceFee}(contributors, 1 ether, interval);
        vm.prank(ALICE);    
        contribution.contribute{value : 1 ether}(id);    
    }

    function testRevertsIfNonMemberTriesToContribute() public {
        vm.prank(ADMIN);
        contributors = [ALICE, BOB];
        uint id =  contribution.createContributionGroup{value : entranceFee}(contributors, 0.001 ether, interval);
        vm.expectRevert(Contribution.Contribution__senderNotInGroup.selector);
        vm.prank(ADMIN);
        contribution.contribute(id);
    }

    function testUpdatesArrayUponContribution() public {
        vm.prank(ADMIN);
        contributors = [ALICE, BOB];
        uint id = contribution.createContributionGroup{value : entranceFee}(contributors, amount, interval);
        vm.prank(ALICE);    
        contribution.contribute{value : amount}(id);
        vm.prank(BOB);
        contribution.contribute{value : amount}(id);
        address bob = contribution.getGroupById(id).currentRoundContributedContributors[1];
        address alice = contribution.getGroupById(id).currentRoundContributedContributors[0];
        vm.assertEq(alice, ALICE);
        vm.assertEq(bob, BOB);
        
    }

    function testAllContributedReturnsTrueIfAllMembersContribute() public {
        vm.prank(ADMIN);
        contributors = [ALICE, BOB];
        uint id = contribution.createContributionGroup{value : entranceFee}(contributors, amount, interval);
        vm.prank(ALICE);    
        contribution.contribute{value : amount}(id);
        
        vm.prank(BOB);    
        contribution.contribute{value : amount}(id);
        //(bool status) = contribution.getAllcontributed(id);
    //    assertEq(status, true);
        (bool upKeepNeeded, ) = contribution.checkUpkeep("");
        vm.assertEq(upKeepNeeded, true);
    }

    function testPerformUpkeepResetsCurrentRoundArray() public {
        vm.prank(ADMIN);
        contributors = [ALICE, BOB];
        uint id = contribution.createContributionGroup{value : entranceFee}(contributors, amount, interval);
        vm.prank(ALICE);    
        contribution.contribute{value : amount}(id);
        
        vm.prank(BOB);    
        contribution.contribute{value : amount}(id);
       
        (bool upKeepNeeded, bytes memory performData) = contribution.checkUpkeep("");
        if (upKeepNeeded){
        contribution.performUpkeep(performData);
        }

        vm.expectRevert();   
        uint _id = contribution.getUpkeepNeededId(0);
    }

    modifier skipFork() {
        if (block.chainid != 31337){
            return;
        }
        _;
    }
    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep() public skipFork {
        //since it is the vrfCoordinator that will call fulfillRandomWords, we say
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(1, address(contribution));
    }

    function testWinnerIsPaidUponFulfillRandomWords() public skipFork {
        vm.prank(ADMIN);
        contributors = [ALICE, BOB];
        uint id = contribution.createContributionGroup{value : entranceFee}(contributors, amount, interval);
        vm.prank(ALICE);    
        contribution.contribute{value : amount}(id);
        
        vm.prank(BOB);    
        contribution.contribute{value : amount}(id);
        uint256 initialBalanceAlice = ALICE.balance;
        uint256 initialBalanceBob = BOB.balance;
       
        (bool upkeepNeeded, bytes memory performData) = contribution.checkUpkeep("");
        
            vm.recordLogs();
            contribution.performUpkeep(performData);
            // Vm.Log[] memory entries = vm.getRecordedLogs();
            // bytes32 requestId = entries[1].topics[1];
        vm.warp(block.timestamp + (interval * 2) + 1);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(1, address(contribution));
        Contribution.contributionGroup memory group = contribution.getGroupById(id);
        address winner = group.lastRoundWinner;
        if (winner == ALICE){
            vm.assertEq(ALICE.balance, initialBalanceAlice + (2 * amount));
            vm.assertEq(BOB.balance, initialBalanceBob);
        } else if (winner == BOB){
            vm.assertEq(BOB.balance, initialBalanceBob + (2 * amount));
            vm.assertEq(ALICE.balance, initialBalanceAlice);
        }       

    }
}