import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// The app's locale for [DateFormat] (Myanmar month names in Myanmar), or
/// null — intl's default English — when that locale's date data isn't
/// loaded. In the app GlobalMaterialLocalizations always loads it; widget
/// tests that leave that delegate out would otherwise throw.
String? dateLocaleOf(BuildContext context) => dateLocaleFor(Localizations.localeOf(context));

/// [dateLocaleOf] for a given [locale]. Builds the intl tag itself: on the web
/// `Locale('my', '').toLanguageTag()` is "my-" (the engine only skips a null
/// country, not an empty one), which intl doesn't know, so every date fell
/// back to English there.
String? dateLocaleFor(Locale locale) {
  final country = locale.countryCode;
  final tag = country == null || country.isEmpty ? locale.languageCode : '${locale.languageCode}_$country';
  try {
    return DateFormat.localeExists(tag) ? tag : null;
  } catch (_) {
    // intl throws (rather than answering false) before any date data is loaded.
    return null;
  }
}
