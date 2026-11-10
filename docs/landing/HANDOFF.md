# Toe Pwar landing page: handoff

Design for the marketing page at **toepwar.com**. Build it as a **single static page** (HTML + CSS + a little vanilla JS, no framework or backend needed). Its main job is to send people to the web app at **https://app.toepwar.com**.

## Files

- `toepwar-landing.design.html` is the finished design, exported from a Claude Design canvas. **Use it as the visual and content source of truth.** It is not directly deployable: it uses a small templating runtime from the design tool. Convert it to plain HTML:
  - `<x-dc>` … `</x-dc>` is the page markup. `<helmet>` holds the `<head>` extras (Google Fonts link + the `<style>` block). Move these into a normal `<head>`.
  - `{{t.someKey}}` placeholders are filled from the `copy(lang)` method in the `<script type="text/x-dc">` block at the bottom. It holds **every string in English and Myanmar**. Keep that table as the source for the i18n strings.
  - Other `{{…}}` holes (`lhBody`, `lhHead`, `h1Size`, `enBg`, `plus.main`, etc.) are computed in `renderVals()` from the current language and the price settings. Replicate that logic in plain JS or CSS.
  - `<sc-for list="{{t.freeItems}}" as="item">` repeats its child for each array item. `<sc-if value="{{x}}">` renders its child only if `x` is truthy.
  - `onClick="{{setEn}}"` / `{{setMy}}` are the language-switch handlers.
  - `data-props` on the script tag lists the design's settings and defaults: `startLang` (`en`), `apkUrl`, and `plusMonthly`/`plusYearly`/`proMonthly`/`proYearly` (MMK, `0` = not set → shows `[price]`).
  - Remove `<script src="./support.js">` (design-tool runtime).

## Page structure

1. Sticky header: logo (inline SVG, same artwork as `frontend/assets/icon/toepwar.svg`) + "Toe Pwar"/"တိုးပွား", nav (Features, How it works, Plans; a second swipeable row below 1000px), English | မြန်မာ switch, "Go to app" button.
2. Hero: headline, sentence, "Go to app" + "Download for Android", note line, and a tilted phone mockup of the app's Home screen with two floating AI chips.
3. Features (`#features`): a jade "Powered by AI" panel with 6 AI cards, each with a small animated demo (voice, receipt scan, AI chat, AI budget suggestions, AI insights, custom insight reports [Pro]), then 3 white "everyday basics" cards.
4. How it works (`#how`): 3 numbered steps.
5. Plans (`#plans`): Free / Plus / Pro cards with prices and what each unlocks, "Start free" button.
6. Final call to action band.
7. Footer: brand, contact icon buttons, app links, copyright.

## Behaviour to keep

- **Language switch** swaps the whole page between `en` and `my` with no reload. Set `lang` on the root, `aria-pressed` on the two buttons. Myanmar text gets larger line-heights and no negative letter-spacing (see `renderVals()`). Consider remembering the choice in `localStorage` and defaulting from `navigator.language`.
- **Fonts:** Manrope + Noto Sans Myanmar (Google Fonts), one font stack for both.
- **All "Go to app" / "Start free" links** go to `https://app.toepwar.com`.
- **Download for Android:** the URL comes from the backend: `GET {API}/api/app/latest-android` → `{ version, download_url }` (see `frontend/lib/services/api_service.dart`). Fetch it at runtime and hide the Android buttons/link on iPhone/iPad and when there's no version, using the same rule as `shouldOfferAndroidDownload` in `frontend/lib/widgets/android_download_link.dart`. Check that endpoint allows CORS from toepwar.com.
- **Prices:** `GET /api/plan` needs auth, so the static page can't read them. Either hard-code them (keep in sync with the admin panel) or add a small public endpoint for plan prices. Formatting must match the app (`formatPlanPrice` and the save-% rule in `frontend/lib/screens/subscription/subscription_screen.dart` / `PlanPrice.savePercent`).
- **Contact icons:** links are placeholders (`#contact-…`). Fill from the owner contact on the admin Plans page (email, Viber, Telegram, Facebook, Messenger; see `frontend/lib/utils/contact_details.dart` for the URL formats). Icons are generic; official brand icons can be swapped in.
- **Animations** (all inside `@media (prefers-reduced-motion: no-preference)`): hero fade-up on load, mockup bars grow, phone and chips float, AI demo loops, scroll-reveal via `animation-timeline: view()` (progressive enhancement), hover lifts. Keep the reduced-motion guard.
- **Accessibility:** real `<a>`/`<button>`, visible `:focus-visible` outlines, `aria-label` on icon-only links, decorative SVG/demos `aria-hidden`, mockups as `role="img"` with a translated `aria-label`.

## Brand tokens (from `frontend/lib/theme/app_theme.dart`)

| Token | Value |
|---|---|
| Jade (primary) | `#0B6B54` (hover `#095A47`) |
| Jade containers | `#B9E9D8`, `#A2E0CB`, `#8FD5BE`; secondary container `#DCEFE8` |
| On jade container | `#05261E`, label `#134539` |
| Page / surface / card | `#E7EDEA` / `#F6FAF8` / `#FFFFFF` |
| Ink / muted / muted 2 | `#101815` / `#3F4A45` / `#5A655F` |
| Outline / divider | `#C6D0CB` / `#EEF2F0` |
| Gold accent | `#6E5411` on `#FBF3DE` (Plus/Pro, insights) |
| Danger | `#B3261E` on `#FBE3E0` |
| Chart ramp | `#0B6B54 #2F8E75 #66B79F #A2D8C7 #D6EDE5` |

Radii: buttons 20, cards 20–24, hero card 24, chips 8–14.

## Content rules

No testimonials, user counts, ratings or press logos. Amounts in the mockups and demos are illustrative examples only.
