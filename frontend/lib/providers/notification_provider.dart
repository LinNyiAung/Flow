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

  List<AppNotification> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<AppNotification> get unreadNotifications =>
      _notifications.where((n) => !n.isRead).toList();

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

    try {
      final oldUnreadCount = _unreadCount;
      _notifications = await ApiService.getNotifications(unreadOnly: unreadOnly);
      await fetchUnreadCount();
      
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
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
    }
  }


    Future<void> showSystemNotification(AppNotification notification) async {
    await _notificationService.showGoalNotification(notification);
  }

  Future<void> fetchUnreadCount() async {
    try {
      _unreadCount = await ApiService.getUnreadNotificationCount();
      notifyListeners();
    } catch (e) {
      print("Error fetching unread count: $e");
    }
  }

  Future<bool> markAsRead(String notificationId) async {
    try {
      await ApiService.markNotificationRead(notificationId);

      final index = _notifications.indexWhere((n) => n.id == notificationId);
      if (index != -1) {
        _notifications[index] = AppNotification(
          id: _notifications[index].id,
          userId: _notifications[index].userId,
          type: _notifications[index].type,
          title: _notifications[index].title,
          message: _notifications[index].message,
          goalId: _notifications[index].goalId,
          goalName: _notifications[index].goalName,
          createdAt: _notifications[index].createdAt,
          isRead: true,
        );
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
      
      _notifications = _notifications.map((n) => AppNotification(
        id: n.id,
        userId: n.userId,
        type: n.type,
        title: n.title,
        message: n.message,
        goalId: n.goalId,
        goalName: n.goalName,
        createdAt: n.createdAt,
        isRead: true,
      )).toList();

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