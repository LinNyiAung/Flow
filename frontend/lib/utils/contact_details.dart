import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// The owner's own email and Viber number (`owner_contact` of `GET /api/plan`),
/// as the owner typed them on the admin Plans page. Both are optional and an
/// unset one is the empty string.
class OwnerContact {
  final String email;

  /// `+` and digits (the server normalises it).
  final String viber;

  const OwnerContact({this.email = '', this.viber = ''});

  static const OwnerContact none = OwnerContact();

  bool get hasEmail => email.isNotEmpty;
  bool get hasViber => viber.isNotEmpty;

  /// Nothing to show.
  bool get isEmpty => !hasEmail && !hasViber;

  factory OwnerContact.fromJson(dynamic json) {
    if (json is! Map) return none;
    String text(String key) {
      final value = json[key];
      return value is String ? value.trim() : '';
    }

    return OwnerContact(email: text('email'), viber: text('viber'));
  }
}

/// A Viber number the way the server stores it: `+` and 8 to 15 digits.
///
/// The same rule as the server (`plans/contact.py`): spaces, dashes, dots and
/// parentheses are dropped, one leading `+` is allowed and a Myanmar local
/// number (`09…`) becomes `+959…`. Returns '' for an empty input (no number)
/// and null when [input] is not a number.
String? normalizeViberNumber(String input) {
  final raw = input.replaceAll(RegExp(r'[\s\-.()]'), '');
  if (raw.isEmpty) return '';
  final number = raw.startsWith('09') ? '+95${raw.substring(1)}' : raw;
  return RegExp(r'^\+[0-9]{8,15}$').hasMatch(number) ? number : null;
}

/// `viber://chat?number=%2B959…`: opens a chat with [number] in Viber.
Uri viberChatUri(String number) =>
    Uri(scheme: 'viber', host: 'chat', queryParameters: {'number': number});

/// `mailto:` [email].
Uri mailtoUri(String email) => Uri(scheme: 'mailto', path: email);

/// How a contact link is opened. A test replaces it; a false answer or a
/// thrown error means it could not be opened.
Future<bool> Function(Uri uri) contactLinkLauncher =
    (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// Opens [uri]. When nothing can open it (no Viber, no email app), copies
/// [fallbackText] to the clipboard and returns false so the caller can say so.
Future<bool> openContactLink(Uri uri, String fallbackText) async {
  var opened = false;
  try {
    opened = await contactLinkLauncher(uri);
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    await Clipboard.setData(ClipboardData(text: fallbackText));
  }
  return opened;
}
