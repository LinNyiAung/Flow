# Toe Pwar Web Version Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the existing Flutter app (`frontend/`) as a website that works like the Android app, plus a "Get the Android app" link to the latest APK.

**Architecture:**
- **One codebase.** Platform differences live behind small helpers in `lib/platform/`, which use conditional imports (`*_io.dart` / `*_web.dart`) and a test-overridable `PlatformInfo.isWeb`.
- **Android paths unchanged.** Every web change is a web-only branch; Android behaves exactly as before.
- **Backend:** gains one public read-only endpoint and exposes `Content-Disposition` to browsers.

**Tech Stack:**
- Flutter (Dart ^3.8.1), `http`, `record`, `image_picker`/`cross_file`, `url_launcher`;
- new: `fetch_client` (streaming on web), `web` (browser APIs);
- FastAPI backend with SQLAlchemy;
- Render static site.

**Spec:** `docs/superpowers/specs/2026-10-16-web-version-design.md`

## Global Constraints

- The Android app's behaviour and look must not change. Web adaptations are web-only branches; Android code paths are kept as they are.
- `dart:io` APIs (`File`, `Platform`, `path_provider`, `permission_handler`, `open_filex`) must never execute on the web. Use the `lib/platform/` helpers.
- User-facing name is **"Toe Pwar"** (page title, manifest `name`/`short_name`, iOS home-screen title).
- **Web layout:**
  - when the browser is wider than 520 logical px, the app renders in a centred column **440 px** wide, full height;
  - at 520 px or narrower it is full width.
- Web builds always pass `--dart-define=API_BASE_URL=<backend URL>` (the in-code default is a LAN address).
- **No push notifications on the web.**
  - The web build must never call `DELETE /api/auth/fcm-token`, which would unregister the user's phone.
  - It must never initialise Firebase.
- **The download link:**
  - shown only in the web build;
  - hidden on iPhone/iPad/iPod user agents;
  - hidden when no version is published.
- Branch: `web-version`. Commit after every task.

## Review Focus

1. **Logout on the web:** it must not unregister the phone's push token. *Test:* `PlatformInfo.isWeb = true`, then `AuthProvider` logout makes no fcm-token DELETE (Task 2).
2. **A reload restores the session.** The token is in SharedPreferences, which is localStorage on the web. A page refresh while signed in must land on Home, not Login. *Check:* browser checklist item, Task 9.
3. **iPhone receipt photos:** they can be PNG or JPEG, so the upload content type must follow the file, not always `image/jpeg`. *Test:* `uploadContentType('receipt.png') == MediaType('image','png')` (Task 5).
4. **Blocked microphone:** a browser that denies the microphone must show the screen's existing error message, not hang or crash. *Check:* browser checklist item, Task 9.
5. **Backend asleep:** on a cold start (Render free tier, about 50 s), the first web visit must show the existing startup spinner and "server waking up" hint, not an error. *Check:* browser checklist item, Task 9.

---

### Task 1: Backend public download endpoint and CORS header

**Files:**
- Modify: `backend/app_version_routes.py` (add to `user_router`)
- Modify: `backend/main.py` (CORSMiddleware: `expose_headers=["Content-Disposition"]`)
- Create: `e2e/test_app_download.py`; add `"test_app_download"` to `SUITES` and `PRINT_ONLY` in `e2e/run_backend_suite.py`

**Interfaces:**
- Produces: `GET /api/app/latest-android` (no auth) → `200 {"version": str | null, "download_url": str | null}`.
  - Picks the highest *parseable* version (`_safe_version`) among **active** versions whose platform is `android` or `all`.
  - Returns nulls when there is none.
  - Exposes no other fields.

