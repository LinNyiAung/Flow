# Toe Pwar on the web

The website is the same Flutter code as the Android app, built for the browser. It talks to
the same backend (`https://flowfinance.onrender.com`) and uses the same accounts. The Android
app is not affected by anything on this page.

## 1. Build it

From the `frontend` folder, with Flutter **3.32.1** (stable):

```
flutter build web --release --dart-define=API_BASE_URL=https://flowfinance.onrender.com
```

The finished site is in `frontend/build/web` (plain static files).

## 2. Order of work: backend first

The website cannot work until the backend is live and updated, so do this in order:

1. **Put the new backend live first.** The backend now runs on PostgreSQL (not MongoDB) and
   has the endpoints the website needs (including the public `GET /api/app/latest-android`
   used by the "Get the Android app" link). The steps for the PostgreSQL move are in
   [postgres-migration-plan.md](postgres-migration-plan.md), section "Deploying on Render".
   Finish that, and check the backend answers at https://flowfinance.onrender.com, before
   going on.
2. **Then create the website on Render** (section 3 below).
3. **Last, allow the website to call the backend.** Open the backend service on Render, then
   Environment, and look at the current value of `CORS_ALLOWED_ORIGINS`.
   - If it is **set** (for example to the admin panel address), the website's address **must
     be added** to it, otherwise the browser blocks every request from the website and the
     site cannot log in. Keep the existing addresses and add the website after a comma, e.g.
     `https://admin.example.com,https://toepwar.onrender.com` (no slash at the end of any
     address).
   - If it is **not set**, the backend allows every address and the website works as it is;
     setting it to the website address (plus the admin panel's, if it has one) is optional
     and makes the backend stricter.

   Save; Render redeploys the backend.

## 3. Create the website on Render (Static Site)

You do these clicks in the Render dashboard:

1. Click **New +**, then **Static Site**.
2. Connect the GitHub repository (the same one as the backend) and choose the branch to
   publish (use `main` after the `web-version` branch is merged).
3. Fill in the settings:
   - **Name:** anything you like (e.g. `toepwar`); this becomes the web address.
   - **Root Directory:** leave empty (the repository root).
   - **Build Command:** paste this as one line:

     ```
     [ -d "$HOME/flutter" ] || git clone https://github.com/flutter/flutter.git -b 3.32.1 --depth 1 "$HOME/flutter" && export PATH="$HOME/flutter/bin:$PATH" && cd frontend && flutter build web --release --dart-define=API_BASE_URL=https://flowfinance.onrender.com
     ```

     The version number `3.32.1` is pinned on purpose so the site is built with the same
     Flutter as the app. Change it only when you deliberately upgrade Flutter. The
     `[ -d "$HOME/flutter" ] ||` part skips the download when the Flutter folder is still
     there from an earlier build (a plain `git clone` would fail then). If the log shows a
     "running as root" warning from Flutter, it is harmless. Watch the first build log to
     the end to confirm it finishes.
   - **Publish Directory:** `frontend/build/web`
4. Open **Redirects/Rewrites** (on the Static Site's settings page, or in the form) and add
   one rule:
   - **Source:** `/*`
   - **Destination:** `/index.html`
   - **Action:** `Rewrite`

   This makes a reload on any page open the app instead of a "not found" page.
5. Click **Create Static Site**. The first build takes several minutes (it downloads
   Flutter). When it says "Live", open the address shown at the top and go through the
   checklist below.

To publish a new version later, push to the branch; Render rebuilds automatically.

Notes:

- A free Render backend goes to sleep when idle; the first request can take up to a minute.
  The app shows a "waking up" hint during that wait, which is normal.
- If you ever move the backend, change the address in the Build Command and rebuild.

## 4. Browser checklist

Run this before telling people the site is ready. Most items were exercised locally against
`e2e/run_server.py` (a stubbed backend, started by the e2e scripts) with a local web build
served from `build/web` by `python -m http.server`. A local run cannot cover everything, so
these items **still need a human pass on real devices and browsers** (and, on the real site,
every item below should be repeated against the live address with a test account):

- Voice recording in Chrome and in Safari (microphone permission prompt, recording, result).
- Camera capture for a receipt photo.
- A real switch to another browser tab and back (premium status and unread badge refresh).
- The PDF report landing in the Downloads folder with a sensible name.
- iPhone Safari: the "Get the Android app" link is hidden.
- An iPad in its default desktop mode: the link is hidden.
- A screenshot check of the Myanmar language chip on the voice input screen (it was cut off
  at the bottom in desktop Chrome before a fix; confirm it now reads fully, including in
  Safari).

- Register, verify through the e-mail link, log in.
- Reload while signed in: you stay signed in.
- Add, edit and delete a transaction, including a recurring one.
- Budgets, goals, charts and insights open and show data.
- AI chat: the reply streams in, and Cancel stops it mid-way.
- Receipt photo (PNG and JPG) and voice input work; with the microphone blocked, an error
  message is shown.
- PDF report downloads with a sensible file name.
- Notifications list; notification settings shown without the system on/off switch.
- Switch the language to Myanmar; switch to the dark theme.
- Log out: no `fcm-token` DELETE request appears in the browser devtools Network tab.
- "Get the Android app" link (login screen and side menu) is shown only when an Android
  version is published, and hidden otherwise and on iPhone/iPad.
- Wide window: the app is a centred 440 px column. Phone width: it fills the screen.
- Backend asleep (cold start): the "waking up" hint appears.
- Switching to another browser tab and back refreshes premium status and the unread badge.
