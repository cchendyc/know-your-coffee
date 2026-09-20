# Know Your Coffee — API

GraphQL API: what Bay Area coffee shops run — espresso machine, grinder, beans, roaster, milk brands, menu prices. Python + Ariadne (schema-first), Neon Postgres, Alembic migrations.

The web client lives in [`../web`](../web/README.md).

## Layout

| Path | Contents |
| --- | --- |
| `schema.graphql` | The GraphQL schema (source of truth). |
| `app/models.py` | Domain models. |
| `app/repository/` | Data access: Postgres (Neon) or in-memory fallback. |
| `app/resolvers/queries.py` | Query resolvers. |
| `app/resolvers/mutations.py` | Mutation resolvers. |
| `app/services/` | Google Places, Yelp, Gemini vision. |
| `app/auth.py` | Google sign-in verification, HMAC session tokens. |
| `migrations/versions/` | Alembic migrations. |
| `scripts/` | Import, enrich, dedup, backfill CLIs. |

## Run locally

```sh
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
cp .env.example .env        # fill in DATABASE_URL + keys
.venv/bin/uvicorn app.main:app --port 4000 --reload
```

GraphQL explorer at http://localhost:4000/graphql. Without `DATABASE_URL` the API uses a non-persistent in-memory store.

## Database (Neon + Alembic)

1. Create a project at [neon.tech](https://neon.tech) (free tier is enough).
2. Copy the **pooled** connection string (Dashboard → Connect) into `.env` as `DATABASE_URL`.
3. Apply migrations, then import real shops:

```sh
.venv/bin/alembic upgrade head
.venv/bin/python -m scripts.import_shops "San Francisco, CA" "Oakland, CA"
.venv/bin/python -m scripts.enrich       # machine/roaster/milk from public reviews
.venv/bin/python -m scripts.backfill     # shop photos + websites from Google Places
.venv/bin/python -m scripts.dedup        # merge duplicates across Yelp/Google
```

New migration: `.venv/bin/alembic revision -m "describe change"`, edit the file in `migrations/versions/`, then `alembic upgrade head`.

## Secrets (`.env`, see `.env.example`)

| Key | Enables |
| --- | --- |
| `DATABASE_URL` | Neon Postgres persistence and migrations. |
| `GOOGLE_OAUTH_CLIENT_ID` | Google sign-in (same client ID as the web repo's `VITE_GOOGLE_CLIENT_ID`). |
| `SESSION_SECRET` | Keeps sessions valid across restarts. Any long random string. |
| `YELP_API_KEY` | Yelp source for `scripts.import_shops`. |
| `GOOGLE_PLACES_API_KEY` | Google Places import, photo/website backfill, adding shops. |
| `GEMINI_API_KEY` | Machine photo recognition and menu parsing. Free tier: https://aistudio.google.com/apikey |

## Deploy (Render, free)

1. Render → New → Blueprint → point it at this repo (`render.yaml` at the repo root; `rootDir: backend`).
2. Fill in the env vars it prompts for.
3. Apply migrations from your machine (`alembic upgrade head` with the production `DATABASE_URL`).
4. Note the service URL — the web deploy needs it as `VITE_API_URL` (`https://<service>.onrender.com/graphql`).

> Render's free plan sleeps after idle; the first request takes ~30s to wake.
