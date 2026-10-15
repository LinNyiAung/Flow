import 'package:flutter/material.dart';
import 'package:frontend/services/notification_service.dart';
import '../models/notification.dart';
import '../services/api_service.dart';

class NotificationProvider with ChangeNotifier {
  List<AppNotification> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;
  String? _error;
  final _notificationService = NotificationService();

  /// Bumped on [reset]; responses for an older session are discarded.
  int _generation = 0;

  List<AppNotification> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<AppNotification> get unreadNotifications =>
      _notifications.where((n) => !n.isRead).toList();

  /// Clears all per-user state (called on logout / user switch).
  void reset() {
    _generation++;
    _notifications = [];
    _unreadCount = 0;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  Future<void> fetchNotifications({bool unreadOnly = false}) async {
    _setLoading(true);
    _setError(null);
    final gen = _generation;

    try {
      final oldUnreadCount = _unreadCount;
      final result = await ApiService.getNotifications(unreadOnly: unreadOnly);
      if (gen != _generation) return;
      _notifications = result;
      await fetchUnreadCount();
      if (gen != _generation) return;

      // Show system notifications for new unread notifications
      if (_unreadCount > oldUnreadCount) {
        final newNotifications = _notifications
            .where((n) => !n.isRead)
            .take(_unreadCount - oldUnreadCount)
            .toList();

        for (var notification in newNotifications) {
          await _notificationService.showGoalNotification(notification);
        }
      }

      _setLoading(false);
    } catch (e) {
      if (gen != _generation) return;
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
    }
  }

  Future<void> showSystemNotification(AppNotification notification) async {
    await _notificationService.showGoalNotification(notification);
  }

  Future<void> fetchUnreadCount() async {
    final gen = _generation;
    try {
      final count = await ApiService.getUnreadNotificationCount();
      if (gen != _generation) return;
      _unreadCount = count;
      notifyListeners();
    } catch (e) {
      debugPrint("Error fetching unread count: $e");
    }
  }

  Future<bool> markAsRead(String notificationId) async {
    try {
      await ApiService.markNotificationRead(notificationId);

      final index = _notifications.indexWhere((n) => n.id == notificationId);
      if (index != -1) {
        // copyWith keeps every field (currency included).
        _notifications[index] = _notifications[index].copyWith(isRead: true);
      }

      await fetchUnreadCount();
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      return false;
    }
  }

  Future<bool> markAllAsRead() async {
    try {
      await ApiService.markAllNotificationsRead();

      _notifications =
          _notifications.map((n) => n.copyWith(isRead: true)).toList();

      _unreadCount = 0;
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      return false;
    }
  }

  Future<bool> deleteNotification(String notificationId) async {
    try {
      await ApiService.deleteNotification(notificationId);
      _notifications.removeWhere((n) => n.id == notificationId);
      await fetchUnreadCount();
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
