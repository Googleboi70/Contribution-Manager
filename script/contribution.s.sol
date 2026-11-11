//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {HelperConfig} from "script/helperConfig.s.sol";
import {Contribution} from "src/contribution.sol";
import {receiveContribution} from "src/receiveContribution.sol";
import {CreateSubscription, AddConsumer, FundSubscription} from "script/interactions.s.sol";
contract DeployContribution is Script{
     HelperConfig.NetworkConfig config;
    function run() public returns (Contribution, HelperConfig, receiveContribution){
        HelperConfig helperConfig = new HelperConfig();
        config = helperConfig.getConfig();
            if (config._subscriptionId == 0){
                CreateSubscription createSubscription = new CreateSubscription();
                (config._subscriptionId, config._vrfCoordinator)= createSubscription.createSubscription(config._vrfCoordinator,config.account);

               FundSubscription fundSubscription = new FundSubscription();
               fundSubscription.fundSubscription(config._vrfCoordinator,config._subscriptionId,config.link,config.account);
            }

        uint entranceFee = config._entranceFee;
        uint32 callbackGasLimit = config._callbackGasLimit;
        bytes32 keyHash = config.keyHash;
        uint256 subscriptionId = config._subscriptionId;
      //  address link = config.link;
        address account = config.account;
        address vrfCoordinator = config._vrfCoordinator;

        vm.startBroadcast(account);
        Contribution contribution = new Contribution(
            entranceFee,
            callbackGasLimit,
            keyHash,
            subscriptionId,
            vrfCoordinator
        );
        receiveContribution receive_Contribution = new receiveContribution(payable(address(contribution)));
        contribution.setAddress(payable(address(receive_Contribution)));
        vm.stopBroadcast();


        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(address(contribution),vrfCoordinator,subscriptionId,config.account);

        return (contribution, helperConfig, receive_Contribution);
    }
}