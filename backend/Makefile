# Run from backend/. `make start` brings up the API on :4000.

.PHONY: start stop migrate

VENV := .venv
UVICORN := $(VENV)/bin/uvicorn
PORT ?= 4000

# Creates the venv and installs deps on first run.
$(UVICORN): requirements.txt
	python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
	touch $(UVICORN)

# API on :4000 with reload (also on schema.graphql). Frees the port first so a
# stale server from an earlier session cannot block the bind.
start: $(UVICORN) stop
	.venv/bin/uvicorn app.main:app --port $(PORT) --reload --reload-include '*.graphql'

# Kill whatever is listening on the API port. No-op when nothing is.
stop:
	@lsof -tiTCP:$(PORT) -sTCP:LISTEN | xargs kill 2>/dev/null || true

# Apply pending Alembic migrations to DATABASE_URL from .env.
migrate: $(UVICORN)
	.venv/bin/alembic upgrade head
