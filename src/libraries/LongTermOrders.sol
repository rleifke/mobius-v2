//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;


///@notice This library handles the state and execution of long term orders. 
library LongTermOrdersLib {
    using PRBMathSD59x18 for int256;
    using OrderPoolLib for OrderPoolLib.OrderPool;
    using SafeTransferLib for ERC20;

    ///@notice information associated with a long term order 
    struct Order {
        uint256 id;
        uint256 expirationBlock;
        uint256 saleRate;
        address owner; 
        address sellTokenId;
        address buyTokenId;
    }
    
    ///@notice structure contains full state related to long term orders
    struct LongTermOrders {
        ///@notice minimum block interval between order expiries 
        uint256 orderBlockInterval;

        ///@notice last virtual orders were executed immediately before this block
        uint256 lastVirtualOrderBlock;

        ///@notice token pair being traded in Uniswap V3
        address token0;
        address token1;

        ///@notice mapping from token address to pool that is selling that token 
        ///we maintain two order pools, one for each token that is tradable in the AMM
        mapping(address => OrderPoolLib.OrderPool) OrderPoolMap;

        ///@notice incrementing counter for order ids
        uint256 orderId;

         ///@notice mapping from order ids to Orders 
        mapping(uint256 => Order) orderMap;
    }

    ///@notice initialize state
    function initialize(LongTermOrders storage self
                        , address token0
                        , address token1
                        , uint256 lastVirtualOrderBlock
                        , uint256 orderBlockInterval) internal {
        self.token0 = token0;
        self.token1 = token1;
        self.lastVirtualOrderBlock = lastVirtualOrderBlock;
        self.orderBlockInterval = orderBlockInterval;
    }

    ///@notice swap token 0 for token 1. Amount represents total amount being sold, numberOfBlockIntervals determines when order expires 
    function longTermSwapFrom0To1(LongTermOrders storage self, uint256 amount0, uint256 numberOfBlockIntervals,  mapping(address => uint256) storage reserveMap) internal returns (uint256) {
        return performLongTermSwap(self, self.tokenA, self.token1, amount0, numberOfBlockIntervals, reserveMap);
    }

    ///@notice swap token 1 for token 0. Amount represents total amount being sold, numberOfBlockIntervals determines when order expires 
    function longTermSwapFrom1To0(LongTermOrders storage self, uint256 amount1, uint256 numberOfBlockIntervals,  mapping(address => uint256) storage reserveMap) internal returns (uint256) {
        return performLongTermSwap(self, self.tokenB, self.token0, amount1, numberOfBlockIntervals, reserveMap);
    }

    ///@notice adds long term swap to order pool
    function performLongTermSwap(LongTermOrders storage self, address operator, address recipient, uint256 amount, uint256 numberOfBlockIntervals,  mapping(address => uint256) storage reserveMap) private returns (uint256) {
        //update virtual order state 
        executeVirtualOrdersUntilCurrentBlock(self, reserveMap);

        //determine the selling rate based on number of blocks to expiry and total amount 
        uint256 currentBlock = block.number;
        uint256 lastExpiryBlock = currentBlock - (currentBlock % self.orderBlockInterval);
        uint256 orderExpiry = self.orderBlockInterval * (numberOfBlockIntervals + 1) + lastExpiryBlock;
        uint256 sellingRate = amount / (orderExpiry - currentBlock);

        //add order to correct pool
        OrderPoolLib.OrderPool storage OrderPool = self.OrderPoolMap[from];
        OrderPool.depositOrder(self.orderId, sellingRate, orderExpiry);

        //add to order map
        self.orderMap[self.orderId] = Order(self.orderId, orderExpiry, sellingRate, msg.sender, from, to);

        // transfer sale amount to contract
        ERC20(from).safeTransferFrom(msg.sender, address(this), amount);

        return self.orderId++;
    }

    ///@notice cancel long term swap, pay out unsold tokens and well as purchased tokens 
    function cancelLongTermSwap(LongTermOrders storage self, uint256 orderId,  mapping(address => uint256) storage reserveMap) internal {
        //update virtual order state 
        executeVirtualOrdersUntilCurrentBlock(self, reserveMap);

        Order storage order = self.orderMap[orderId];
        require(order.owner == msg.sender, 'sender must be order owner');

        OrderPoolLib.OrderPool storage OrderPool = self.OrderPoolMap[order.sellTokenId];
        (uint256 unsoldAmount, uint256 purchasedAmount) = OrderPool.cancelOrder(orderId);

        require(unsoldAmount > 0 || purchasedAmount > 0, 'no proceeds to withdraw');
        //transfer to owner
        ERC20(order.buyTokenId).safeTransfer(msg.sender, purchasedAmount);
        ERC20(order.sellTokenId).safeTransfer(msg.sender, unsoldAmount);
    }

    ///@notice withdraw proceeds from a long term swap (can be expired or ongoing) 
    function withdrawProceedsFromLongTermSwap(LongTermOrders storage self, uint256 orderId,  mapping(address => uint256) storage reserveMap) internal {
         //update virtual order state 
        executeVirtualOrdersUntilCurrentBlock(self, reserveMap);

        Order storage order = self.orderMap[orderId];
        require(order.owner == msg.sender, 'sender must be order owner');

        OrderPoolLib.OrderPool storage OrderPool = self.OrderPoolMap[order.sellTokenId];
        uint256 proceeds = OrderPool.withdrawProceeds(orderId);

        require(proceeds > 0, 'no proceeds to withdraw');
        //transfer to owner
        ERC20(order.buyTokenId).safeTransfer(msg.sender, proceeds);
    }


    ///@notice executes all virtual orders between current lastVirtualOrderBlock and blockNumber
    //also handles orders that expire at end of final block. This assumes that no orders expire inside the given interval 
    function executeVirtualTradesAndOrderExpiries(LongTermOrders storage self, mapping(address => uint256) storage reserveMap, uint256 blockNumber) private {
        
        //amount sold from virtual trades
        uint256 blockNumberIncrement = blockNumber - self.lastVirtualOrderBlock;
        uint256 tokenASellAmount = self.OrderPoolMap[self.tokenA].currentSalesRate * blockNumberIncrement;
        uint256 tokenBSellAmount = self.OrderPoolMap[self.tokenB].currentSalesRate * blockNumberIncrement;

        //initial amm balance 
        uint256 tokenAStart = reserveMap[self.token0];
        uint256 tokenBStart = reserveMap[self.token1];
        
        //updated balances from sales 
        (uint256 token0Out, uint256 token1Out, uint256 ammEndToken0, uint256 ammEndToken1) = 
            computeVirtualBalances(token0Start, token1Start, token0SellAmount, token1SellAmount);
        
        //update balances reserves
        reserveMap[self.tokenA] = ammEndToken0;
        reserveMap[self.tokenB] = ammEndToken1;
        
        //distribute proceeds to pools 
        OrderPoolLib.OrderPool storage OrderPool0 = self.OrderPoolMap[self.token0];
        OrderPoolLib.OrderPool storage OrderPool1 = self.OrderPoolMap[self.token1];

        OrderPool0.distributePayment(token1Out);
        OrderPool1.distributePayment(token0Out);

        //handle orders expiring at end of interval 
        OrderPool0.updateStateFromBlockExpiry(blockNumber);
        OrderPool1.updateStateFromBlockExpiry(blockNumber);

        //update last virtual trade block 
        self.lastVirtualOrderBlock = blockNumber;
    }

    ///@notice executes all virtual orders until current block is reached. 
    function executeVirtualOrdersUntilCurrentBlock(LongTermOrders storage self, mapping(address => uint256) storage reserveMap) internal {
        uint256 nextExpiryBlock = self.lastVirtualOrderBlock - (self.lastVirtualOrderBlock % self.orderBlockInterval) + self.orderBlockInterval;
        //iterate through blocks eligible for order expiries, moving state forward
        while(nextExpiryBlock < block.number) {
            executeVirtualTradesAndOrderExpiries(self, reserveMap, nextExpiryBlock);
            nextExpiryBlock += self.orderBlockInterval;
        }
        //finally, move state to current block if necessary 
        if(self.lastVirtualOrderBlock != block.number) {
            executeVirtualTradesAndOrderExpiries(self, reserveMap, block.number);
        }
    }

    ///@notice computes the result of virtual trades by the token pools
    function computeVirtualBalances(
          uint256 token0Start
        , uint256 token1Start
        , uint256 token0In
        , uint256 token1In) private pure returns (uint256 token0Out, uint256 token1Out, uint256 ammEndToken0, uint256 ammEndToken1)
    {
        //if no tokens are sold to the pool, we don't need to execute any orders
        if(token0In == 0 && token1In == 0) {
            token0Out = 0;
            token1Out = 0;
            ammEndToken0 = token0Start;
            ammEndToken1 = token1Start;
        }
        //in the case where only one pool is selling, we just perform a normal swap 
        else if (token0In == 0) {
            //constant product formula
            token0Out =  token0Start * token1In / (token1Start + token1In);
            token1Out = 0;
            ammEndToken0 = token0Start - token0Out;
            ammEndToken1 = token1Start + token1In;
            
        }
        else if (token1In == 0) {
            token0Out = 0;
            //contant product formula
            token1Out =  token1Start * token0In / (token0Start + token0In);
            ammEndToken0 = token0Start + token0In;
            ammEndToken1 = token1Start - token1Out;
        }
        //when both pools sell, we use the TWAMM formula
        else {
            
            //signed, fixed point arithmetic 
            int256 0In = int256(token0In).fromInt();
            int256 1In = int256(token1In).fromInt();
            int256 0Start = int256(tokenAStart).fromInt();
            int256 1Start = int256(tokenBStart).fromInt();
            int256 k = 0Start.mul(1Start);

            int256 c = computeC(0Start, 1Start, 0In, 1In);
            int256 end0 = computeAmmEndTokenA(aIn, bIn, c, k, 0Start, 1Start);
            int256 end1 = 0Start.div(end0).mul(1Start);

            int256 out0 = 0Start + 0In - end0;
            int256 out1 = 1Start + 1In - end1;

            return (uint256(out0.toInt()), uint256(out1.toInt()), uint256(end0.toInt()), uint256(end.toInt()));

        }
        
    }

    //helper function for TWAMM formula computation, helps avoid stack depth errors
    function computeC(int256 token0Start, int256 token1Start, int256 token0In, int256 token1In) private pure returns (int256 c) {
        int256 c1 = token0Start.sqrt().mul(token1In.sqrt());
        int256 c2 = token1Start.sqrt().mul(token0In.sqrt());
        int256 cNumerator = c1 - c2;
        int256 cDenominator = c1 + c2;
        c = cNumerator.div(cDenominator);
    }

    //helper function for TWAMM formula computation, helps avoid stack depth errors
    function computeAmmEndToken0(int256 token0In, int256 token1In, int256 c, int256 k, int256 aStart, int256 bStart) private pure returns (int256 ammEndToken0) {
        //rearranged for numerical stability
        int256 eNumerator = PRBMathSD59x18.fromInt(4).mul(tokenAIn).mul(tokenBIn).sqrt();
        int256 eDenominator = aStart.sqrt().mul(bStart.sqrt()).inv();
        int256 exponent = eNumerator.mul(eDenominator).exp();
        int256 fraction = (exponent + c).div(exponent - c);
        int256 scaling = k.div(tokenBIn).sqrt().mul(tokenAIn.sqrt());
        ammEndTokenA = fraction.mul(scaling);
    }
  
}