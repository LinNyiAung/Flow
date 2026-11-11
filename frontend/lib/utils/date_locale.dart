import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// The app's locale for [DateFormat] (Myanmar month names in Myanmar), or
/// null — intl's default English — when that locale's date data isn't
/// loaded. In the app GlobalMaterialLocalizations always loads it; widget
/// tests that leave that delegate out would otherwise throw.
String? dateLocaleOf(BuildContext context) {
  final tag = Localizations.localeOf(context).toLanguageTag();
  try {
    return DateFormat.localeExists(tag) ? tag : null;
  } catch (_) {
    // intl throws (rather than answering false) before any date data is loaded.
    return null;
  }
}
