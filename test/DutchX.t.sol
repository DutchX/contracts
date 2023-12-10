// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import "src/DutchX.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import "forge-std/console.sol";

contract DutchXTest is Test {
    DutchX public dutchXETH;
    DutchX public dutchXBase;

    MockERC20 public usdt;
    MockERC20 public wstETH;

    uint256 ETH_FORK;
    uint256 BASE_FORK;

    uint256 ETH_CHAIN_ID = 11155111;
    uint256 BASE_CHAIN_ID = 84531;

    address user;
    address solver;

    function setUp() external {
        user = vm.addr(vm.envUint("PRIVATE_KEY"));
        solver = vm.addr(vm.envUint("SOLVER_PRIVATE_KEY"));

        ETH_FORK = vm.createSelectFork(vm.envString("ETH_RPC"));
        dutchXETH = DutchX(0xc1E262C291229db17B8C17c4a598869Ee48d9Dac);
        usdt = MockERC20(0xfb8c7dD1E47b57a3308f52B55244f974b1E319A0);
        // usdt.transfer(user, 50e18);
        // usdt.transfer(solver, 50e18);

        BASE_FORK = vm.createSelectFork(vm.envString("BASE_RPC"));
        dutchXBase = DutchX(0x668Cb4EadBAc6F9b78C67924499C8de16749F351);
        wstETH = MockERC20(0xfb8c7dD1E47b57a3308f52B55244f974b1E319A0);
        // wstETH.transfer(solver, 50e18);

        // vm.selectFork(ETH_FORK);
        // dutchXETH.setReceiver(5790810961207155433, address(dutchXBase));

        // vm.selectFork(BASE_FORK);
        // dutchXBase.setReceiver(16015286601757825753, address(dutchXETH));
    }

    function test_decode() external {
        ExecutedOrder memory data = abi.decode(
            hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000046a23e25df9a0f6c18729dda9ad1af3b6a1311600000000000000000000000000b04f0774084f00f8b9fb4ecf8de0ba44c2ca5bb000000000000000000000000fb8c7dd1e47b57a3308f52b55244f974b1e319a00000000000000000000000000000000000000000000000008ac7230489e8000000000000000000000000000000000000000000000000000000000000657493ae0000000000000000000000000000000000000000000000000000000000000015626c616820626c616820626c61636b2073686565700000000000000000000000",
            (ExecutedOrder)
        );
        console.log(data.orderHash);
        console.log(data.amount);
        console.log(data.token);
    }

    function test_validOrder() external {
        vm.selectFork(ETH_FORK);
        vm.startPrank(user);
        usdt.approve(address(dutchXETH), 11e18);
        UserOrder memory order = UserOrder(
            user,
            ETH_CHAIN_ID,
            address(usdt),
            10e18,
            BASE_CHAIN_ID,
            address(wstETH),
            1e18,
            0.9e18,
            1e18,
            block.timestamp - 40 seconds,
            180 seconds,
            0,
            "blah blah black sheep"
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encode(order))));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(vm.envUint("PRIVATE_KEY"), digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        console.log(block.timestamp - 40 seconds);
        console.logBytes32(digest);
        console.logBytes(signature);
        console.logBytes(abi.encode(order));
        vm.stopPrank();

        vm.startPrank(solver);
        usdt.approve(address(dutchXETH), 11e18);
        dutchXETH.claimOrder(abi.encode(order), signature);

        vm.stopPrank();

        vm.selectFork(BASE_FORK);
        vm.startPrank(solver);
        deal(solver, 1 ether);
        wstETH.approve(address(dutchXBase), 996666666666666697);

        dutchXBase.executeOrder{value: 0.09 etherg}(
            ETH_CHAIN_ID, "blah blah black sheep", user, address(wstETH), 996666666666666697
        );
        vm.stopPrank();

        console.logBytes4(dutchXETH.ccipReceive.selector);
        vm.selectFork(ETH_FORK);
        address ccipRouter = address(dutchXETH.ccipRouter());
        vm.startPrank(ccipRouter);
        dutchXETH.ccipReceive(
            Client.Any2EVMMessage(
                0xfa0f5f46c2be94033bd1a789a67116730a43f276a11b3684a649f7912709fc3c,
                5790810961207156000,
                hex"000000000000000000000000550393bb7a6acb6b9a70345ef67d74c87d4496c2",
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000046a23e25df9a0f6c18729dda9ad1af3b6a1311600000000000000000000000000b04f0774084f00f8b9fb4ecf8de0ba44c2ca5bb000000000000000000000000fb8c7dd1e47b57a3308f52b55244f974b1e319a00000000000000000000000000000000000000000000000008ac7230489e8000000000000000000000000000000000000000000000000000000000000657493ae0000000000000000000000000000000000000000000000000000000000000015626c616820626c616820626c61636b2073686565700000000000000000000000",
                new Client.EVMTokenAmount[](0)
            )
        );
    }
}
