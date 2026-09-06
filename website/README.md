# HotPotChef marketing site (`hotpotchef.com`)

Minimal static site for plate-share links and Android App Links.

## What it does

| Path | Purpose |
|------|---------|
| `/` | Brand landing — *Home kitchens. Near you. On your slot.* |
| `/meal/{id}` | Dish preview (Supabase) + Open app / Play Store CTAs |
| `/.well-known/assetlinks.json` | Android App Links verification |
| `/.well-known/apple-app-site-association` | iOS Universal Links stub (fill Team ID when you ship iOS) |

Share URLs from the app already use `https://hotpotchef.com/meal/{id}`.

## Setup

1. Copy config and fill keys:

```bash
cp js/config.example.js js/config.js
```

Edit `js/config.js`:

- `supabaseUrl` — your project URL (e.g. `https://tpcykyaumvqtwhuiiomg.supabase.co`)
- `supabaseAnonKey` — anon / publishable key (same as the Flutter app; protected by RLS)
- `playStoreUrl` — Play listing when live (placeholder OK for now)
- `androidSha256Fingerprints` — see App Links below

2. Put your **release** signing certificate SHA-256 into:

- `js/config.js` → `androidSha256Fingerprints` (optional helper only)
- **`/.well-known/assetlinks.json`** → `sha256_cert_fingerprints` (**required** for App Links)

Get the fingerprint:

```bash
keytool -list -v -keystore path/to/upload-keystore.jks -alias upload
```

Use the SHA-256 line (colons optional; Google accepts either). If you use Play App Signing, also add the **App signing key** SHA-256 from Play Console → App integrity.

3. Deploy this `website/` folder as the site root (not the Flutter `web/` build).

### Vercel

- Root directory: `website`
- DNS: point `hotpotchef.com` (and `www` → apex) to Vercel
- `vercel.json` already rewrites `/meal/:id` → `meal.html`

### Netlify

- Publish directory: `website`
- `netlify.toml` + `_redirects` handle `/meal/*`

### Cloudflare Pages

- Build output: `website`
- Add a `_redirects` or Cloudflare redirect rule: `/meal/*` → `/meal.html` (200)

## Verify App Links

After HTTPS is live:

1. Open `https://hotpotchef.com/.well-known/assetlinks.json` — must be public JSON, `Content-Type: application/json`.
2. [Google Statement List Generator](https://developers.google.com/digital-asset-links/tools/generator) — package `com.hotpotchef.app`.
3. On a device with the release APK:  
   `adb shell pm get-app-links com.hotpotchef.app`  
   Domain should show **verified**.

## Local preview

```bash
cd website
npx --yes serve -p 5173
```

Then open `http://localhost:5173/meal.html?id=YOUR_MEAL_UUID` (path rewrite needs the host; locally use the query form or `serve` with a simple proxy).

## Notes

- Do not commit real keys in `js/config.js` if your repo is public — `config.js` is gitignored; commit only `config.example.js`.
- Meal rows must be readable by the anon key under RLS (same as the diner app feed).
- Flutter’s `web/` folder is the Flutter web build — keep it separate from this marketing site.
