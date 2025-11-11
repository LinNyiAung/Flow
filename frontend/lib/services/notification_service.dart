import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import '../models/notification.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _isInitialized = true;
    print('✅ Notification service initialized');
  }

  Future<bool> requestPermissions() async {
    if (await Permission.notification.isGranted) {
      return true;
    }

    final status = await Permission.notification.request();
    return status.isGranted;
  }

  void _onNotificationTapped(NotificationResponse response) {
    print('Notification tapped: ${response.payload}');
    // Handle notification tap - you can add navigation logic here
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    required NotificationType type,
    String? payload,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Check permissions
    if (!await requestPermissions()) {
      print('⚠️ Notification permissions not granted');
      return;
    }

    final Color color = _getNotificationColor(type);

    final androidDetails = AndroidNotificationDetails(
      'goals_channel',
      'Goal Notifications',
      channelDescription: 'Notifications about your financial goals',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: Color.fromARGB(255, color.red, color.green, color.blue),
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(body),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payload,
    );

    print('✅ System notification shown: $title');
  }

  Future<void> showGoalNotification(AppNotification notification) async {
    await showNotification(
      id: notification.id.hashCode,
      title: notification.title,
      body: notification.message,
      type: notification.type,
      payload: notification.goalId,
    );
  }

  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

Color _getNotificationColor(NotificationType type) {
  switch (type) {
    case NotificationType.goal_achieved:
      return Color(0xFFFFD700); // Gold
    case NotificationType.goal_progress:
      return Color(0xFF4CAF50); // Green
    case NotificationType.goal_milestone:
      return Color(0xFFFF9800); // Orange
    case NotificationType.goal_approaching_date:
      return Color(0xFF2196F3); // Blue
    case NotificationType.budget_started:           // ADD THIS
      return Color(0xFF4CAF50); // Green
    case NotificationType.budget_ending_soon:       // ADD THIS
      return Color(0xFFFF9800); // Orange
    case NotificationType.budget_threshold:         // ADD THIS
      return Color(0xFFFF9800); // Orange
    case NotificationType.budget_exceeded:          // ADD THIS
      return Color(0xFFFF5722); // Red
    case NotificationType.budget_auto_created:      // ADD THIS
      return Color(0xFF667eea); // Purple
    case NotificationType.budget_now_active:        // ADD THIS
      return Color(0xFF4CAF50); // Green
  }
}
}