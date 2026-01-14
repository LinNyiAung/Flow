import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:frontend/models/notification.dart';
import 'package:frontend/services/api_service.dart';
import 'dart:io' show Platform;

import 'package:frontend/services/notification_event_bus.dart';

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('📨 Background message received: ${message.notification?.title}');
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  String? _fcmToken;

  String? get fcmToken => _fcmToken;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize local notifications
      await _initializeLocalNotifications();

      // Request permission
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ FCM permission granted');

        // Get FCM token
        _fcmToken = await _fcm.getToken();
        print('📱 FCM Token: $_fcmToken');

        // Send token to backend
        if (_fcmToken != null) {
          await _sendTokenToBackend(_fcmToken!);
        }

        // Listen for token refresh
        _fcm.onTokenRefresh.listen((newToken) {
          _fcmToken = newToken;
          print('🔄 FCM Token refreshed: $newToken');
          _sendTokenToBackend(newToken);
        });

        // Handle foreground messages
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

        // Handle background message clicks
        FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

        // Check if app was opened from a terminated state
        RemoteMessage? initialMessage = await _fcm.getInitialMessage();
        if (initialMessage != null) {
          _handleMessageOpenedApp(initialMessage);
        }

        // Set background message handler
        FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler,
        );

        _isInitialized = true;
        print('✅ FCM Service initialized successfully');
      } else {
        print('⚠️ FCM permission denied');
      }
    } catch (e) {
      print('❌ FCM initialization error: $e');
    }
  }

  Future<void> _initializeLocalNotifications() async {
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

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      await ApiService.updateFCMToken(token);
      print('✅ FCM token sent to backend');
    } catch (e) {
      print('❌ Failed to send FCM token to backend: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    print('📨 Foreground message: ${message.notification?.title}');
    _showLocalNotification(message);
    // NEW: Notify via event bus
    NotificationEventBus().notifyReceived();
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    print('📨 Message opened app: ${message.notification?.title}');
    // TODO: Navigate to appropriate screen based on message.data
    _handleNotificationNavigation(message.data);
  }

  void _onNotificationTapped(NotificationResponse response) {
    print('📨 Local notification tapped: ${response.payload}');
    // TODO: Parse payload and navigate
  }

  void _handleNotificationNavigation(Map<String, dynamic> data) {
    // This will be called when user taps notification
    // You can add navigation logic here later
    final notificationType = data['type'];
    final goalId = data['goal_id'];
    final notificationId = data['notification_id'];
    
    print('Navigate to: type=$notificationType, goalId=$goalId');
    // TODO: Implement navigation in your main app
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    
    if (notification == null) return;

    // Parse notification type from data
    final notificationType = message.data['type'] ?? 'goal_progress';
    final color = _getNotificationColor(notificationType);

    final androidDetails = AndroidNotificationDetails(
      'flow_finance_notifications',
      'Flow Finance',
      channelDescription: 'Financial notifications from Flow Finance',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: color,
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(
        notification.body ?? '',
        contentTitle: notification.title,
      ),
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

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      notificationDetails,
      payload: message.data['notification_id'],
    );
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'goal_achieved':
        return Color(0xFFFFD700);
      case 'goal_progress':
      case 'budget_started':
      case 'budget_now_active':
        return Color(0xFF4CAF50);
      case 'goal_milestone':
      case 'budget_threshold':
      case 'large_transaction':
        return Color(0xFFFF9800);
      case 'budget_exceeded':
      case 'unusual_spending':
        return Color(0xFFFF5722);
      case 'goal_approaching_date':
      case 'payment_reminder':
        return Color(0xFF2196F3);
      default:
        return Color(0xFF667eea);
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    await _fcm.subscribeToTopic(topic);
    print('✅ Subscribed to topic: $topic');
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    await _fcm.unsubscribeFromTopic(topic);
    print('✅ Unsubscribed from topic: $topic');
  }
}