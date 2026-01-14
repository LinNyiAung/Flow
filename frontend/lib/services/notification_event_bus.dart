import 'dart:async';

class NotificationEventBus {
  static final NotificationEventBus _instance = NotificationEventBus._internal();
  factory NotificationEventBus() => _instance;
  NotificationEventBus._internal();

  final _controller = StreamController<void>.broadcast();
  
  Stream<void> get onNotificationReceived => _controller.stream;
  
  void notifyReceived() {
    _controller.add(null);
  }
  
  void dispose() {
    _controller.close();
  }
}