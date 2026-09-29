# Run from admin/. `make start` brings up the support console on :5174,
# proxying /graphql to :4000.

.PHONY: start stop

PORT ?= 5174

# Installs deps on first run.
node_modules: package.json
	npm install
	touch node_modules

# Frees the port first so a stale server cannot block the bind.
start: node_modules stop
	npm run dev

# Kill whatever is listening on the console port. No-op when nothing is.
stop:
	@lsof -tiTCP:$(PORT) -sTCP:LISTEN | xargs kill 2>/dev/null || true
