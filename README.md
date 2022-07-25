# Mobius V2

A Time Weighted Automated Market Maker (TWAMM) implementation for Uniswap V3 on Celo forked from @FrankieIsLost. Allowing users on Celo to split their large orders over several blocks. 


### Useful links:

https://www.paradigm.xyz/2021/07/twamm/ 

https://github.com/FrankieIsLost/TWAMM


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
