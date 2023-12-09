// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import "src/DutchX.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract DeployScript is Script {
    DutchX public dutchXETH;
    DutchX public dutchXBase;

    MockERC20 public usdt;
    MockERC20 public wstETH;

    uint256 ETH_FORK;
    uint256 BASE_FORK;

    function run() public {
        ETH_FORK = vm.createSelectFork(vm.envString("ETH_RPC"));
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        dutchXETH = new DutchX(0xD0daae2231E9CB96b94C8512223533293C3693Bf);
        // usdt = new MockERC20(100e18, "USDT", "USDT");
        // usdt.transfer(user, 50e18);
        // usdt.transfer(solver, 50e18);
        vm.stopBroadcast();

        BASE_FORK = vm.createSelectFork(vm.envString("BASE_RPC"));
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        dutchXBase = new DutchX(0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D);
        dutchXBase.setReceiver(16015286601757825753, address(dutchXETH));
        // wstETH = new MockERC20(100e18, "WrappedStEth", "WSTETH");
        // wstETH.transfer(solver, 50e18);
        vm.stopBroadcast();

        vm.selectFork(ETH_FORK);
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        dutchXETH.setReceiver(5790810961207155433, address(dutchXBase));
        vm.stopBroadcast();
    }
}
