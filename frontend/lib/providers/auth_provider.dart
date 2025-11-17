import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class AuthProvider with ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;
  
  // NEW: Premium status getters
  bool get isPremium => _user?.isPremium ?? false;
  SubscriptionType get subscriptionType => _user?.subscriptionType ?? SubscriptionType.free;
  DateTime? get subscriptionExpiresAt => _user?.subscriptionExpiresAt;

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
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
      _user = authResponse.user;
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final authResponse = await ApiService.login(
        email: email,
        password: password,
      );
      _user = authResponse.user;
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
    try {
      _user = await ApiService.getCurrentUser();
      notifyListeners();
    } catch (e) {
      _user = null;
      notifyListeners();
    }
  }

  // NEW: Subscription management methods
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

  Future<void> refreshSubscriptionStatus() async {
    try {
      final status = await ApiService.getSubscriptionStatus();
      if (_user != null) {
        // Update user with latest subscription info
        _user = User(
          id: _user!.id,
          name: _user!.name,
          email: _user!.email,
          createdAt: _user!.createdAt,
          subscriptionType: status.subscriptionType,
          subscriptionExpiresAt: status.expiresAt,
        );
        notifyListeners();
      }
    } catch (e) {
      print('Error refreshing subscription status: $e');
    }
  }

  // NEW: Helper method to check premium access
  Future<bool> canAccessPremiumFeature(BuildContext context) async {
    if (isPremium) return true;
    
    // Show upgrade dialog
    await _showUpgradeDialog(context);
    return false;
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
              // Navigate to subscription/payment screen
              Navigator.pushNamed(context, '/subscription');
            },
            child: Text('Upgrade'),
          ),
        ],
      ),
    );
  }
}