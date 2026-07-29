# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

profile ?=default

# dapp deps
update:; forge update

# Deployment helpers
deploy:
	FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --skip src --skip test --rpc-url ${DEPLOY_RPC_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} --slow --broadcast -vvv --verify

deploy-local:
	FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --skip src --skip test --rpc-url localhost --slow --broadcast -vvv

# Deploys the implementation + migrator only, leaving migrate() to be called by hand.
# Sepolia-only: it is the rehearsal chain and its migration admin is an EOA, so there
# is no Safe to propose to. The mainnets all use propose-upgrade below.
deploy-upgrade:
	FOUNDRY_PROFILE=production forge script script/DeployUpgrade.s.sol --skip src --skip test \
		--rpc-url $(RPC_URL) --slow --broadcast -vvv \
		--verify --verifier $(VERIFIER) --verifier-url $(VERIFIER_URL)

# Deploys the implementation + migrator AND proposes migrate() to the migration-admin
# Safe (via the Safe Transaction Service). Used for every mainnet wM v2 upgrades on
# (mainnet/base/arbitrum) — all have a Safe as their migration admin. `--ffi` lets
# safe-utils post the proposal.
# NOTE: running this posts a REAL Safe proposal; PRIVATE_KEY must be a Safe proposer.
propose-upgrade:
	FOUNDRY_PROFILE=production forge script script/ProposeUpgrade.s.sol --skip src --skip test \
		--rpc-url $(RPC_URL) --slow --broadcast --ffi --non-interactive -vvv \
		--verify --verifier $(VERIFIER) --verifier-url $(VERIFIER_URL)

# Usage: $(call alchemy,<slug>).
alchemy = https://$(1).g.alchemy.com/v2/$(ALCHEMY_API_KEY)

propose-upgrade-mainnet: RPC_URL=$(call alchemy,eth-mainnet)
propose-upgrade-mainnet: VERIFIER=etherscan
propose-upgrade-mainnet: VERIFIER_URL=$(MAINNET_VERIFIER_URL)
propose-upgrade-mainnet: propose-upgrade

propose-upgrade-base: RPC_URL=$(call alchemy,base-mainnet)
propose-upgrade-base: VERIFIER=etherscan
propose-upgrade-base: VERIFIER_URL=$(BASE_VERIFIER_URL)
propose-upgrade-base: propose-upgrade

propose-upgrade-arbitrum: RPC_URL=$(call alchemy,arb-mainnet)
propose-upgrade-arbitrum: VERIFIER=etherscan
propose-upgrade-arbitrum: VERIFIER_URL=$(ARBITRUM_VERIFIER_URL)
propose-upgrade-arbitrum: propose-upgrade

deploy-upgrade-sepolia: RPC_URL=$(call alchemy,eth-sepolia)
deploy-upgrade-sepolia: VERIFIER=etherscan
deploy-upgrade-sepolia: VERIFIER_URL=$(SEPOLIA_VERIFIER_URL)
deploy-upgrade-sepolia: deploy-upgrade

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