- [ ] **Step 1: Write the failing test** `e2e/test_app_download.py`. Style it like `e2e/test_premium_expiry.py`: `check(ok, name)` prints `[PASS]`/`[BUG]`, it uses `pgcompat.get_db()` and talks to `http://127.0.0.1:8765`. Clear `app_versions` first, then:
  - no rows → `{"version": None, "download_url": None}`, status 200, **no Authorization header sent**;
  - insert active `android 1.2.0` (url A), active `all 1.3.0` (url B), inactive `android 9.0.0` (url C), active `ios 5.0.0` (url D), active `android "abc"` (malformed) → response is `{"version": "1.3.0", "download_url": B}`;
  - deactivate `1.3.0` → `{"version": "1.2.0", "download_url": A}`;
  - the response JSON has exactly the keys `{"version", "download_url"}`;
  - CORS: `POST /api/reports/download` as a premium user (create one as `test_premium_expiry.py` does), sent with header `Origin: http://example.com`, returns 200 with `access-control-expose-headers` containing `content-disposition` (case-insensitive).
- [ ] **Step 2: Run it to verify it fails**
  - Run: `scratchpad run_suite.ps1 -NoSuite`, then `python e2e/test_app_download.py`.
  - Expected: `[BUG]` lines (404 on the endpoint) and a non-zero exit.
- [ ] **Step 3: Implement** `latest_android_version() -> dict` in `app_version_routes.py`. Reuse `versions_db.active_for_platforms([Platform.ANDROID.value, Platform.ALL.value], limit=500)` and `_safe_version`, exactly like `check_app_version`. Add `expose_headers=["Content-Disposition"]` to the CORS middleware in `main.py`.
- [ ] **Step 4: Run the test to verify it passes.** Expected: all `[PASS]`, exit 0.
- [ ] **Step 5: Commit**: `git commit -m "Add public latest-Android-version endpoint; expose Content-Disposition to browsers"`

---

### Task 2: Web-safe startup, push and notification services

**Files:**
- Create: `frontend/lib/platform/platform_info.dart`
- Modify: `frontend/lib/main.dart:56-69` (startup), `:237-255` (`_checkVersion`)
- Modify: `frontend/lib/services/fcm_service.dart`, `frontend/lib/services/notification_service.dart`
- Modify: `frontend/lib/providers/auth_provider.dart` (`_registerFcmFor`, `_flushPendingFcmUnregister`, `_unregisterFcm`)
- Modify: `frontend/lib/screens/settings/notification_settings_screen.dart`
- Test: `frontend/test/web_platform_test.dart`

**Interfaces:**
- Produces: `class PlatformInfo { static bool isWeb = kIsWeb; }`, with `isWeb` `@visibleForTesting`-settable. **All** later tasks check `PlatformInfo.isWeb`, never `kIsWeb` directly, so tests can flip it.
- Produces (test seam, the only one added): `@visibleForTesting static Future<void> Function(String authToken)? deleteFcmTokenOverride` on `ApiService`. When it is set, `ApiService.deleteFCMToken(authToken: t)` calls it instead of making the HTTP request.

- [ ] **Step 1: Write the failing tests** in `test/web_platform_test.dart`:
  - `logout on web does not unregister the FCM token`:
    - set `PlatformInfo.isWeb = true`;
    - set the `deleteFCMToken` override to record calls;
    - sign in an `AuthProvider` with a saved token (SharedPreferences mock values) and call `logout()`;
    - expect zero recorded calls.
  - `logout on Android still unregisters`: `PlatformInfo.isWeb = false` → exactly one recorded call with the old auth token.
  - `FCMService on web is inert`: with `PlatformInfo.isWeb = true`, `await FCMService().initialize()` completes, `FCMService().fcmToken` is `null`, and nothing throws (no Firebase app exists in tests).
