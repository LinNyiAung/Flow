import 'dart:async';

class NotificationEventBus {
  static final NotificationEventBus _instance = NotificationEventBus._internal();
  factory NotificationEventBus() => _instance;
  NotificationEventBus._internal();

  // Existing: regular notification received (e.g. goal, budget)
  final _notificationController = StreamController<void>.broadcast();
  Stream<void> get onNotificationReceived => _notificationController.stream;
  void notifyReceived() => _notificationController.add(null);

  // NEW: fired when the backend pushes a subscription_updated FCM message
  final _subscriptionController = StreamController<void>.broadcast();
  Stream<void> get onSubscriptionUpdated => _subscriptionController.stream;
  void notifySubscriptionUpdated() => _subscriptionController.add(null);

  // Fired when a custom insight push (custom_insight_ready / custom_insight_failed)
  // arrives in the foreground, so the list and the open report reload.
  final _customInsightController = StreamController<void>.broadcast();
  Stream<void> get onCustomInsightUpdated => _customInsightController.stream;
  void notifyCustomInsightUpdated() => _customInsightController.add(null);

  void dispose() {
    _notificationController.close();
    _subscriptionController.close();
    _customInsightController.close();
  }
}