// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import "src/DutchX.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract DutchXTest is Test {
    DutchX public dutchXPolygon;
    DutchX public dutchXBase;

    MockERC20 public usdt;
    MockERC20 public wstETH;

    uint256 POLYGON_FORK;
    uint256 BASE_FORK;

    uint256 POLYGON_CHAIN_ID = 80001;
    uint256 BASE_CHAIN_ID = 84531;

    address user;
    address solver;

    function setUp() external {
        user = vm.addr(420);
        solver = vm.addr(69);

        POLYGON_FORK = vm.createSelectFork(vm.envString("POLYGON_RPC"));
        dutchXPolygon = new DutchX(0x70499c328e1E2a3c41108bd3730F6670a44595D1);
        usdt = new MockERC20(100e18, "USDT", "USDT");
        usdt.transfer(user, 50e18);
        usdt.transfer(solver, 50e18);

        BASE_FORK = vm.createSelectFork(vm.envString("BASE_RPC"));
        dutchXBase = new DutchX(0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D);
        wstETH = new MockERC20(100e18, "WrappedStEth", "WSTETH");
        wstETH.transfer(solver, 50e18);
    }

    function test_validOrder() external {
        vm.selectFork(POLYGON_FORK);

        vm.startPrank(user);
        usdt.approve(address(dutchXPolygon), 10e18);
        UserOrder memory order = UserOrder(
            user,
            POLYGON_CHAIN_ID,
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
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(420, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.startPrank(solver);
        usdt.approve(address(dutchXPolygon), 1e18);
        dutchXPolygon.claimOrder(abi.encode(order), signature);
        vm.stopPrank();

        vm.selectFork(BASE_FORK);
        vm.startPrank(solver);
        wstETH.approve(address(dutchXBase), 996666666666666697);

        dutchXBase.executeOrder(POLYGON_CHAIN_ID, "blah blah black sheep", user, address(wstETH), 996666666666666697);
    }
}