- [ ] **Step 2: Run** `flutter test test/web_platform_test.dart`. Expected: FAIL (missing `PlatformInfo`).
- [ ] **Step 3: Implement**
  - **`main.dart`:**
    - call `Firebase.initializeApp()`, `FCMService().initialize()` and `NotificationService().initialize()` only when `!PlatformInfo.isWeb`;
    - in `_checkVersion`, return early with `_versionCheckDone = true` (no request) when `PlatformInfo.isWeb`;
    - replace `Platform.isIOS` with `defaultTargetPlatform == TargetPlatform.iOS` and drop the `dart:io` import.
  - **`FCMService`:**
    - make `_fcm` a lazy getter (`FirebaseMessaging get _fcm => FirebaseMessaging.instance;`);
    - `initialize`, `sendTokenToBackend`, `subscribeToTopic` and `unsubscribeFromTopic` return immediately on web.
  - **`NotificationService`:** `initialize`, `showNotification` and the cancel methods return immediately on web; `requestPermissions` returns `false` on web.
  - **`AuthProvider`:** `_registerFcmFor`, `_flushPendingFcmUnregister` and `_unregisterFcm` return immediately on web.
  - **Notification settings screen, on web:**
    - `_initialize` skips `_checkPermissionStatus`, sets `_notificationsEnabled = true` and loads preferences;
    - the system-permission switch card and the "test notification" button are not built.
- [ ] **Step 4: Run** `flutter test`. Expected: the new tests PASS, and the existing tests in `frontend/test/` still PASS.
- [ ] **Step 5: Run** `flutter build web --release --dart-define=API_BASE_URL=http://127.0.0.1:8765`. Expected: the build succeeds.
- [ ] **Step 6: Commit**: `"Web: skip Firebase/FCM/local notifications and the update check"`

---

### Task 3: Phone-width frame on wide screens

**Files:**
- Create: `frontend/lib/widgets/web_phone_frame.dart`
- Modify: `frontend/lib/main.dart` (`MaterialApp.builder`)
- Test: `frontend/test/web_phone_frame_test.dart`

**Interfaces:**
- Produces: `class WebPhoneFrame extends StatelessWidget { const WebPhoneFrame({super.key, required this.child}); static const double frameWidth = 440; static const double breakpoint = 520; }`.
  - It is used as `builder: (context, child) => PlatformInfo.isWeb ? WebPhoneFrame(child: child!) : child!`.
  - Because it wraps the Navigator, routes, dialogs and bottom sheets all live inside the frame.

- [ ] **Step 1: Write the failing tests:**
  - At a test surface of `1280x800`, a `MaterialApp(builder: (c, child) => WebPhoneFrame(child: child!), home: Scaffold(key: k))` gives `tester.getSize(find.byKey(k)).width == 440`, and `MediaQuery.of(k.currentContext!).size.width == 440`.
  - At `390x844` the width is `390`.
  - At `1280x800`, a `showDialog` dialog's `Dialog` widget is horizontally inside the 440 px column.
- [ ] **Step 2: Run** `flutter test test/web_phone_frame_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Wide case:
    - `ColoredBox` (background `Theme.of(context).colorScheme.surfaceContainerHighest`, so it suits light and dark);
    - inside it, `Center(child: SizedBox(width: frameWidth, child: MediaQuery(data: mq.copyWith(size: Size(frameWidth, mq.size.height)), child: ClipRect(child: child))))`.
  - Narrow case: `child` unchanged.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit**: `"Web: show the app in a phone-width column on wide screens"`

---

### Task 4: PDF report download in the browser

**Files:**
- Create: `frontend/lib/platform/file_saver.dart` (conditional export), `file_saver_io.dart`, `file_saver_web.dart`
- Modify: `frontend/lib/services/api_service.dart:1452-1525` (`downloadReportPdf`)
- Modify: `frontend/lib/screens/report/reports_screen.dart:117-138`
- Modify: `frontend/pubspec.yaml` (add `web`)
- Test: `frontend/test/report_download_test.dart`

**Interfaces:**
- Produces:
  - `String reportFilenameFromContentDisposition(String? header)`, in `api_service.dart`, top-level; defaults to `'financial_report.pdf'`;
  - `class ReportPdf { final Uint8List bytes; final String filename; }`;
  - `ApiService.downloadReportPdf(...)` now returns `Future<ReportPdf>`.
- Produces: `Future<String?> saveReportPdf(ReportPdf pdf)` in `file_saver.dart`:
  - **Android:** writes to `getApplicationDocumentsDirectory()` and returns the path;
  - **Web:** starts a browser download (a `Blob` and an `<a download>` element via `package:web`) and returns `null`.
- [ ] **Step 1: Write the failing test** `reportFilenameFromContentDisposition`:
  - `'attachment; filename="report_2026-10.pdf"'` → `'report_2026-10.pdf'`;
  - `'attachment; filename=plain.pdf'` → `'plain.pdf'`;
  - `null` → `'financial_report.pdf'`;
  - `'inline'` → `'financial_report.pdf'`.
- [ ] **Step 2: Run** `flutter test test/report_download_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** the function, `ReportPdf`, the saver, and the screen change:
  - `final path = await saveReportPdf(pdf);`
  - The snackbar shows the "Open" action (`OpenFilex.open(path)`) only when `path != null`.
  - `open_filex` is imported only from the io side or kept in the screen behind `path != null` (it is never called on the web).
