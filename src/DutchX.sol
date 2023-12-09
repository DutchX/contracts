// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./vendor/IRouterClient.sol";

struct OrderInfo {
    address from;
    address fromToken;
    address toToken;
    uint256 fromChainId;
    uint256 toChainId;
    uint256 fromAmount;
    uint256 startingPrice;
    uint256 stakeAmount;
    uint256 timestamp;
    uint256 nonce;
}

struct ClaimedOrder {
    address from;
    address solver;
    address fromToken;
    address toToken;
    uint256 fromChainId;
    uint256 toChainId;
    uint256 fromAmount;
    uint256 toAmount;
    uint256 timestamp;
    bool isCompleted;
}

struct ExecuteOrder {
    bytes32 orderHash;
    address user;
    address solver;
    address token;
    uint256 amount;
}

contract DutchX {
    IRouterClient public ccipRouter;

    mapping(uint64 dstChain => address dutchX) public receiver;

    // mapping(address => uint256) public stakeAmounts;
    mapping(address => uint256) public userNonce;
    mapping(bytes32 => ClaimedOrder) public claimedOrders;
    mapping(bytes32 => address) public orderClaimedBy;

    modifier onlyRouter() {
        require(msg.sender == address(ccipRouter), "dutchX/caller not router");
        _;
    }

    constructor(address router_) {
        ccipRouter = IRouterClient(router_);
    }

    function claimOrder(bytes memory encodedOrderInfo, bytes memory signature) external {
        address signer = recoverSigner(encodedOrderInfo, signature);
        OrderInfo memory order = abi.decode(encodedOrderInfo, (OrderInfo));
        bytes32 orderHash = keccak256(encodedOrderInfo);

        require(signer == order.from, "Invalid signature");
        require(order.nonce == userNonce[signer], "Invalid nonce");
        require(order.fromChainId == block.chainid, "Invalid from chain id");
        require(orderClaimedBy[orderHash] == address(0), "Order already claimed");

        uint256 toAmount = calculateCurrentPrice(order.startingPrice, order.timestamp);
        require(toAmount > 0, "Order expired");

        claimedOrders[orderHash] = ClaimedOrder({
            from: order.from,
            solver: msg.sender,
            fromToken: order.fromToken,
            toToken: order.toToken,
            fromChainId: order.fromChainId,
            toChainId: order.toChainId,
            fromAmount: order.fromAmount,
            toAmount: toAmount,
            timestamp: block.timestamp,
            isCompleted: false
        });

        userNonce[signer] += 1;
        orderClaimedBy[orderHash] = msg.sender;

        //TODO: Transfer needs to be a seperate function with message signature check
        IERC20(order.fromToken).transferFrom(msg.sender, address(this), order.stakeAmount);
    }

    function executeOrder(uint256 fromChainId, bytes32 orderHash, address user, address token, uint256 amount)
        external
        payable
    {
        uint64 fromChainIdCasted = uint64(fromChainId);

        IERC20 tokenContract = IERC20(token);
        uint256 userBalanceBefore = tokenContract.balanceOf(user);
        tokenContract.transferFrom(msg.sender, user, amount);
        uint256 userBalanceAfter = tokenContract.balanceOf(user);

        require(userBalanceAfter - userBalanceBefore >= amount, "dutchX/revert transfer from");

        /// construct the ccip message
        EVM2AnyMessage memory message = EVM2AnyMessage(
            abi.encode(receiver[fromChainIdCasted]),
            abi.encode(ExecuteOrder(orderHash, user, msg.sender, token, amount)),
            new EVMTokenAmount[](0),
            address(0),
            bytes("")
        );

        ccipRouter.ccipSend{value: ccipRouter.getFee(fromChainIdCasted, message)}(fromChainIdCasted, message);
    }

    function ccipReceive(Any2EVMMessage memory message) external onlyRouter {
        /// ignore messageId storing for replay as we've innate replay protection
        ExecuteOrder memory orderExecuted = abi.decode(message.data, (ExecuteOrder));

        ClaimedOrder storage claimedOrder = claimedOrders[orderExecuted.orderHash];
        require(!claimedOrder.isCompleted, "dutchX/already executed");
        require(
            claimedOrder.toToken == orderExecuted.token && claimedOrder.toAmount <= orderExecuted.amount,
            "dutchX/ invalid filling on remote chain"
        );
        claimedOrder.isCompleted = true;

        IERC20(claimedOrder.fromToken).transfer(claimedOrder.solver, claimedOrder.fromAmount);
    }

    function calculateCurrentPrice(uint256 startingPrice, uint256 timestamp) internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - timestamp;
        uint256 price = startingPrice - (startingPrice * timeElapsed / 3600);
        return price;
    }

    function recoverSigner(bytes memory encodedData, bytes memory signature) public pure returns (address) {
        bytes32 messageHash = keccak256(encodedData);
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        (uint8 v, bytes32 r, bytes32 s) = splitSignature(signature);
        return ecrecover(ethSignedMessageHash, v, r, s);
    }

    function splitSignature(bytes memory signature) public pure returns (uint8, bytes32, bytes32) {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        return (v, r, s);
    }
}
