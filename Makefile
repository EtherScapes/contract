all:

test:
	# DEPLOY_SCENE0=1
	truffle test --network development

test-tile:
	truffle test --network development test/ESTile.js

test-pack:
	truffle test --network development test/ESTilePack.js

test-wrapper:
	truffle test --network development test/ESTileWrapper.js

deploy-test:
	DEPLOY_SCENE0=1 truffle deploy --network development
	cp build/contracts/EscapeToken.json ../www/src/contract/EscapeToken.json
	cp build/contracts/ESTile.json ../www/src/contract/ESTile.json
	cp build/contracts/ESTilePack.json ../www/src/contract/ESTilePack.json
	cp build/contracts/ESTileWrapper.json ../www/src/contract/ESTileWrapper.json