- [ ] **Step 4: Run** `flutter test` and `flutter build web ...`. Expected: PASS, and the build succeeds.
- [ ] **Step 5: Commit**: `"Web: download PDF reports through the browser"`

---

### Task 5: Voice input and receipt photos from bytes

**Files:**
- Modify: `frontend/lib/services/api_service.dart:1579-1678` (`transcribeAudio`, `extractTransactionFromImage`)
- Modify: `frontend/lib/screens/transactions/voice_input_screen.dart` (start/stop/process, permission request)
- Modify: `frontend/lib/screens/transactions/image_input_screen.dart` (`_selectedImage`, pickers, preview at line 380, permission request)
- Modify: `frontend/pubspec.yaml` (add `cross_file` explicitly)
- Test: `frontend/test/upload_content_type_test.dart`

**Interfaces:**
- Produces: `MediaType uploadContentType(String filename)`, in `api_service.dart`, top-level:

  | Extension | Content type |
  | --- | --- |
  | `.wav` | `audio/wav` |
  | `.webm` | `audio/webm` |
  | `.m4a` | `audio/mp4` |
  | `.png` | `image/png` |
  | `.jpg` / `.jpeg` | `image/jpeg` |
  | `.webp` | `image/webp` |
  | `.heic` | `image/heic` |
  | anything else | `application/octet-stream` |

- Produces:
  - `ApiService.transcribeAudio(Uint8List bytes, {required String filename, String? language})`;
  - `ApiService.extractTransactionFromImage(Uint8List bytes, {required String filename})`.
  
  Both use `http.MultipartFile.fromBytes(..., filename: filename, contentType: uploadContentType(filename))`. The multipart field names stay `audio` and `image`.
