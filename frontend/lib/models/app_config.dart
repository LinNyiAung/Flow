import 'package:frontend/utils/date_parsing.dart';

/// The owner's notice for the top of the dashboard (`announcement` of
/// `GET /api/app/config`), already in the person's language.
class Announcement {
  /// Which announcement this is.
  final String id;

  /// When it was last edited; with [id], what a device remembers when the
  /// person closes it (an edit shows it again).
  final String updatedAt;

  /// `info` or `warning`.
  final String style;
  final String text;

  /// An `http(s)` link, or null.
  final String? linkUrl;
  final String linkLabel;

  const Announcement({
    required this.id,
    required this.updatedAt,
    required this.style,
    required this.text,
    this.linkUrl,
    this.linkLabel = '',
  });

  /// Null when [json] is not a usable announcement (no id or no text).
  static Announcement? tryParse(dynamic json) {
    if (json is! Map) return null;
    final id = json['id'];
    final text = json['text'];
    if (id == null || text is! String || text.isEmpty) return null;
    final link = json['link_url'];
    final style = json['style'];
    return Announcement(
      id: id.toString(),
      updatedAt: json['updated_at']?.toString() ?? '',
      style: style == 'warning' ? 'warning' : 'info',
      text: text,
      linkUrl: link is String && link.isNotEmpty ? link : null,
      linkLabel: json['link_label'] is String ? json['link_label'] as String : '',
    );
  }
}

/// What the owner has switched in the admin panel (`GET /api/app/config`):
/// maintenance, the paused features and the announcement to show.
class AppConfig {
  final bool maintenanceOn;
  final String maintenanceMessage;

  /// When maintenance should end, in local time; null when not announced.
  final DateTime? backBy;

  /// True when this person may still use the app during maintenance (a tester).
  final bool canEnter;

  /// The paused switches (`chat`, `signups`, ...) with their message in the
  /// person's language; a switch that is not listed is not paused.
  final Map<String, String> paused;

  final Announcement? announcement;

  const AppConfig({
    required this.maintenanceOn,
    required this.maintenanceMessage,
    required this.backBy,
    required this.canEnter,
    required this.paused,
    required this.announcement,
  });

  /// Nothing paused, no maintenance: also what the app assumes when the
  /// config cannot be read.
  static const AppConfig open = AppConfig(
    maintenanceOn: false,
    maintenanceMessage: '',
    backBy: null,
    canEnter: true,
    paused: {},
    announcement: null,
  );

  /// Unknown keys are ignored; anything missing or malformed reads as "open".
  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final maintenance = json['maintenance'];
    final m = maintenance is Map ? maintenance : const {};
    final pausedJson = json['paused'];
    final paused = <String, String>{};
    if (pausedJson is Map) {
      pausedJson.forEach((key, value) {
        if (key is String && value is String) paused[key] = value;
      });
    }
    return AppConfig(
      maintenanceOn: m['on'] == true,
      maintenanceMessage: m['message'] is String ? m['message'] as String : '',
      backBy: parseInstantOrNull(m['back_by']),
      canEnter: m['can_enter'] != false,
      paused: Map.unmodifiable(paused),
      announcement: Announcement.tryParse(json['announcement']),
    );
  }
}
