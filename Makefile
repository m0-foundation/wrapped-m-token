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

deploy-upgrade:
	FOUNDRY_PROFILE=production forge script script/DeployUpgrade.s.sol --skip src --skip test \
		--rpc-url $(RPC_URL) --slow --broadcast -vvv \
		--verify --verifier $(VERIFIER) --verifier-url $(VERIFIER_URL)

# Usage: $(call alchemy,<slug>).
alchemy = https://$(1).g.alchemy.com/v2/$(ALCHEMY_API_KEY)

deploy-upgrade-mainnet: RPC_URL=$(call alchemy,eth-mainnet)
deploy-upgrade-mainnet: VERIFIER=etherscan
deploy-upgrade-mainnet: VERIFIER_URL=$(MAINNET_VERIFIER_URL)
deploy-upgrade-mainnet: deploy-upgrade

deploy-upgrade-bsc: RPC_URL=$(call alchemy,bnb-mainnet)
deploy-upgrade-bsc: VERIFIER=etherscan
deploy-upgrade-bsc: VERIFIER_URL=$(BSC_VERIFIER_URL)
deploy-upgrade-bsc: deploy-upgrade

deploy-upgrade-monad: RPC_URL=$(call alchemy,monad-mainnet)
deploy-upgrade-monad: VERIFIER=etherscan
deploy-upgrade-monad: VERIFIER_URL=$(MONAD_VERIFIER_URL)
deploy-upgrade-monad: deploy-upgrade

deploy-upgrade-hyperevm: RPC_URL=$(call alchemy,hyperliquid-mainnet)
deploy-upgrade-hyperevm: VERIFIER=etherscan
deploy-upgrade-hyperevm: VERIFIER_URL=$(HYPEREVM_VERIFIER_URL)
deploy-upgrade-hyperevm: deploy-upgrade

deploy-upgrade-base: RPC_URL=$(call alchemy,base-mainnet)
deploy-upgrade-base: VERIFIER=etherscan
deploy-upgrade-base: VERIFIER_URL=$(BASE_VERIFIER_URL)
deploy-upgrade-base: deploy-upgrade

deploy-upgrade-plasma: RPC_URL=$(call alchemy,plasma-mainnet)
deploy-upgrade-plasma: VERIFIER=etherscan
deploy-upgrade-plasma: VERIFIER_URL=$(PLASMA_VERIFIER_URL)
deploy-upgrade-plasma: deploy-upgrade

deploy-upgrade-arbitrum: RPC_URL=$(call alchemy,arb-mainnet)
deploy-upgrade-arbitrum: VERIFIER=etherscan
deploy-upgrade-arbitrum: VERIFIER_URL=$(ARBITRUM_VERIFIER_URL)
deploy-upgrade-arbitrum: deploy-upgrade

deploy-upgrade-linea: RPC_URL=$(call alchemy,linea-mainnet)
deploy-upgrade-linea: VERIFIER=etherscan
deploy-upgrade-linea: VERIFIER_URL=$(LINEA_VERIFIER_URL)
deploy-upgrade-linea: deploy-upgrade

deploy-upgrade-sepolia: RPC_URL=$(call alchemy,eth-sepolia)
deploy-upgrade-sepolia: VERIFIER=etherscan
deploy-upgrade-sepolia: VERIFIER_URL=$(SEPOLIA_VERIFIER_URL)
deploy-upgrade-sepolia: deploy-upgrade

deploy-upgrade-soneium: RPC_URL=$(call alchemy,soneium-mainnet)
deploy-upgrade-soneium: VERIFIER=blockscout
deploy-upgrade-soneium: VERIFIER_URL=$(SONEIUM_VERIFIER_URL)
deploy-upgrade-soneium: deploy-upgrade

deploy-upgrade-rise: RPC_URL=$(call alchemy,rise-mainnet)
deploy-upgrade-rise: VERIFIER=blockscout
deploy-upgrade-rise: VERIFIER_URL=$(RISE_VERIFIER_URL)
deploy-upgrade-rise: deploy-upgrade

deploy-upgrade-moca: RPC_URL=$(MOCA_RPC_URL)
deploy-upgrade-moca: VERIFIER=blockscout
deploy-upgrade-moca: VERIFIER_URL=$(MOCA_VERIFIER_URL)
deploy-upgrade-moca: deploy-upgrade

deploy-upgrade-citrea: RPC_URL=$(CITREA_RPC_URL)
deploy-upgrade-citrea: VERIFIER=blockscout
deploy-upgrade-citrea: VERIFIER_URL=$(CITREA_VERIFIER_URL)
deploy-upgrade-citrea: deploy-upgrade

deploy-upgrade-mantra: RPC_URL=$(MANTRA_RPC_URL)
deploy-upgrade-mantra: VERIFIER=blockscout
deploy-upgrade-mantra: VERIFIER_URL=$(MANTRA_VERIFIER_URL)
deploy-upgrade-mantra: deploy-upgrade

deploy-upgrade-fluent: RPC_URL=$(FLUENT_RPC_URL)
deploy-upgrade-fluent: VERIFIER=blockscout
deploy-upgrade-fluent: VERIFIER_URL=$(FLUENT_VERIFIER_URL)
deploy-upgrade-fluent: deploy-upgrade

deploy-upgrade-plume: RPC_URL=$(PLUME_RPC_URL)
deploy-upgrade-plume: VERIFIER=blockscout
deploy-upgrade-plume: VERIFIER_URL=$(PLUME_VERIFIER_URL)
deploy-upgrade-plume: deploy-upgrade

deploy-upgrade-0g: RPC_URL=$(ZEROG_RPC_URL)
deploy-upgrade-0g: VERIFIER=custom
deploy-upgrade-0g: VERIFIER_URL=$(ZEROG_VERIFIER_URL)
deploy-upgrade-0g: deploy-upgrade

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
