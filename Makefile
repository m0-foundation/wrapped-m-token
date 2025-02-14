# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

profile ?=default

# dapp deps
update:; forge update

# Deployment helpers
deploy:
	FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --skip src --skip test --rpc-url ${DEPLOY_RPC_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --slow --broadcast -vvv --verify --show-standard-json-input

deploy-local:
	FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --skip src --skip test --rpc-url localhost --slow --broadcast -vvv

deploy-upgrade:
	FOUNDRY_PROFILE=production forge script script/DeployUpgradeMainnet.s.sol --skip src --skip test --rpc-url mainnet --slow --broadcast -vvv --verify --show-standard-json-input

# Run slither
slither :
	FOUNDRY_PROFILE=production forge build --build-info --skip '*/test/**' --skip '*/script/**' --force && slither --compile-force-framework foundry --ignore-compile --sarif results.sarif --config-file slither.config.json .

# Common tasks
build:
	./build.sh -p production

tests:
	MAINNET_RPC_URL=$(MAINNET_RPC_URL) ./test.sh -p $(profile)

fuzz:
	MAINNET_RPC_URL=$(MAINNET_RPC_URL) ./test.sh -t testFuzz -p $(profile)

integration:
	MAINNET_RPC_URL=$(MAINNET_RPC_URL) ./test.sh -d test/integration -p $(profile)

invariant:
	MAINNET_RPC_URL=$(MAINNET_RPC_URL) ./test.sh -d test/invariant -p $(profile)

coverage:
	FOUNDRY_PROFILE=production forge coverage --fork-url $(MAINNET_RPC_URL) --report lcov && lcov --extract lcov.info --rc lcov_branch_coverage=1 --rc derive_function_end_line=0 -o lcov.info 'src/*' && genhtml lcov.info --rc branch_coverage=1 --rc derive_function_end_line=0 -o coverage

gas-report:
	FOUNDRY_PROFILE=production forge test --fork-url $(MAINNET_RPC_URL) --gas-report > gasreport.ansi

sizes:
	./build.sh -p production -s

clean:
	forge clean && rm -rf ./abi && rm -rf ./bytecode && rm -rf ./types
