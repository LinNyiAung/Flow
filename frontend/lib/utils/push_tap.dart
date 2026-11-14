import 'package:frontend/models/notification.dart';

/// A tapped push: what to open ([type], [goalId]) and in which book
/// ([family]: the push carried `book: family`).
typedef PushTap = ({String type, String? goalId, bool family});

/// The payload of the local notification shown for a push received while the
/// app is open: `type|goal_id|book` (empty parts for none), so a tap opens it
/// like a tapped push. Null for a push whose tap opens nothing.
String? pushTapPayload(Object? type, Object? goalId, Object? book) {
  if (type is! String || !notificationOpensSomething(type)) return null;
  return '$type|${goalId is String ? goalId : ''}|${book == 'family' ? 'family' : ''}';
}

/// Reads a [pushTapPayload] back (the older `type|goal_id` custom insight
/// payload too). Null for anything else, such as a plain notification id.
PushTap? parsePushTapPayload(String? payload) {
  if (payload == null) return null;
  final parts = payload.split('|');
  final type = parts.first;
  if (!notificationOpensSomething(type)) return null;
  final id = parts.length > 1 ? parts[1] : '';
  return (type: type, goalId: id.isEmpty ? null : id, family: parts.length > 2 && parts[2] == 'family');
}
