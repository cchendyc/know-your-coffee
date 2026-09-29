# Local development. `make start` brings up the API; `make dev-web` in a second terminal.
# backend/ and web/ have their own Makefiles; these targets delegate to them.

.PHONY: start stop dev-backend dev-web dev-admin migrate

start:
	$(MAKE) -C backend start

stop:
	$(MAKE) -C backend stop
	$(MAKE) -C web stop
	$(MAKE) -C admin stop

dev-backend: start

dev-web:
	$(MAKE) -C web start

# Support console on :5174 (seller application review). Admin accounts only.
dev-admin:
	$(MAKE) -C admin start

migrate:
	$(MAKE) -C backend migrate
