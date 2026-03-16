import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/services/fcm_service.dart';
import 'package:frontend/services/notification_event_bus.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class AuthProvider with ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  String? _error;
  bool _isAuthChecking = true;

  // Listens for admin-triggered subscription changes
  StreamSubscription? _subscriptionUpdateSub;

  bool get isAuthChecking => _isAuthChecking;
  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;
  bool get hasClaimedFreeTrial => _user?.hasClaimedFreeTrial ?? false;

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

  Future<void> _sendFCMToken() async {
    try {
      await FCMService().sendTokenToBackend();
    } catch (e) {
      print('⚠️ Could not send FCM token: $e');
    }
  }

  /// Silently re-fetches the user from /api/auth/me and updates state.
  /// Called automatically when a subscription_updated FCM message arrives.
  Future<void> _silentRefreshUser() async {
    print('🔄 AuthProvider: silently refreshing user after subscription update');
    try {
      final refreshed = await ApiService.getCurrentUser();
      _user = refreshed;
      notifyListeners();
      print('✅ AuthProvider: user refreshed — isPremium=${_user?.isPremium}');
    } catch (e) {
      print('⚠️ AuthProvider: silent refresh failed: $e');
      // Don't clear the user or show an error — this is a background refresh
    }
  }

  // ─── Public refresh (can be called manually, e.g. pull-to-refresh) ───────
  Future<void> refreshSubscriptionStatus() async {
    try {
      final status = await ApiService.getSubscriptionStatus();
      if (_user != null) {
        _user = User(
          id: _user!.id,
          name: _user!.name,
          email: _user!.email,
          createdAt: _user!.createdAt,
          subscriptionType: status.subscriptionType,
          subscriptionExpiresAt: status.expiresAt,
          defaultCurrency: _user!.defaultCurrency,
          isVerified: _user!.isVerified,
          hasClaimedFreeTrial: _user!.hasClaimedFreeTrial, // preserve
        );
        notifyListeners();
      }
    } catch (e) {
      print('Error refreshing subscription status: $e');
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
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

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
        _setLoading(false);
        return true;
      }

      _user = authResponse.user;
      await _sendFCMToken();
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

  Future<bool> login({required String email, required String password}) async {
    _setLoading(true);
    _setError(null);
    try {
      final authResponse = await ApiService.login(
        email: email,
        password: password,
      );
      _user = authResponse.user;
      await _sendFCMToken();
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

  Future<bool> deleteAccount() async {
    _setLoading(true);
    _setError(null);
    try {
      await ApiService.deleteAccount();
      _user = null;
      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
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
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

  Future<void> logout() async {
    await ApiService.removeToken();
    _user = null;
    notifyListeners();
  }

  Future<void> checkAuthStatus() async {
    _isAuthChecking = true;
    try {
      _user = await ApiService.getCurrentUser();
      if (_user != null) {
        await _sendFCMToken();
      }
    } catch (e) {
      _user = null;
    } finally {
      _isAuthChecking = false;
      notifyListeners();
    }
  }

  Future<bool> updateSubscription({
    required SubscriptionType subscriptionType,
    DateTime? subscriptionExpiresAt,
  }) async {
    _setLoading(true);
    _setError(null);
    try {
      _user = await ApiService.updateSubscription(
        subscriptionType: subscriptionType,
        subscriptionExpiresAt: subscriptionExpiresAt,
      );
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
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
      _setError(e.toString().replaceAll('Exception: ', ''));
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
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

  Future<void> _showUpgradeDialog(BuildContext context) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Premium Feature'),
        content: Text(
          'This feature requires a premium subscription. Upgrade now to unlock all features!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/subscription');
            },
            child: Text('Upgrade'),
          ),
        ],
      ),
    );
  }
}