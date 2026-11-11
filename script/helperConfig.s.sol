//SPDX-License-Identifier:MIT
pragma solidity 0.8.30;
import {Contribution} from "src/contribution.sol";
import {Script, console2} from "lib/forge-std/src/Script.sol";
import {VRFCoordinatorV2_5Mock} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";

abstract contract CodeConstants{
    uint96 public constant MOCK_BASE_FEE = 0.25 ether;
    uint96 public constant MOCK_GAS_PRICE_LINK = 1e9;
    // LINK / ETH price
    int256 public constant MOCK_WEI_PER_UINT_LINK = 4e15;

    address public constant FOUNDRY_DEFAULT_SENDER =
        0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ETH_MAINNET_CHAIN_ID = 1;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
}
contract HelperConfig is Script, CodeConstants{

    mapping (uint => NetworkConfig) idToConfig;

    struct NetworkConfig{
        uint _entranceFee;
        uint32 _callbackGasLimit;
        bytes32 keyHash;
        uint256 _subscriptionId;
        address _vrfCoordinator;
        address link;
        address account;
    }

    NetworkConfig public anvilConfig;

   constructor (){
    if (block.chainid == ETH_SEPOLIA_CHAIN_ID){
       idToConfig[block.chainid] = getSepoliaEthConfig();   
    }else{
        idToConfig[block.chainid] = getAnvilConfig();
    }
   }

   function getSepoliaEthConfig() public pure returns (NetworkConfig memory){
        NetworkConfig memory sepoliaConfig = NetworkConfig({
            _entranceFee : 0.0001 ether,
            _callbackGasLimit : 500_000,
            keyHash : 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            _subscriptionId : 41050699971850943085760090219252719432271208305023409422966357813251030827681,
            _vrfCoordinator : 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
            link : 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            account : 0x8D6cD042f6f0236EAADD5Dccef99E64e7D588d01
        });
        return sepoliaConfig;
   }
 
   function setConfig(uint chainId, NetworkConfig memory config) public {
       idToConfig[chainId] = config;
   }
   function getAnvilConfig() public returns (NetworkConfig memory){
        if (anvilConfig._vrfCoordinator != address(0)){
            return anvilConfig;
        }
        console2.log(unicode"⚠️ You have deployed a mock conract!");
        console2.log("Make sure this was intentional");
        vm.startBroadcast();
           VRFCoordinatorV2_5Mock mockVrf = new VRFCoordinatorV2_5Mock(
                MOCK_BASE_FEE,
                MOCK_GAS_PRICE_LINK,
                MOCK_WEI_PER_UINT_LINK
            );
           LinkToken link = new LinkToken();
        vm.stopBroadcast();
        anvilConfig = NetworkConfig({
            _entranceFee : 0.01 ether,
            _callbackGasLimit : 500_000,
            keyHash : 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            _subscriptionId : 0,
            _vrfCoordinator : address(mockVrf),
            link : address(link),
            account : FOUNDRY_DEFAULT_SENDER
        });
        return anvilConfig;
   }

   function getConfigByChainId(uint id) public view returns (NetworkConfig memory){
       return idToConfig[id];
   }

   function getConfig() public view returns (NetworkConfig memory){
      return getConfigByChainId(block.chainid);
   }
}