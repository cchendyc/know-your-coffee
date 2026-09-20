# Local development. Run `make dev-backend` and `make dev-web` in two terminals.

.PHONY: dev-backend dev-web migrate

# API on :4000 with reload. Uses backend/.env (Neon DATABASE_URL or in-memory fallback).
dev-backend:
	cd backend && .venv/bin/uvicorn app.main:app --port 4000 --reload

# Vite on :5173, proxying /graphql to :4000.
dev-web:
	cd web && npm run dev

# Apply pending Alembic migrations to DATABASE_URL from backend/.env.
migrate:
	cd backend && .venv/bin/alembic upgrade head