- [ ] **Step 1: Write the failing test.** Every row of the mapping table above, plus `uploadContentType('RECEIPT.PNG')` → `image/png` (case-insensitive).
- [ ] **Step 2: Run** `flutter test test/upload_content_type_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - **Voice:**
    - On web, skip `Permission.microphone.request()`; the browser prompts.
    - On web, start with `path: ''` and encoder `AudioEncoder.wav` if `await _audioRecorder.isEncoderSupported(AudioEncoder.wav)`, else `AudioEncoder.opus`, with filename `recording.wav` / `recording.webm`.
    - After `stop()`, read bytes with `XFile(path).readAsBytes()`; this works for Android file paths and web blob URLs.
    - Android keeps its temp-file `.wav` path.
  - **Image:**
    - Hold `XFile? _selectedImage` plus `Uint8List? _imageBytes`.
    - Preview with `Image.memory`.
    - Upload with `filename: image.name`.
    - Skip the `Permission.*` requests on web.
  - Remove `dart:io` from both screens.
- [ ] **Step 4: Run** `flutter test` and `flutter build web ...`. Expected: PASS, and the build succeeds.
- [ ] **Step 5: Commit**: `"Upload voice recordings and receipt photos as bytes (web-compatible)"`

---

### Task 6: Streaming AI chat in the browser

**Files:**
- Create: `frontend/lib/platform/streaming_client.dart` (conditional export), `streaming_client_io.dart`, `streaming_client_web.dart`
- Modify: `frontend/lib/services/api_service.dart:975-994` (chat stream client + error handling)
- Modify: `frontend/pubspec.yaml` (add `fetch_client`)

**Interfaces:**
- Produces: `http.Client createStreamingClient()`:
  - **Android:** `http.Client()`;
  - **Web:** `FetchClient(mode: RequestMode.cors)`.
  
  This is needed because the browser `http` client buffers whole responses, so the chat would appear only at the end and could hit the per-chunk idle timeout.
- [ ] **Step 1: Implement.** In the chat stream, replace `http.Client()` with `createStreamingClient()`. Add `on http.ClientException catch (e) { throw ApiException('$networkErrorMessage (${e.message})'); }` next to the existing `SocketException` catch.
- [ ] **Step 2: Verify in a browser** (the backend runs with `E2E_FAKE_AI=1`, whose OpenAI fake streams in chunks):
  - build the web app against the local backend and send a chat message as a premium user;
  - Expected: the reply appears progressively, with no timeout error.
  - Also run `flutter test`. Expected: PASS.
- [ ] **Step 3: Commit**: `"Web: stream AI chat replies with fetch"`

---

### Task 7: Refresh premium status and the unread badge when the tab regains focus

**Files:**
- Modify: `frontend/lib/providers/auth_provider.dart` (rename `_silentRefreshUser` → public `refreshUserSilently()`; the FCM listener calls it)
- Modify: `frontend/lib/main.dart` (`_MyAppState`: an `AppLifecycleListener` created in `initState`, only when `PlatformInfo.isWeb`, disposed in `dispose`)

**Interfaces:**
- Consumes: `NotificationProvider.fetchUnreadCount()` (existing).
- Produces: `Future<void> AuthProvider.refreshUserSilently()`. It does nothing when signed out and never throws.
- [ ] **Step 1: Implement.** `onResume`: `if (_authProvider.isAuthenticated) { _authProvider.refreshUserSilently(); _notificationProvider.fetchUnreadCount(); }`.
- [ ] **Step 2: Verify in a browser.**
  - Signed in as a free user in one tab, grant premium in the admin panel and switch back to the app tab.
  - Expected: premium features unlock without a reload, and the badge updates after a broadcast.
  - Also run `flutter test`. Expected: PASS.
- [ ] **Step 3: Commit**: `"Web: refresh profile and unread count when the tab becomes visible"`

---

### Task 8: "Get the Android app" link

**Files:**
- Create: `frontend/lib/platform/user_agent.dart` (conditional export: io → `''`, web → `window.navigator.userAgent`)
- Create: `frontend/lib/widgets/android_download_link.dart`
- Modify:
  - `frontend/lib/services/api_service.dart` (client call);
  - `frontend/lib/screens/auth/login_screen.dart` (below the register link, ~line 217);
  - `frontend/lib/widgets/app_drawer.dart` (a row above Settings/Logout);
  - `frontend/lib/services/localization_service.dart` (en ~790, my ~1782, getter ~2824).
- Test: `frontend/test/android_download_link_test.dart`

**Interfaces:**
- Consumes: `GET /api/app/latest-android` (Task 1).
- Produces:
  - `class AndroidDownload { final String version; final String url; }`;
  - `static Future<AndroidDownload?> ApiService.getLatestAndroidDownload()`, which returns `null` for null fields or any error and sends no auth header;
  - `bool shouldOfferAndroidDownload({required bool isWeb, required String userAgent})`, which is `isWeb && !RegExp('iPhone|iPad|iPod', caseSensitive: false).hasMatch(userAgent)`;
  - `class AndroidDownloadLink extends StatefulWidget { const AndroidDownloadLink({super.key, this.inDrawer = false}); }`:
    - it renders nothing unless `shouldOfferAndroidDownload(...)` is true and the fetch returned a value;
    - tapping it opens the URL with `launchUrl(uri, mode: LaunchMode.externalApplication)`.
- Copy:
  - key `getAndroidApp`: en `'Get the Android app'`, my `'Android အက်ပ်ကို ရယူပါ'`;
  - key `androidAppVersion`: en `'Version {version}'`, my `'ဗားရှင်း {version}'` (shown under the link text).
- [ ] **Step 1: Write the failing tests:**
  - `shouldOfferAndroidDownload`:
    - web plus a desktop Chrome UA → `true`;
    - web plus an Android Chrome UA → `true`;
    - web plus an iPhone Safari UA → `false`;
    - web plus an iPad UA → `false`;
    - `isWeb: false` plus any UA → `false`.
  - **Widget:** with `PlatformInfo.isWeb = false`, `AndroidDownloadLink` builds `SizedBox.shrink` (no text 'Get the Android app').
- [ ] **Step 2: Run** `flutter test test/android_download_link_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** the function, the client call, the widget and the copy. Place it in the login screen and the drawer.
- [ ] **Step 4: Run** `flutter test` and `flutter build web ...`. Expected: PASS, and the build succeeds.
- [ ] **Step 5: Verify in a browser.**
  - With an active `android` version published, the link shows under login and in the drawer, and opens the URL.
  - With the user agent emulated as iPhone (browser devtools), it is hidden.
  - With no published version, it is hidden.
