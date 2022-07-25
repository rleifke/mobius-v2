//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import "./libraries/LongTermOrders.sol";

///@title Mobius V2 
///@author Mobius Team 
///@notice TWAMM implementation for Uniswap v3 on Celo. 
// https://www.paradigm.xyz/2021/07/twamm/


contract TWAMM is ITWAMM, ReentrancyGuard {
    using LongTermOrdersLib for LongTermOrdersLib.LongTermOrders;
    using PRBMathUD60x18 for uint256;

    /// ---------------------------
    /// ------ AMM Parameters -----
    /// ---------------------------
    
    ///@notice tokens that can be traded in the AMM
    address public token0;
    address public token1;
    
    ///@notice map token addresses to current amm reserves
    mapping(address => uint256) reserveMap;

    /// ---------------------------
    /// -----TWAMM Parameters -----
    /// ---------------------------

    ///@notice interval between blocks that are eligible for order expiry 
    uint256 public orderBlockInterval;

    ///@notice data structure to handle long term orders  
    LongTermOrdersLib.LongTermOrders internal longTermOrders;

    /// ---------------------------
    /// --------- Events ----------
    /// ---------------------------

    ///@notice An event emitted when initial liquidity is provided 
    event InitialLiquidityProvided(address indexed addr, uint256 amount0, uint256 amount1);

    ///@notice An event emitted when liquidity is provided 
    event LiquidityProvided(address indexed addr, uint256 lpTokens);

    ///@notice An event emitted when liquidity is removed 
    event LiquidityRemoved(address indexed addr, uint256 lpTokens);

    ///@notice An event emitted when a swap from tokenA to tokenB is performed 
    event SwapATo1(address indexed addr, uint256 amount0In, uint256 amount1Out);

    ///@notice An event emitted when a swap from tokenB to tokenA is performed 
    event SwapBTo0(address indexed addr, uint256 amount1In, uint256 amount0Out);

    ///@notice An event emitted when a long term swap from tokenA to tokenB is performed 
    event LongTermSwap0To1(address indexed addr, uint256 amount0In, uint256 orderId);

    ///@notice An event emitted when a long term swap from tokenB to tokenA is performed 
    event LongTermSwap1To0(address indexed addr, uint256 amount1In, uint256 orderId);

    ///@notice An event emitted when a long term swap is cancelled
    event CancelLongTermOrder(address indexed addr, uint256 orderId);

    ///@notice An event emitted when proceeds from a long term swap are withdrawm 
    event WithdrawProceedsFromLongTermOrder(address indexed addr, uint256 orderId);

    
    constructor(address operator,
                address recipient,
                address _token0,
                address _token1,
                uint256 _orderBlockInterval) 
    {
        token0 = _token0;
        token1 = _token1;
        orderBlockInterval = _orderBlockInterval;
        longTermOrders.initialize(_token0, _token1, block.number, _orderBlockInterval);
    }

    ///@notice provide initial liquidity to the amm. This sets the relative price between tokens
    function provideInitialLiquidity(uint256 amount0, uint256 amount1) external nonReentrant {
        require(totalSupply == 0, 'liquidity has already been provided, need to call provideLiquidity');

        reserveMap[token0] = amount0;
        reserveMap[token1] = amount1;
        
        //initial LP amount is the geometric mean of supplied tokens
        uint256 lpAmount = amount0.fromUint().sqrt().mul(amountB.fromUint().sqrt()).toUint();
        _mint(msg.sender, lpAmount);

        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);

        emit InitialLiquidityProvided(msg.sender, amount0, amount1);
    }

    ///@notice provide liquidity to the AMM 
    ///@param lpTokenAmount number of lp tokens to mint with new liquidity  
    function provideLiquidity(uint256 lpTokenAmount) external nonReentrant {
        require(totalSupply != 0, 'no liquidity has been provided yet, need to call provideInitialLiquidity');

        //execute virtual orders 
        longTermOrders.executeVirtualOrdersUntilCurrentBlock(reserveMap);

        //the ratio between the number of underlying tokens and the number of lp tokens must remain invariant after mint 
        uint256 amount0In = lpTokenAmount * reserveMap[token0] / totalSupply;
        uint256 amount1In = lpTokenAmount * reserveMap[token1] / totalSupply;

        reserveMap[tokenA] += amount0In;
        reserveMap[tokenB] += amount1In;

        _mint(msg.sender, lpTokenAmount);

        token1.safeTransferFrom(msg.sender, address(this), amount0In);
        token2.safeTransferFrom(msg.sender, address(this), amount1In);
        
        emit LiquidityProvided(msg.sender, lpTokenAmount);
    }

    ///@notice remove liquidity to the AMM 
    ///@param lpTokenAmount number of lp tokens to burn
    function removeLiquidity(uint256 lpTokenAmount) external nonReentrant {
        require(lpTokenAmount <= totalSupply, 'not enough lp tokens available');

        //execute virtual orders 
        longTermOrders.executeVirtualOrdersUntilCurrentBlock(reserveMap);
        
        //the ratio between the number of underlying tokens and the number of lp 
        //tokens must remain invariant after burn 
        uint256 amount0Out = reserveMap[token0] * lpTokenAmount / totalSupply;
        uint256 amount1Out = reserveMap[token1] * lpTokenAmount / totalSupply;

        reserveMap[token0] -= amount0Out;
        reserveMap[token1] -= amount1Out;

        _burn(msg.sender, lpTokenAmount);

        token0.safeTransfer(msg.sender, amount0Out);
        token1.safeTransfer(msg.sender, amount1Out);

        emit LiquidityRemoved(msg.sender, lpTokenAmount);
    }

    ///@notice swap a given amount of Token0 against v3 amm
    function swapFrom0To1(uint256 amount0In) external nonReentrant {
        uint256 amount1Out = performSwap(token0, token1, amount0In);
        emit Swap0To1(msg.sender, amount0In, amount1Out);
    }

    ///@notice create a long term order to swap from token0 
    ///@param amount0In total amount of token 0 to swap 
    ///@param numberOfBlockIntervals number of block intervals over which to execute long term order
    function longTermSwapFrom0To1(uint256 amount0In, uint256 numberOfBlockIntervals) external nonReentrant {
        uint256 orderId =  longTermOrders.longTermSwapFrom0To1(amountAIn, numberOfBlockIntervals, reserveMap);
        emit LongTermSwap0To1(msg.sender, amount0In, orderId);
    }

    ///@notice swap a given amount of Token1 against Uniswap v3 amm 
    function swapFrom1To0(uint256 amount1In) external nonReentrant {
        uint256 amount0Out = performSwap(token1, token0, amountBIn);
        emit SwapBToA(msg.sender, amount1In, amount0Out);
    }

    ///@notice create a long term order to swap from tokenB 
    ///@param amountBIn total amount of tokenB to swap 
    ///@param numberOfBlockIntervals number of block intervals over which to execute long term order
    function longTermSwapFrom1To0(uint256 amountBIn, uint256 numberOfBlockIntervals) external nonReentrant {
        uint256 orderId = longTermOrders.longTermSwapFrom1To0(amount1In, numberOfBlockIntervals, reserveMap);
        emit LongTermSwap1To0(msg.sender, amount1In, orderId);
    }

    ///@notice stop the execution of a long term order 
    function cancelLongTermSwap(uint256 orderId) external nonReentrant {
        longTermOrders.cancelLongTermSwap(orderId, reserveMap);
        emit CancelLongTermOrder(msg.sender, orderId);
    }

    ///@notice withdraw proceeds from a long term swap 
    function withdrawProceedsFromLongTermSwap(uint256 orderId) external nonReentrant {
        longTermOrders.withdrawProceedsFromLongTermSwap(orderId, reserveMap);
        emit WithdrawProceedsFromLongTermOrder(msg.sender, orderId);
    }

    ///@notice private function which implements swap logic 
    function performV3Swap(address operator, address recipient, uint256 amountIn) private returns (uint256 amountOutMinusFee) {
        require(amountIn > 0, 'swap amount must be positive');

        //execute virtual orders 
        longTermOrders.executeVirtualOrdersUntilCurrentBlock(reserveMap);

        //TODO: Modify this to call V3 swap router.
        
        reserveMap[from] += amountIn;
        reserveMap[to] -= amountOutMinusFee;

        operator.safeTransferFrom(msg.sender, address(this), amountIn);  
        recipient.safeTransfer(msg.sender, amountOutMinusFee);
    }

    ///@notice get token0 reserves
    function token0Reserves() public view returns (uint256) {
        return reserveMap[tokenA];
    }

    ///@notice get token1 reserves
    function token1Reserves() public view returns (uint256) {
        return reserveMap[tokenB];
    }

    ///@notice convenience function to execute virtual orders. Note that this already happens
    ///before most interactions with the AMM 
    function executeVirtualOrders() public {
        longTermOrders.executeVirtualOrdersUntilCurrentBlock(reserveMap);
    }

    
}