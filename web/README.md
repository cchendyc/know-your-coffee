# Know Your Coffee — Web

Search, check, and report what Bay Area coffee shops run: espresso machine, grinder, beans and roaster, milk brands, and menu prices. Save shops, track where you've been, and share photos of the setup.

React + Vite + Tailwind + Leaflet. The GraphQL API lives in [`../backend`](../backend/README.md).

**Features**

- Map + paginated list of real Bay Area shops, with distinct markers for saved and been-to shops
- Community reports (sign-in required): machine (photo-recognized via Gemini), grinder, bean source and origins, roaster, milk brands, drinks with prices (parsed from a menu photo)
- Google sign-in with profile menu, saved list ("Saved") and visited list ("Been")
- Photo galleries per shop, grouped by section: machine, beans, drinks, menu, vibe
- Links to Google Maps and each shop's own website

## Run locally

```sh
npm install
npm run dev        # http://localhost:5173
```

The dev server proxies `/graphql` to `http://localhost:4000` — run the API alongside. For Google sign-in, copy `.env.example` to `.env.local` and set `VITE_GOOGLE_CLIENT_ID`.

## Deploy (GitHub Pages)

`.github/workflows/deploy-web.yml` (repo root) builds and publishes on every push that touches `web/`. One-time setup:

1. Settings → Pages → Source: **GitHub Actions**.
2. Settings → Secrets and variables → Actions → **Variables**, add:
   - `VITE_API_URL` = `https://<your-render-service>.onrender.com/graphql`
   - `VITE_GOOGLE_CLIENT_ID` = your Google OAuth client ID
3. **Google OAuth** ([console.cloud.google.com](https://console.cloud.google.com/apis/credentials)): add `https://<you>.github.io` to *Authorized JavaScript origins*.

The site publishes to `https://<you>.github.io/<repo>/`.
