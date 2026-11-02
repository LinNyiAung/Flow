import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/notification_event_bus.dart';

/// The signed-in user's plan and what is left of each AI allowance this
/// period (`GET /api/plan`).
///
/// Loaded when the user signs in (the app root calls [refresh]) and
/// refreshed after every AI action ([ApiService.onPlanUsageChanged]), when the
/// server pushes `subscription_updated` (an admin changed the plan) and when
/// the web tab comes back into view. A failed refresh keeps the numbers that
/// are already on screen.
class PlanProvider with ChangeNotifier {
  PlanStatus? _status;
  bool _isLoading = false;
  String? _error;

  /// Bumped by [reset] and by each started load: a response for an older
  /// generation (previous user) is dropped.
  int _generation = 0;

  /// A refresh was requested while one was in flight: run once more after it.
  bool _again = false;

  StreamSubscription<void>? _subscriptionUpdateSub;

  /// Where the plan comes from; [ApiService.getPlanStatus] unless a test
  /// supplies its own.
  final Future<PlanStatus> Function() _loader;

  PlanProvider({Future<PlanStatus> Function()? loader})
      : _loader = loader ?? ApiService.getPlanStatus {
    // An admin changed the plan: the new limits apply at once.
    _subscriptionUpdateSub =
        NotificationEventBus().onSubscriptionUpdated.listen((_) => refresh());
  }

  /// Null until the first load succeeds.
  PlanStatus? get status => _status;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// This feature's allowance, or null while the plan is not loaded.
  FeatureAllowance? feature(String key) => _status?.feature(key);

  /// True when [key] is locked on the user's plan. While the plan is not
  /// loaded yet the answer is [whenUnknown].
  bool isLocked(String key, {bool whenUnknown = false}) {
    final allowance = _status?.feature(key);
    return allowance == null ? whenUnknown : allowance.isLocked;
  }

  /// Clears all per-user state (called on logout / user switch).
  void reset() {
    _generation++;
    _again = false;
    _status = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  /// Reloads the plan. Silent: a failure keeps the previous status. Does
  /// nothing when nobody is signed in.
  Future<void> refresh() async {
    if (await ApiService.getToken() == null) return;
    if (_isLoading) {
      _again = true;
      return;
    }
    final generation = ++_generation;
    _isLoading = true;
    notifyListeners();
    try {
      final result = await _loader();
      if (generation != _generation) return;
      _status = result;
      _error = null;
    } catch (e) {
      if (generation != _generation) return;
      _error = e.toString().replaceAll('Exception: ', '');
      debugPrint('PlanProvider: refresh failed: $e');
    }
    _isLoading = false;
    notifyListeners();
    if (_again) {
      _again = false;
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    _subscriptionUpdateSub?.cancel();
    super.dispose();
  }
}
