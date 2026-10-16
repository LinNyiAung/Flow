# Flow web version: design

Date: 2026-10-16 · Status: draft for approval

(The project and backend are called Flow; users see the app as **Toe Pwar**.)

## Why

Flow (Toe Pwar) is a Flutter app distributed only as an Android APK, downloaded directly from a link
(not the Play Store). The owner can't build for iPhone/iPad or computers, so those people
can't use Flow at all today. A web version, the same app running in a browser, lets
anyone use it. The website is also where Android users find the APK download link.

## What it is

- The **existing Flutter app** (`frontend/`), built for the web from the **same code**.
  No second codebase, no separate homepage or marketing page.
- The website opens on the **same login screen** as the phone app. Once signed in, users
  get the same screens and features, with the same account and data as on their phone
  (same backend API).
- **Who uses it:** iPhone/iPad users, computer users, and Android users who prefer a
  browser.

## Goals

1. Every feature of the Android app works in a browser (Chrome, Edge, Safari, Firefox;
   desktop and phone browsers), except phone-style push notifications (see below).
2. **Layout (owner's choice, option A):** on any screen the app looks exactly like the phone
   app. On wide screens it is shown as a **centred, phone-width column** (roughly
   400–480 px wide, full height) on a plain background. No desktop-specific layouts.
3. A **"Get the Android app" link** to the latest APK.
4. Hosted at a free **Render static site** address (e.g. `flow-web.onrender.com`). There is
   no custom domain yet; one can be added later without app changes.

## Non-goals

- No browser push notifications. On the web, alerts are seen in the app's existing
  **notifications list** (owner's decision).
- No desktop-optimised layouts, no landing page, no SEO work.
- No changes to the Android app's behaviour or look.

## Anti-goals (would make this a failure even if the site works)

- Breaking or changing anything in the Android app (startup, push notifications, update
  check, file handling). All web adaptations must be web-only branches (`kIsWeb`
  or conditional imports), with the Android code paths unchanged.
- A second copy of screens or logic for the web.
- Offering the APK to iPhone/iPad users, who can't install it.

## Constraints

- Flutter (Dart SDK ^3.8.1). `frontend/web/` already exists (generated defaults: name
  "frontend", default icons and description).
- Backend: FastAPI on Render (`https://flowfinance.onrender.com`). The app's API base
  URL comes from `--dart-define=API_BASE_URL=...`; the web build must pass the production
  URL explicitly (the in-code default is a LAN development address).
- **Launch order:** the PostgreSQL backend (merged to `main` on 2026-10-16) is **not yet
  live** on Render; going live needs the Render PostgreSQL database, `DATABASE_URL`, and the
  `alembic upgrade head` pre-deploy step (see `docs/postgres-migration-plan.md`). The
  backend goes live first, including the new public endpoint below, then the website.
- The backend's CORS allows all origins by default (`CORS_ALLOWED_ORIGINS`, default `*`;
  auth is a bearer header, no cookies). That already permits the website. Restricting it
  to the site's address is allowed but optional.
- The Flutter e2e suite (`e2e/run_e2e.ps1`, 43 tests on an Android emulator) must still pass.

## What needs adapting (found by reading the code)

| # | Area | Today (phone) | On the web |
|---|------|---------------|------------|
| 1 | **Startup** (`main.dart`) | `Firebase.initializeApp()`, `FCMService().initialize()`, `NotificationService().initialize()` | Firebase has **no web config** (`firebase_options.dart` throws for web), so startup would crash. Skip Firebase/FCM/local-notification setup on the web entirely. |
| 2 | **Push notifications / permissions** | FCM token registration, local notifications, `permission_handler` notification prompts, notification settings screen reads OS permission status | Not used on the web. Notification **preferences** (which alert types the user wants) stay usable since they also govern the in-app list. Anything about OS permission or device tokens is hidden or no-op on web. Logout must not try to unregister an FCM token on the web. |
| 2b | **Things FCM refreshes on Android** (silent `subscription_updated` push refreshes premium status; incoming pushes refresh the unread badge) | Refreshed instantly by push | *(My call)* On the web, refresh the user profile (premium status) and the unread count whenever the browser tab becomes visible/focused again, plus on app start. No polling. |
| 3 | **Update check / force-update screen** (`main.dart` `_checkVersion` uses `dart:io Platform`; `force_update_screen.dart`) | Checks published versions, may block with "please update" | Skipped on the web (the website is always the latest build). `dart:io` must not be used on the web path. |
| 4 | **PDF report download** (`api_service.dart` ~line 1505 saves to `getApplicationDocumentsDirectory()`; `reports_screen.dart` opens with `OpenFilex`) | Saves to a phone folder, then opens it | Trigger a normal **browser download** of the PDF bytes (with a sensible filename); no "open file" step. Browsers can only read the server's `Content-Disposition` filename if the backend CORS exposes that header; expose it, or build the filename in the app. |
| 5 | **Voice input** (`voice_input_screen.dart`: `record` to a temp file, then uploads `File(path)`) | File on disk | Record in the browser (the `record` package supports web; the microphone permission is asked by the browser) and upload the recorded **bytes**. No `dart:io`, no `path_provider`, no `permission_handler` on web. Upload format must be one the backend's transcription accepts (check the backend endpoint and adjust the filename/content type, e.g. webm/opus). |
| 6 | **Receipt photo** (`image_input_screen.dart`: `image_picker` → `File(image.path)`) | File on disk | `image_picker` works on the web (file chooser; camera on phone browsers). Use the picked file's **bytes** for preview and upload instead of `File`. No `permission_handler` on web. |
| 7 | **App identity** (`web/index.html`, `web/manifest.json`, icons) | n/a | The user-facing name is **"Toe Pwar"** (owner's decision), as in the Android app (`MaterialApp(title: 'Toe Pwar')`, Android label). Use it for the page title, manifest `name`/`short_name`, and iOS home-screen title, with a proper description, theme colour and the app's icon (`assets/icon/flow.png`) instead of the Flutter defaults, so the browser tab, bookmarks and iPhone "Add to Home Screen" show Toe Pwar. *(My call: making the site installable to the home screen is nearly free with Flutter and gives iPhone users an app-like icon.)* |
| 8 | **Layout** | Full-screen phone UI | Wrap the app (all routes and dialogs) in a centred, phone-width frame when the browser window is wider than a phone. |

Anything else found during the build that relies on `dart:io` or a mobile-only plugin
follows the same rule: a web-only alternative, Android unchanged.

## The download link (placement is my call; owner left it open)

- **Where:**
  - a "Get the Android app" link/button under the login form;
  - the same entry in the side menu (drawer) when signed in.
- **Who sees it:**
  - shown in the **web** build only, never in the Android app itself;
  - hidden when the browser is on iPhone/iPad (iOS);
  - shown on Android phones and computers.
- **Where it points:** the `download_url` of the **newest active version** published in the
  admin panel (App Versions) for platform `android` or `all`. Publishing a new APK version
  in the admin panel therefore updates the website link automatically. If nothing is
  published, the link is hidden.
- **Backend:** the existing `POST /api/app/check-version` requires login, but the login
  screen needs the link before sign-in. Add a small **public, read-only** endpoint (e.g.
  `GET /api/app/latest-android`) returning only `{version, download_url}` of that newest
  active version (or an empty result). No other data is exposed. Cover it with a backend
  test.

## Hosting (my call)

- **Render Static Site** serving the built `build/web` folder, with a rewrite of every path
  to `index.html` so deep links and refreshes work.
- Built with `flutter build web --release --dart-define=API_BASE_URL=https://flowfinance.onrender.com`.
- Render's static sites have no Flutter preinstalled. The builder chooses between:
  - installing Flutter in the Render build command;
  - building elsewhere (e.g. a GitHub Action) and deploying the output.
  
  Either way, document the exact steps for the owner, who will do the Render dashboard
  clicks with guidance.
- No custom domain for now.

## Testing

- **Android app unchanged:** the existing Flutter e2e suite still passes (43/43).
- **Web build** *(my call: a guided browser checklist, not a new automated web suite; the
  Android suite already covers the shared screens and logic)*: `flutter build web`
  succeeds, and the site is exercised in a real browser against the local stubbed backend
  (`e2e/run_server.py`, which uses a throwaway local PostgreSQL). The checklist is written
  into the repo so it can be repeated before releases:
  - register, verify, log in;
  - add/edit/delete transactions;
  - budgets, goals and charts;
  - AI chat and insights;
  - receipt photo and voice input, at least the upload path;
  - PDF report download;
  - notifications list, settings, language and theme;
  - logout;
  - the download link appears/hides as specified.
- Spot-check a phone-width browser and a wide desktop window (centred column).
- **Backend:** a test for the new public endpoint.

## Left to the builder

- How to structure the web-only code (conditional imports vs `kIsWeb` checks), as long as
  `dart:io`-only code never runs on the web.
- Exact phone-frame width and background colour (should suit both light and dark themes).
- The browser-detection approach for hiding the link on iOS.
- Which Render build approach to use.
