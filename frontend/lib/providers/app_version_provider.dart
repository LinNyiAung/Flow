import 'package:flutter/material.dart';
import '../models/app_version.dart';
import '../services/api_service.dart';

class AppVersionProvider with ChangeNotifier {
  VersionCheckResponse? _versionCheck;
  bool _isLoading = false;
  bool _isChecked = false; // prevent rechecking multiple times per session

  VersionCheckResponse? get versionCheck => _versionCheck;
  bool get isLoading => _isLoading;
  bool get isChecked => _isChecked;

  /// True if there's a forced update the user has not bypassed yet.
  bool get requiresForceUpdate =>
      _versionCheck != null &&
      !_versionCheck!.isUpToDate &&
      _versionCheck!.forceUpdate;

  /// True if there's a soft (optional) update available.
  bool get hasOptionalUpdate =>
      _versionCheck != null &&
      !_versionCheck!.isUpToDate &&
      !_versionCheck!.forceUpdate;

  Future<void> checkVersion({
    required String currentVersion,
    required String platform, // 'android' or 'ios'
  }) async {
    if (_isLoading) return;

    _isLoading = true;
    notifyListeners();

    try {
      _versionCheck = await ApiService.checkAppVersion(
        currentVersion: currentVersion,
        platform: platform,
      );
      _isChecked = true;
    } catch (e) {
      // On failure, assume up to date — never block the user due to a network error
      print('⚠️ Version check failed: $e');
      _versionCheck = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void reset() {
    _versionCheck = null;
    _isChecked = false;
    notifyListeners();
  }
}
