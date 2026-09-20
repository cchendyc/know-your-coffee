# Know Your Coffee ☕

Search, check, and report what Bay Area coffee shops run: espresso machine, grinder, beans and roaster, milk brands, and menu prices. Save shops, track where you've been, and share photos of the setup.

- `backend/` — GraphQL API. Python + Ariadne (schema-first), Neon Postgres, Alembic migrations. Deploys to Render via `render.yaml`.
- `web/` — React + Vite + Tailwind + Leaflet SPA. Deploys to GitHub Pages via `.github/workflows/deploy-web.yml`.

Setup, secrets, and deploy steps live in each folder's README: [backend](backend/README.md), [web](web/README.md).

## Run locally

```sh
# API — http://localhost:4000/graphql
cd backend
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/uvicorn app.main:app --port 4000 --reload

# Web — http://localhost:5173 (proxies /graphql to the API)
cd web
npm install && npm run dev
```
