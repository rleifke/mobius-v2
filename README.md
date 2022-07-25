# Mobius V2 [![Github Actions][gha-badge]][gha] [![Foundry][foundry-badge]][foundry] [![License: MIT][license-badge]][license]

A Time Weighted Automated Market Maker (TWAMM) implementation for Uniswap V3 on Celo. Allowing users on Celo to split their large orders over several blocks. 


### Useful links:

https://www.paradigm.xyz/2021/07/twamm/ 



## Implementation Notes

### Overview 

`TWAMM.sol` directly implements most of the standard AMM functionality (liquidity provision, liquidity removal, and swapping). The logic for execution of long term orders is split across two libraries, `OrderPool.sol` and `LongTermOrders.sol`. 

### Order Pool 

The main abstraction for implementing long term orders is the `Order Pool`. The order pool represents a set of long term orders, which sell a given token to the embedded AMM at a constant rate. The token pool also handles the logic for the distribution of sales proceeds to the owners of the long term orders. 

The distribution of rewards is done through a modified version of algorithm from [Scalable Reward Distribution on the Ethereum Blockchain](https://uploads-ssl.webflow.com/5ad71ffeb79acc67c8bcdaba/5ad8d1193a40977462982470_scalable-reward-distribution-paper.pdf). Since order expiries are decopuled from reward distribution in the TWAMM model, the modified algorithm needs to keep track of additional parameters to compute rewards correctly. 

### Long term orders

In addition to the order pools, the `LongTermOrders` struct keep the state of the virtual order execution. Most importantly, it keep track of the last block where virtual orders were executed. Before every interaction with the embedded AMM, the state of virtual order execution is brought forward to the present block. We can do this efficiently because only certain blocks are eligible for virtual order expiry. Thus, we can advance the state by a full block interval in a single computation. Crucially, advancing the state of long term order execution is linear only in the number of block intervals since the last interaction with TWAMM, not linear in the number of orders. 

### Fixed Point Math

This implementation uses the [PRBMath Library](https://github.com/hifi-finance/prb-math) for fixed point arithmetic, in order to implement the closed form solution to settling long term trades. Efforts were made to make the computation numerically stable, but there's remaining work to be done here in order to ensure that the computation is correct for the full set of expected inputs. 

## Usage

Here's a list of the most frequently needed commands.

### Build

Build the contracts:

```sh
$ forge build
```

### Clean

Delete the build artifacts and cache directories:

```sh
$ forge clean
```

### Compile

Compile the contracts:

```sh
$ forge build
```

### Deploy

Deploy to Anvil:

```sh
$ forge script script/Foo.s.sol:FooScript --fork-url http://localhost:8545 \
 --broadcast --private-key $PRIVATE_KEY
```

For instructions on how to deploy to a testnet or mainnet, check out the [Solidity Scripting tutorial](https://book.getfoundry.sh/tutorials/solidity-scripting.html).

### Format

Format the contracts with Prettier:

```sh
$ yarn prettier
```

### Gas Usage

Get a gas report:

```sh
$ forge test --gas-report
```

### Lint

Lint the contracts:

```sh
$ yarn lint
```

### Test

Run the tests:

```sh
$ forge test
```

## Notes

1. Foundry piggybacks off [git submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules) to manage dependencies. There's a [guide](https://book.getfoundry.sh/projects/dependencies.html) about how to work with dependencies in the book.
2. You don't have to create a `.env` file, but filling in the environment variables may be useful when debugging and testing against a mainnet fork.

## Related Efforts

- [abigger87/femplate](https://github.com/abigger87/femplate)
- [cleanunicorn/ethereum-smartcontract-template](https://github.com/cleanunicorn/ethereum-smartcontract-template)
- [foundry-rs/forge-template](https://github.com/foundry-rs/forge-template)
- [FrankieIsLost/forge-template](https://github.com/FrankieIsLost/forge-template)

## License

[MIT](./LICENSE.md) © Paul Razvan Berg
