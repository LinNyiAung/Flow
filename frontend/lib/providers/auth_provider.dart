import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/platform/platform_info.dart';
import 'package:frontend/services/fcm_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/services/notification_event_bus.dart';
import 'package:frontend/services/pending_fcm_unregister.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class AuthProvider with ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  String? _error;
  bool _isAuthChecking = true;
  bool _authCheckInFlight = false;

  /// Bumped by logout / session expiry: an in-flight [checkAuthStatus]
  /// started before that ignores its (late) result and never touches the
  /// auth-check flags again.
  int _authGeneration = 0;

  /// Sequence number of the latest language choice; only the latest one is
  /// sent, and only its response may clear the "sync pending" marker.
  int _languageSeq = 0;

  /// Tail of the serialized language PUT chain (never completes with an
  /// error).
  Future<void>? _languagePush;

  /// The logout `DELETE /api/auth/fcm-token` that may still be in flight
  /// (completes with null on success, else the error). Registering this
  /// device again waits for it, so a late DELETE can't wipe the new token.
  Future<Object?>? _fcmDeleteInFlight;

  /// Running flush of a persisted [PendingFcmUnregister] (deduplicated).
  Future<void>? _pendingFcmFlush;

  /// The last session restore failed for a transient reason (timeout,
  /// offline, 5xx). The stored token is kept and the app shows a retry
  /// screen instead of the login screen.
  bool _sessionRestoreFailed = false;
  String? _sessionRestoreError;

  /// Id of the last user whose data was loaded into the app's providers.
  String? _lastUserId;

  /// E-mail of an account that tried to log in / register but is not
  /// verified yet. The login screen offers "Resend verification email".
  String? _pendingVerificationEmail;

  /// Wipes every per-user provider (transactions, goals, insights, chat...).
  /// Wired up by the app root; called on logout, session expiry and when a
  /// different user logs in.
  VoidCallback? onSessionReset;

  /// Applies the user's server-side language preference to the app.
  void Function(String languageCode)? onLanguagePreference;

  // Listens for admin-triggered subscription changes
  StreamSubscription? _subscriptionUpdateSub;

  bool get isAuthChecking => _isAuthChecking;
  bool get sessionRestoreFailed => _sessionRestoreFailed;
  String? get sessionRestoreError => _sessionRestoreError;
  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;
  bool get hasClaimedFreeTrial => _user?.hasClaimedFreeTrial ?? false;
  String? get pendingVerificationEmail => _pendingVerificationEmail;

  bool get isPremium => _user?.isPremium ?? false;
  SubscriptionType get subscriptionType =>
      _user?.subscriptionType ?? SubscriptionType.free;
  DateTime? get subscriptionExpiresAt => _user?.subscriptionExpiresAt;
  Currency get defaultCurrency => _user?.defaultCurrency ?? Currency.usd;

  AuthProvider() {
    // Listen for silent FCM subscription_updated messages so the UI
    // reflects premium access the moment admin grants it — no sign-out needed.
    _subscriptionUpdateSub = NotificationEventBus()
        .onSubscriptionUpdated
        .listen((_) => _silentRefreshUser());
  }

  @override
  void dispose() {
    _subscriptionUpdateSub?.cancel();
    super.dispose();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  static String _cleanError(Object e) =>
      e.toString().replaceAll('Exception: ', '');

  Future<void> _sendFCMToken() async {
    try {
      await FCMService().sendTokenToBackend();
    } catch (e) {
      debugPrint('Could not send FCM token: $e');
    }
  }

  /// Registers this device's FCM token for [userId] (login / restored
  /// session) — but first lets an in-flight logout DELETE finish and sends
  /// (or cancels) a persisted pending unregister, so neither can remove the
  /// token registered here.
  Future<void> _registerFcmFor(String userId) async {
    if (PlatformInfo.isWeb) return;
    final inFlight = _fcmDeleteInFlight;
    if (inFlight != null) await inFlight;
    await _flushPendingFcmUnregister(signedInUserId: userId);
    await _sendFCMToken();
  }

  /// Retries a logout's failed FCM unregister. When [signedInUserId] is the
  /// same account that logged out, the delete is cancelled instead (its
  /// token is re-sent right after by [_registerFcmFor]).
  Future<void> _flushPendingFcmUnregister({String? signedInUserId}) {
    if (PlatformInfo.isWeb) return Future<void>.value();
    return _pendingFcmFlush ??= () async {
      try {
        final pending = await PendingFcmUnregister.load();
        if (pending == null) return;
        if (signedInUserId != null && pending.userId == signedInUserId) {
          await PendingFcmUnregister.clear();
          return;
        }
        try {
          await ApiService.deleteFCMToken(authToken: pending.authToken);
          await PendingFcmUnregister.clearIfAuthToken(pending.authToken);
        } catch (e) {
          // 401/403: that session is gone server-side — nothing left to
          // unregister with it. Anything else: keep it for the next try.
          if (ApiService.isSessionRejection(e) ||
              (e is ApiException && e.statusCode == 403)) {
            await PendingFcmUnregister.clearIfAuthToken(pending.authToken);
          } else {
            debugPrint('Pending FCM unregister failed, will retry: $e');
          }
        }
      } catch (e) {
        debugPrint('Pending FCM unregister flush failed: $e');
      } finally {
        _pendingFcmFlush = null;
      }
    }();
  }

  /// Clears all per-user state held by other providers.
  void _resetSessionState() {
    _lastUserId = null;
    try {
      onSessionReset?.call();
    } catch (e) {
      debugPrint('AuthProvider: session reset failed: $e');
    }
  }

  /// Called once a user is known (login / restored session).
  void _onUserSignedIn(User user) {
    if (_lastUserId != user.id) {
      // A different account (or the first one since logout): drop anything
      // cached — including late responses from the previous session.
      _resetSessionState();
    }
    _lastUserId = user.id;
    _sessionRestoreFailed = false;
    _sessionRestoreError = null;
    unawaited(_syncLanguagePreference(user));
  }

  /// Reconciles the server-side language preference with the local one.
  /// A local change whose PUT failed (e.g. offline) wins and is re-sent;
  /// otherwise the server value is applied.
  Future<void> _syncLanguagePreference(User user) async {
    try {
      final decision = LanguageSyncDecision.decide(
        userId: user.id,
        serverLanguage: user.language,
        localLanguage: await LocalizationService.getSelectedLanguage(),
        pendingUserId: await LocalizationService.getLanguageSyncPendingUser(),
      );
      if (decision.clearPending) {
        await LocalizationService.setLanguageSyncPendingUser(null);
      }
      final apply = decision.apply;
      if (apply != null) {
        await LocalizationService.setSelectedLanguage(apply);
        onLanguagePreference?.call(apply);
      }
      if (decision.push) {
        final seq = ++_languageSeq;
        await _pushLanguage(
          user.id,
          await LocalizationService.getSelectedLanguage(),
          seq,
        );
      }
    } catch (e) {
      debugPrint('AuthProvider: language sync failed: $e');
    }
  }

  /// PUT /api/auth/language, serialized: each call waits for the previous
  /// PUT, and a call whose [seq] is no longer the latest is skipped (the
  /// newer choice is sent instead), so rapid toggles never race. The "sync
  /// pending" marker is cleared only by the response for the LATEST choice,
  /// and only if that value is still the one selected locally.
  Future<bool> _pushLanguage(String userId, String languageCode, int seq) async {
    final previous = _languagePush;
    final done = Completer<void>();
    _languagePush = done.future;
    try {
      if (previous != null) await previous;
      if (seq != _languageSeq) return false; // superseded by a newer choice
      await ApiService.updateLanguage(languageCode);
      if (seq == _languageSeq &&
          await LocalizationService.getLanguageSyncPendingUser() == userId &&
          await LocalizationService.getSelectedLanguage() == languageCode) {
        await LocalizationService.setLanguageSyncPendingUser(null);
      }
      return true;
    } catch (e) {
      debugPrint('AuthProvider: language PUT failed, will retry: $e');
      return false;
    } finally {
      done.complete();
    }
  }

  /// Saves [languageCode] locally and syncs it to the server. The choice is
  /// marked "sync pending" until the PUT succeeds, so if it fails (offline)
  /// the next login keeps the local choice and retries instead of letting
  /// the server value overwrite it.
  Future<void> updateLanguagePreference(String languageCode) async {
    // Taken before any await so the sequence follows the user's taps.
    final seq = ++_languageSeq;
    await LocalizationService.setSelectedLanguage(languageCode);
    final userId = _user?.id;
    if (userId == null) return;
    // Mark first so an app kill mid-request still counts as unsynced.
    await LocalizationService.setLanguageSyncPendingUser(userId);
    final ok = await _pushLanguage(userId, languageCode, seq);
    if (ok && seq == _languageSeq && _user?.id == userId) {
      _user = _user!.copyWith(language: languageCode);
    }
  }

  /// Silently re-fetches the user from /api/auth/me and updates state.
  /// Called automatically when a subscription_updated FCM message arrives.
  Future<void> _silentRefreshUser() async {
    if (_user == null) return;
    try {
      final refreshed = await ApiService.getCurrentUser();
      if (_user == null || refreshed.id != _user!.id) return;
      _user = refreshed;
      notifyListeners();
    } catch (e) {
      // Background refresh — don't clear the user or show an error.
      debugPrint('AuthProvider: silent refresh failed: $e');
    }
  }

  // ─── Public refresh (can be called manually, e.g. pull-to-refresh) ───────
  Future<void> refreshSubscriptionStatus() async {
    try {
      final status = await ApiService.getSubscriptionStatus();
      if (_user != null) {
        _user = _user!.copyWith(
          subscriptionType: status.subscriptionType,
          subscriptionExpiresAt: status.expiresAt,
          clearSubscriptionExpiresAt: status.expiresAt == null,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error refreshing subscription status: $e');
    }
  }

  // ─── Auth actions ─────────────────────────────────────────────────────────

  Future<bool> updateDefaultCurrency({required Currency currency}) async {
    _setLoading(true);
    _setError(null);
    try {
      _user = await ApiService.updateDefaultCurrency(currency: currency);
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(_cleanError(e));
      _setLoading(false);
      return false;
    }
  }

  /// Registers a new account. Unverified accounts are NOT signed in: the
  /// returned token is discarded and [pendingVerificationEmail] is set so
  /// the UI can show the "check your e-mail" step.
  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    _setError(null);
    try {
      final authResponse = await ApiService.register(
        name: name,
        email: email,
        password: password,
      );

      if (!authResponse.user.isVerified) {
        // The register screen shows its own "verify your e-mail" step; the
        // login screen's notice is only for an actual unverified login.
        _pendingVerificationEmail = null;
        _setLoading(false);
        return true;
      }

      _pendingVerificationEmail = null;
      _onUserSignedIn(authResponse.user);
      _user = authResponse.user;
      unawaited(_registerFcmFor(authResponse.user.id));
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(_cleanError(e));
      _setLoading(false);
      return false;
    }
  }

  Future<bool> login({required String email, required String password}) async {
    _setLoading(true);
    _setError(null);
    _pendingVerificationEmail = null;
    try {
      final authResponse = await ApiService.login(
        email: email,
        password: password,
      );
      _onUserSignedIn(authResponse.user);
      _user = authResponse.user;
      // Re-register this device for pushes (it was unregistered on logout)
      // once any pending / in-flight logout unregister has settled.
      unawaited(_registerFcmFor(authResponse.user.id));
      _setLoading(false);
      return true;
    } on EmailNotVerifiedException catch (e) {
      _pendingVerificationEmail = email;
      _setError(e.message);
      _setLoading(false);
      return false;
    } catch (e) {
      _setError(_cleanError(e));
      _setLoading(false);
      return false;
    }
  }

  /// POST /api/auth/resend-verification — always "succeeds" server-side.
  /// Returns null on success, otherwise a user-facing error message. The
  /// message is NOT stored in [error] (the login screen hides [error] behind
  /// the verify notice, and the register flow must not leave a stale error
  /// on the login screen).
  Future<String?> resendVerificationEmail(String email) async {
    try {
      await ApiService.resendVerificationEmail(email: email);
      return null;
    } catch (e) {
      return _cleanError(e);
    }
  }

  void clearPendingVerification() {
    if (_pendingVerificationEmail == null) return;
    _pendingVerificationEmail = null;
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<bool> deleteAccount({required String password}) async {
    _setLoading(true);
    _setError(null);
    try {
      await ApiService.deleteAccount(password: password);
      _user = null;
      _resetSessionState();
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(_cleanError(e));
      _setLoading(false);
      return false;
    }
  }

  Future<bool> canAccessPremiumFeature(BuildContext context) async {
    if (isPremium) return true;
    await _showUpgradeDialog(context);
    return false;
  }

  Future<bool> updateProfile({required String name}) async {
    _setLoading(true);
    _setError(null);
    try {
      _user = await ApiService.updateProfile(name: name);
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(_cleanError(e));
      _setLoading(false);
      return false;
    }
  }

  /// Signs out: wipes all per-user state, clears the stored auth token and
  /// then starts unregistering this device's FCM token in the background,
  /// authenticating with the captured old token (still valid server-side).
  /// Returns without waiting for that request. Callers should then
  /// navigate to the root (AuthWrapper) with pushAndRemoveUntil.
  /// Ends any session restore in progress: its late result is ignored (see
  /// [_authGeneration]) and the startup spinner / retry progress is dropped
  /// immediately instead of after the request's timeout (up to 60 s).
  void _cancelAuthCheck() {
    _authGeneration++;
    _authCheckInFlight = false;
    _isAuthChecking = false;
  }

  Future<void> logout() async {
    // Read the token before anything else can store a newer one.
    final tokenFuture = ApiService.getToken();
    // Synchronous part first: Logout pressed on the retry screen while a
    // retry is in flight must leave the spinner right away.
    _cancelAuthCheck();
    final userId = _user?.id ?? _lastUserId;

    // Drop every trace of the previous user from memory first so nothing
    // can render it again (e.g. Bob seeing Alice's AI insight).
    _user = null;
    _error = null;
    _pendingVerificationEmail = null;
    _sessionRestoreFailed = false;
    _sessionRestoreError = null;
    ApiService.cancelChatStream();
    _resetSessionState();
    notifyListeners();

    final token = await tokenFuture;
    if (token == null) return;

    // Remove the stored token BEFORE the (up to 5 s) FCM call: a login that
    // completes in that window saves a new token, which must survive. Only
    // the token captured above is ever removed.
    await ApiService.removeTokenIfMatches(token);
    // Not awaited: callers navigate to the login screen as soon as logout()
    // returns, and waiting here kept the old screen up for up to 5 s. The
    // request is tracked in [_fcmDeleteInFlight] (a quick re-login waits for
    // it) and a failure is persisted and retried, so nothing needs it here.
    unawaited(_unregisterFcm(token: token, userId: userId));
  }

  /// `DELETE /api/auth/fcm-token` as the signed-out session. Waits at most
  /// 5 s; if it fails or is still running, it is persisted as a
  /// [PendingFcmUnregister] and retried later. A late success clears that
  /// entry again. The request itself stays tracked in [_fcmDeleteInFlight]
  /// so a quick re-login registers its token only after it has landed.
  Future<void> _unregisterFcm({required String token, String? userId}) async {
    // Never on the web: the DELETE would unregister the push token of the
    // same account's phone.
    if (PlatformInfo.isWeb) return;
    String? fcmToken;
    try {
      fcmToken = FCMService().fcmToken;
    } catch (_) {
      // Firebase unavailable — the token is informational only.
    }
    final settled = ApiService.deleteFCMToken(authToken: token)
        .then<Object?>((_) => null, onError: (Object e) => e);
    _fcmDeleteInFlight = settled;
    var succeeded = false;
    unawaited(settled.then((error) async {
      if (identical(_fcmDeleteInFlight, settled)) _fcmDeleteInFlight = null;
      if (error == null) {
        succeeded = true;
        try {
          await PendingFcmUnregister.clearIfAuthToken(token);
        } catch (_) {}
      }
    }));

    Object? error;
    try {
      error = await settled.timeout(const Duration(seconds: 5));
    } on TimeoutException catch (e) {
      error = e;
    }
    if (error == null) return;
    debugPrint('Could not unregister FCM token: $error');
    // A rejected token can never unregister anything — don't retry it.
    if (ApiService.isSessionRejection(error) ||
        (error is ApiException && error.statusCode == 403)) {
      return;
    }
    try {
      await PendingFcmUnregister.save(PendingFcmUnregister(
        authToken: token,
        userId: userId,
        fcmToken: fcmToken,
      ));
      // The request may have succeeded while the entry was being written.
      if (succeeded) await PendingFcmUnregister.clearIfAuthToken(token);
    } catch (e) {
      debugPrint('Could not persist pending FCM unregister: $e');
    }
  }

  /// The backend rejected [token] (401: password changed elsewhere, account
  /// deleted, token revoked...). Only acts if [token] is still the stored
  /// token — a late 401 for an older session must not sign out a newer one.
  /// Returns true when a signed-in user was actually logged out.
  Future<bool> handleSessionExpired(String token) async {
    if (await ApiService.getToken() != token) return false;
    await ApiService.removeTokenIfMatches(token);
    // A login that finished meanwhile stored a newer token: leave it alone.
    if (await ApiService.getToken() != null) return false;

    _cancelAuthCheck();
    final wasSignedIn = _user != null;
    ApiService.cancelChatStream();
    _user = null;
    // Definitely signed out: show login, not the "can't reach server" retry.
    _sessionRestoreFailed = false;
    _sessionRestoreError = null;
    _resetSessionState();
    if (wasSignedIn) {
      _error = AppLocalizations(Locale(ApiService.currentLanguage))
          .sessionExpiredSignInAgain;
    }
    notifyListeners();
    return wasSignedIn;
  }

  /// Restores the saved session on app start (and from the retry screen).
  ///
  /// Only a definite rejection (401 / 403 "Email not verified") signs the
  /// user out. A timeout, network error or server error (e.g. a Render cold
  /// start) keeps the stored token and sets [sessionRestoreFailed] so the
  /// app shows a retry state instead of the login screen.
  Future<void> checkAuthStatus() async {
    if (_authCheckInFlight) return;
    final generation = _authGeneration;
    _authCheckInFlight = true;
    _isAuthChecking = true;
    // _sessionRestoreFailed is kept while retrying, so the retry screen stays
    // up (with a progress indicator) instead of flipping back to the startup
    // spinner for the whole length of each attempt.
    notifyListeners();

    // A logout / session expiry since this check started (it cancelled the
    // check and already reset the flags): drop the late result.
    bool superseded() => generation != _authGeneration;

    String? token;
    try {
      token = await ApiService.getToken();
      if (superseded()) return;
      if (token != null) {
        final user = await ApiService.getCurrentUser();
        // A login / logout may have happened while /me was in flight.
        if (!superseded() && await ApiService.getToken() == token) {
          _onUserSignedIn(user);
          _user = user;
          _sessionRestoreFailed = false;
          _sessionRestoreError = null;
          unawaited(_registerFcmFor(user.id));
        }
      } else {
        _sessionRestoreFailed = false;
        _sessionRestoreError = null;
        // Signed out at app start: retry a logout's failed FCM unregister.
        unawaited(_flushPendingFcmUnregister());
      }
    } catch (e) {
      if (!superseded() && _user == null) {
        if (ApiService.isSessionRejection(e)) {
          // Signed out (the global session handler also clears it).
          _sessionRestoreFailed = false;
          _sessionRestoreError = null;
          if (token != null) await ApiService.removeTokenIfMatches(token);
        } else if (await ApiService.getToken() == token && !superseded()) {
          _sessionRestoreFailed = true;
          _sessionRestoreError = _cleanError(e);
        }
      }
    } finally {
      if (!superseded()) {
        _authCheckInFlight = false;
        _isAuthChecking = false;
        notifyListeners();
      }
    }
  }

  Future<bool> claimFreeTrial() async {
    _setLoading(true);
    _setError(null);
    try {
      _user = await ApiService.claimFreeTrial();
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(_cleanError(e));
      _setLoading(false);
      return false;
    }
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    _setLoading(true);
    _setError(null);
    try {
      await ApiService.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
        confirmPassword: confirmPassword,
      );
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(_cleanError(e));
      _setLoading(false);
      return false;
    }
  }

  Future<void> _showUpgradeDialog(BuildContext context) async {
    showDialog(
      context: context,
      builder: (context) {
        final localizations = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(localizations.premiumFeatureTitle),
          content: Text(localizations.premiumFeatureDialogContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(localizations.dialogCancel),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/subscription');
              },
              child: Text(localizations.upgrade),
            ),
          ],
        );
      },
    );
  }
}