- [ ] **Step 6: Commit**: `"Web: add the Get the Android app link"`

---

### Task 9: Site identity, hosting guide and browser checklist

**Files:**
- Modify: `frontend/web/index.html`:
  - `<title>Toe Pwar</title>`;
  - `<meta name="description" content="Toe Pwar - personal finance: track spending, budgets and goals.">`;
  - `apple-mobile-web-app-title` set to `Toe Pwar`;
  - `theme-color`.
- Modify: `frontend/web/manifest.json`: `name`/`short_name` `"Toe Pwar"`, the description above, `background_color`/`theme_color` taken from `AppTheme` primary.
- Create: `frontend/flutter_launcher_icons-web.yaml`. It holds only a `flutter_launcher_icons:` block with `web: generate: true, image_path: "assets/icon/flow.png"`, so the Android icons are not regenerated. Run `dart run flutter_launcher_icons -f flutter_launcher_icons-web.yaml`.
- Create: `docs/web-version.md`, which contains:
  - **Build:** `flutter build web --release --dart-define=API_BASE_URL=https://flowfinance.onrender.com`.
  - **Render Static Site** settings for the owner, step by step:
    - Root Directory: repo root;
    - Build Command installs Flutter pinned to the version in `flutter --version` (`git clone https://github.com/flutter/flutter.git -b <version> --depth 1 "$HOME/flutter"`), then `cd frontend && flutter build web ...`;
    - Publish Directory: `frontend/build/web`;
    - a Rewrite rule `/*` → `/index.html`.
  - **Order:** the backend goes live first.
  - **Browser checklist.** Each item runs against `e2e/run_server.py`, with a local web build served by `python -m http.server` from `build/web`:
    - register, verify via the outbox link, log in;
    - **reload while signed in → still signed in**;
    - add, edit and delete a transaction, including a recurring one;
    - budgets, goals, charts, insights;
    - AI chat streams;
    - receipt photo (PNG and JPG) and voice input, including **microphone denied → error message**;
    - PDF download;
    - notifications list; notification settings without the system toggle;
    - language switch to Myanmar; dark theme;
    - logout, with **no `fcm-token` DELETE in the devtools Network tab**;
    - download link shown or hidden as specified;
    - wide window → centred 440 px column; phone width → full width;
    - **backend cold start shows the waking-up hint**.
- [ ] **Step 1: Apply** the identity changes and generate the web icons. Check `git status`: only `frontend/web/**` changed, and nothing under `android/` or `ios/`.
- [ ] **Step 2: Write** `docs/web-version.md`.
- [ ] **Step 3: Run the whole checklist** in a browser and fix anything that fails, with a new commit per fix.
- [ ] **Step 4: Regression gates:**
  - `flutter test` → PASS;
  - backend suite (`e2e/run_backend_suite.py`) → 0 problems;
  - the Android Flutter e2e suite: `e2e/run_e2e.ps1` → 41/41, plus `-LargeText -Name "^14 Large text tour "` → 2/2.
- [ ] **Step 5: Commit**: `"Web: Toe Pwar identity, hosting guide and browser checklist"`
