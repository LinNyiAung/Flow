import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// The owner's own contact details (`owner_contact` of `GET /api/plan`) as
/// the server stores them from the admin Plans page: email, Viber number,
/// Telegram number or username, Facebook page link and Messenger link. Each is
/// optional and an unset one is the empty string.
class OwnerContact {
  final String email;

  /// `+` and digits (the server normalises it).
  final String viber;

  /// `+` and digits (a number) or `@name` (a username); see
  /// [normalizeTelegram] and [telegramUri].
  final String telegram;

  /// An `https://` link to the owner's Facebook page; see
  /// [normalizeFacebookUrl].
  final String facebook;

  /// An `https://` m.me or messenger.com link; see [normalizeMessengerUrl].
  final String messenger;

  const OwnerContact({
    this.email = '',
    this.viber = '',
    this.telegram = '',
    this.facebook = '',
    this.messenger = '',
  });

  static const OwnerContact none = OwnerContact();

  bool get hasEmail => email.isNotEmpty;
  bool get hasViber => viber.isNotEmpty;
  bool get hasTelegram => telegram.isNotEmpty;
  bool get hasFacebook => facebook.isNotEmpty;
  bool get hasMessenger => messenger.isNotEmpty;

  /// Nothing to show.
  bool get isEmpty =>
      !hasEmail && !hasViber && !hasTelegram && !hasFacebook && !hasMessenger;

  factory OwnerContact.fromJson(dynamic json) {
    if (json is! Map) return none;
    String text(String key) {
      final value = json[key];
      return value is String ? value.trim() : '';
    }

    return OwnerContact(
      email: text('email'),
      viber: text('viber'),
      telegram: text('telegram'),
      facebook: text('facebook'),
      messenger: text('messenger'),
    );
  }
}

final _separators = RegExp(r'[\s\-.()]');

/// A Viber number the way the server stores it: `+` and 8 to 15 digits.
///
/// The same rule as the server (`plans/contact.py`): spaces, dashes, dots and
/// parentheses are dropped, one leading `+` is allowed and a Myanmar local
/// number (`09…`) becomes `+959…`. Returns '' for an empty input (no number)
/// and null when [input] is not a number.
String? normalizeViberNumber(String input) {
  final raw = input.replaceAll(_separators, '');
  if (raw.isEmpty) return '';
  final number = raw.startsWith('09') ? '+95${raw.substring(1)}' : raw;
  return RegExp(r'^\+[0-9]{8,15}$').hasMatch(number) ? number : null;
}

final _telegramName = RegExp(
  r'^(?:(?:https?://)?(?:t|telegram)\.me/|@)?([a-z][a-z0-9_]{4,31})$',
  caseSensitive: false,
);

/// A Telegram contact the way the server stores it: a number (`+` and 8 to 15
/// digits) or a username (`@name`, in the case it was typed).
///
/// The same rule as the server (`plans/contact.py`): an input that is only
/// digits once spaces, dashes, dots and parentheses are dropped (with an
/// optional leading `+`) is a number and follows [normalizeViberNumber]
/// (`09…` becomes `+959…`). Anything else is a username: `@name`, `name`, or
/// a `t.me/name` / `telegram.me/name` link with or without `http(s)://`; the
/// name is 5 to 32 of a-z A-Z 0-9 _ and starts with a letter. Returns '' for
/// an empty input and null when [input] is neither.
String? normalizeTelegram(String input) {
  final text = input.trim();
  final compact = text.replaceAll(_separators, '');
  if (compact.isEmpty) return '';
  if (RegExp(r'^\+?[0-9]+$').hasMatch(compact)) {
    return normalizeViberNumber(text);
  }
  final match = _telegramName.firstMatch(text);
  return match == null ? null : '@${match.group(1)}';
}

/// The most characters a Facebook or Messenger link may have (as typed and as
/// stored).
const maxContactLinkLength = 300;

