# Toe Pwar landing page (toepwar.com)

A single static page: plain HTML, CSS and a little JavaScript, with no build step. Its job is to send people to the web app at **https://app.toepwar.com**.

The design is `docs/landing/toepwar-landing.design.html`; `docs/landing/HANDOFF.md` describes it. This folder is a plain-HTML version of that design, with the same markup and styles.

| File | What it is |
|---|---|
| `index.html` | The page. All text is in English in the HTML, so the page reads fine without JavaScript. |
| `styles.css` | The design's styles, plus the language-dependent line heights and the language-switch colours. |
| `i18n.js` | Every string in English and Myanmar (`TP_COPY`), taken from the design's copy table. |
| `main.js` | The language switch, prices, contact links and the Android download. |
| `favicon.svg`, `apple-touch-icon.png` | The app icon (`frontend/assets/icon/`). |

## What comes from the backend

The backend address is the `tp-api-base` meta tag in `index.html`. Both endpoints are public, with no login.

- **`GET /api/plan/public`** returns the Plus and Pro prices and the owner contact details, as set on the admin **Plans** page.
  - **Prices:** a plan with no monthly price shows no price. "Save N%" uses the same rule as the app.
  - **Contact icons:** only the details that are set are shown, and the whole Contact column is hidden when none are.
- **`GET /api/app/latest-android`** returns the newest Android build from the admin **App versions** page.
  - The three "Download for Android" links appear only when a version exists.
  - They never appear on iPhone or iPad. This is the same rule as the app's `shouldOfferAndroidDownload`.

If the backend can't be reached, the page still works: those parts just stay hidden.

### Language

There is no reload when switching. The page starts in the language last chosen (saved in `localStorage`). On a first visit it uses Myanmar when the browser's language is Myanmar, and English otherwise.

## Changing text

Edit both languages in `i18n.js`.

If you add a new element:
- give it `data-i18n="key"` for its text;
- or `data-i18n-attr="aria-label:key"` for an attribute;
- or put `data-i18n-list="key"` on a `<ul>` whose first `<li>` contains a `[data-item]` span.

Keep the English text in `index.html` too, for visitors without JavaScript.

## Deploying (Render static site)

1. In Render, create a **Static Site** from this repository:
   - Root directory: `landing`
   - Build command: leave it empty
   - Publish directory: `.`
2. Under **Custom Domains**, add `toepwar.com` and `www.toepwar.com`, then follow Render's DNS instructions.
3. **CORS:** the backend must allow the browser to call it from `https://toepwar.com`. `CORS_ALLOWED_ORIGINS` allows every site when it is unset. If it is set on the backend service, add `https://toepwar.com` and `https://www.toepwar.com` to it.
4. Deploy the backend change that adds `GET /api/plan/public` first. Until it is live, prices and contact icons stay hidden.

To try it locally, run `python -m http.server 8080` in this folder and open http://localhost:8080.
