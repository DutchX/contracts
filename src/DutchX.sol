// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./vendor/IRouterClient.sol";

struct UserOrder {
    address from;
    uint256 fromChainId;
    address fromToken;
    uint256 fromAmount;
    uint256 toChainId;
    address toToken;
    uint256 startingPrice;
    uint256 endingPrice;
    uint256 stakeAmount;
    uint256 creationTimestamp;
    uint256 duration;
    uint256 nonce;
    string orderId;
}

struct ClaimedOrder {
    address from;
    address solver;
    address fromToken;
    uint256 fromChainId;
    uint256 fromAmount;
    address toToken;
    uint256 toChainId;
    uint256 toAmount;
    uint256 stakeAmount;
    uint256 deadline;
    bool isCompleted;
}

struct ExecutedOrder {
    string orderHash;
    address user;
    address solver;
    address token;
    uint256 amount;
    uint256 executedTime;
}

contract DutchX {
    uint256 public constant SOLVER_PERIOD = 3 minutes;
    IRouterClient public ccipRouter;

    mapping(address user => uint256 nonce) public userNonce;
    mapping(uint64 dstChain => address dutchX) public receiver;
    mapping(string orderHash => ClaimedOrder) public claimedOrders;
    mapping(uint256 nativeChainId => uint64 chainlinkChainId) public chainlinkChainId;

    modifier onlyRouter() {
        require(msg.sender == address(ccipRouter), "dutchX/caller not router");
        _;
    }

    constructor(address router_) {
        ccipRouter = IRouterClient(router_);

        /// intialize the starting chainids
        chainlinkChainId[11155111] = 16015286601757825753;
        chainlinkChainId[84531] = 5790810961207155433;
    }

    function setReceiver(uint64 dstChain, address dutchX) external {
        receiver[dstChain] = dutchX;
    }

    function claimOrder(bytes memory encodedUserOrder, bytes memory signature) external {
        address signer = recoverSigner(encodedUserOrder, signature);

        UserOrder memory order = abi.decode(encodedUserOrder, (UserOrder));
        ClaimedOrder storage claimedOrder = claimedOrders[order.orderId];

        require(signer == order.from, "dutchX/invalid signature");
        require(order.nonce == userNonce[signer], "dutchX/invalid nonce");
        require(order.fromChainId == block.chainid, "dutchX/invalid from chain id");
        require(claimedOrder.solver == address(0), "dutchX/order already claimed");
        require(block.timestamp < order.creationTimestamp + order.duration, "dutchX/order expired");

        uint256 toAmount =
            calculateToAmount(order.startingPrice, order.endingPrice, order.duration, order.creationTimestamp);

        claimedOrder.from = order.from;
        claimedOrder.solver = msg.sender;
        claimedOrder.fromToken = order.fromToken;
        claimedOrder.fromChainId = block.chainid;
        claimedOrder.fromAmount = order.fromAmount;
        claimedOrder.toToken = order.toToken;
        claimedOrder.toChainId = order.toChainId;
        claimedOrder.toAmount = toAmount;
        claimedOrder.stakeAmount = order.stakeAmount;
        claimedOrder.deadline = block.timestamp + SOLVER_PERIOD;

        unchecked {
            ++userNonce[signer];
        }

        IERC20(claimedOrder.fromToken).transferFrom(claimedOrder.from, address(this), claimedOrder.fromAmount);
        IERC20(claimedOrder.fromToken).transferFrom(claimedOrder.solver, address(this), claimedOrder.stakeAmount);
    }

    function executeOrder(uint256 fromChainId, string memory orderHash, address user, address token, uint256 amount)
        external
        payable
    {
        uint64 fromChainIdCasted = chainlinkChainId[fromChainId];

        IERC20 tokenContract = IERC20(token);
        uint256 userBalanceBefore = tokenContract.balanceOf(user);
        tokenContract.transferFrom(msg.sender, user, amount);
        uint256 userBalanceAfter = tokenContract.balanceOf(user);

        require(userBalanceAfter - userBalanceBefore >= amount, "dutchX/revert transfer from");

        /// construct the ccip message
        EVM2AnyMessage memory message = EVM2AnyMessage(
            abi.encode(receiver[fromChainIdCasted]),
            abi.encode(ExecutedOrder(orderHash, user, msg.sender, token, amount, block.timestamp)),
            new EVMTokenAmount[](0),
            address(0),
            abi.encodeWithSelector(0x97a657c9, EVMExtraArgsV1({gasLimit: 200_000, strict: true}))
        );

        ccipRouter.ccipSend{value: ccipRouter.getFee(fromChainIdCasted, message)}(fromChainIdCasted, message);
    }

    function ccipReceive(Any2EVMMessage memory message) external onlyRouter {
        /// ignore messageId storing for replay as we've innate replay protection
        ExecutedOrder memory orderExecuted = abi.decode(message.data, (ExecutedOrder));
        ClaimedOrder storage claimedOrder = claimedOrders[orderExecuted.orderHash];

        require(!claimedOrder.isCompleted, "dutchX/already executed");
        require(
            claimedOrder.toToken == orderExecuted.token && claimedOrder.toAmount <= orderExecuted.amount,
            "dutchX/ invalid filling on remote chain"
        );
        claimedOrder.isCompleted = true;

        IERC20(claimedOrder.fromToken).transfer(claimedOrder.solver, claimedOrder.fromAmount + claimedOrder.stakeAmount);
    }

    function calculateToAmount(
        uint256 startingPrice,
        uint256 endingPrice,
        uint256 duration,
        uint256 orderCreatingTimestamp
    ) internal view returns (uint256 toAmount) {
        uint256 decayFreq = (block.timestamp - orderCreatingTimestamp - 30) / 6;
        /// 6 sec decay
        uint256 decayAmount = (startingPrice - endingPrice) * 6 / duration - 30;
        toAmount = startingPrice - (decayFreq * decayAmount);
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