const facebookHosts = [
  'facebook.com',
  'www.facebook.com',
  'm.facebook.com',
  'web.facebook.com',
  'fb.com',
  'www.fb.com',
  'fb.me',
];
const messengerHosts = ['m.me', 'messenger.com', 'www.messenger.com'];

/// The same rule as the server's `_normalize_link`: an http(s) link (or one
/// typed without a scheme) on one of [hosts] with a page path becomes
/// `https://` + the host in lower case + the path, query and fragment as
/// typed. Returns '' for an empty input and null for any other host, no path,
/// a user name or a port, spaces, another scheme, or more than
/// [maxContactLinkLength] characters.
String? _normalizeLink(String input, List<String> hosts) {
  final text = input.trim();
  if (text.isEmpty) return '';
  if (text.length > maxContactLinkLength || RegExp(r'\s').hasMatch(text)) {
    return null;
  }
  var rest = text;
  final scheme = RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*)://').firstMatch(text);
  if (scheme != null) {
    if (!const ['http', 'https'].contains(scheme.group(1)!.toLowerCase())) {
      return null;
    }
    rest = text.substring(scheme.end);
  }
  final cut = rest.indexOf(RegExp(r'[/?#]'));
  final host = (cut < 0 ? rest : rest.substring(0, cut)).toLowerCase();
  final tail = cut < 0 ? '' : rest.substring(cut);
  // A user name (user@host) or a port (host:443) makes it differ from every
  // allowed host.
  if (!hosts.contains(host)) return null;
  final path = tail.split(RegExp(r'[?#]')).first;
  if (path.isEmpty || path == '/') return null;
  final url = 'https://$host$tail';
  return url.length > maxContactLinkLength ? null : url;
}

/// A Facebook page link the way the server stores it (`https://`, on
/// facebook.com, www./m./web.facebook.com, fb.com, www.fb.com or fb.me, with
/// a page path); '' for an empty input, null when it is not one.
String? normalizeFacebookUrl(String input) =>
    _normalizeLink(input, facebookHosts);

/// A Messenger link the way the server stores it (`https://`, on m.me,
/// messenger.com or www.messenger.com, with a page path); '' for an empty
/// input, null when it is not one.
String? normalizeMessengerUrl(String input) =>
    _normalizeLink(input, messengerHosts);

/// A stored link as the app shows it: without the leading `https://`
/// (`facebook.com/yourpage`).
String contactLinkDisplay(String url) =>
    url.startsWith('https://') ? url.substring('https://'.length) : url;

/// `viber://chat?number=%2B959…`: opens a chat with [number] in Viber.
Uri viberChatUri(String number) =>
    Uri(scheme: 'viber', host: 'chat', queryParameters: {'number': number});

/// `mailto:` [email].
Uri mailtoUri(String email) => Uri(scheme: 'mailto', path: email);

/// The t.me link of a stored Telegram contact: `https://t.me/+959…` for a
/// number, `https://t.me/name` for `@name`.
Uri telegramUri(String stored) {
  final target = stored.startsWith('@') ? stored.substring(1) : stored;
  return Uri.parse('https://t.me/$target');
}

/// The stored Facebook page link ([stored] is already `https://…`).
Uri facebookUri(String stored) => _linkUri(stored);

/// The stored Messenger link ([stored] is already `https://…`).
Uri messengerUri(String stored) => _linkUri(stored);

/// [url] as a Uri; one Dart cannot parse as typed (a stray `%`, which the
/// server keeps as typed) is percent-encoded first instead of throwing.
Uri _linkUri(String url) => Uri.tryParse(url) ?? Uri.parse(Uri.encodeFull(url));

/// How a contact link is opened. A test replaces it; a false answer or a
/// thrown error means it could not be opened.
Future<bool> Function(Uri uri) contactLinkLauncher =
    (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// Opens [uri]. When nothing can open it (no Viber, no email app, no browser),
/// copies [fallbackText] to the clipboard and returns false so the caller can
/// say so.
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
