# Wrapped M Token - Smart Wrapper contract

## Overview

Non-rebasing M token alternative with an additional possibility to preserve and forward yield to earners.

## Development

### Installation

You may have to install the following tools to use this repository:

- [Foundry](https://github.com/foundry-rs/foundry) to compile and test contracts
- [lcov](https://github.com/linux-test-project/lcov) to generate the code coverage report
- [slither](https://github.com/crytic/slither) to static analyze contracts

Install dependencies:

```bash
npm i
```

### Env

Copy `.env` and write down the env variables needed to run this project.

```bash
cp .env.example .env
```

### Compile

Run the following command to compile the contracts:

```bash
npm run compile
```

### Coverage

Forge is used for coverage, run it with:

```bash
npm run coverage
```

You can then consult the report by opening `coverage/index.html`:

```bash
open coverage/index.html
```

### Test

To run all tests:

```bash
npm test
```

Run test that matches a test contract:

```bash
forge test --mc <test-contract-name>
```

Test a specific test case:

```bash
forge test --mt <test-case-name>
```

To run slither:

```bash
npm run slither
```

### Code quality

[Husky](https://typicode.github.io/husky/#/) is used to run [lint-staged](https://github.com/okonet/lint-staged) and tests when committing.

[Prettier](https://prettier.io) is used to format code. Use it by running:

```bash
npm run prettier
```

[Solhint](https://protofire.github.io/solhint/) is used to lint Solidity files. Run it with:

```bash
npm run solhint
```

To fix solhint errors, run:

```bash
npm run solhint-fix
```

### CI

The following Github Actions workflow are setup to run on push and pull requests:

- [.github/workflows/coverage.yml](.github/workflows/coverage.yml)
- [.github/workflows/test-gas.yml](.github/workflows/test-gas.yml)

It will build the contracts and run the test coverage, as well as a gas report.

The coverage report will be displayed in the PR by [github-actions-report-lcov](https://github.com/zgosalvez/github-actions-report-lcov) and the gas report by [foundry-gas-diff](https://github.com/Rubilmax/foundry-gas-diff).

For the workflows to work, you will need to setup the `MNEMONIC_FOR_TESTS` and `MAINNET_RPC_URL` repository secrets in the settings of your Github repository.

Some additional workflows are available if you wish to add fuzz, integration and invariant tests:

- [.github/workflows/test-fuzz.yml](.github/workflows/test-fuzz.yml)
- [.github/workflows/test-integration.yml](.github/workflows/test-integration.yml)
- [.github/workflows/test-invariant.yml](.github/workflows/test-invariant.yml)

You will need to uncomment them to activate them.

### Documentation

The documentation can be generated by running:

```bash
npm run doc
```

It will run a server on port 4000, you can then access the documentation by opening [http://localhost:4000](http://localhost:4000).

## Deployment

### Build

To compile the contracts for production, run:

```bash
npm run build
```

### Deploy

#### Local

Open a new terminal window and run [anvil](https://book.getfoundry.sh/reference/anvil/) to start a local chain:

```bash
anvil
```

Deploy the contracts by running:

```bash
npm run deploy-local
```

#### Sepolia

To deploy to the Sepolia testnet, run:

```bash
npm run deploy-sepolia
```
