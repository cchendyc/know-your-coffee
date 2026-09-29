# Run from web/. `make start` brings up Vite on :5173, proxying /graphql to :4000.

.PHONY: start stop

PORT ?= 5173

# Installs deps on first run.
node_modules: package.json
	npm install
	touch node_modules

# Frees the port first so a stale server cannot block the bind.
start: node_modules stop
	npm run dev

# Kill whatever is listening on the Vite port. No-op when nothing is.
stop:
	@lsof -tiTCP:$(PORT) -sTCP:LISTEN | xargs kill 2>/dev/null || true
