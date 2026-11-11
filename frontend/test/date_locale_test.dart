import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/utils/date_locale.dart';

void main() {
  setUpAll(() async {
    // Loads intl's date data, as GlobalMaterialLocalizations does in the app.
    await GlobalMaterialLocalizations.delegate.load(const Locale('my'));
  });

  test('an empty country code (the app\'s supportedLocales) still gives "my"', () {
    // On the web, Locale('my', '').toLanguageTag() is "my-"; the helper must
    // not depend on it.
    expect(dateLocaleFor(const Locale('my', '')), 'my');
    expect(dateLocaleFor(const Locale('my')), 'my');
    expect(dateLocaleFor(const Locale('en', '')), 'en');
  });

  test('a locale intl has no date data for falls back to null (English)', () {
    expect(dateLocaleFor(const Locale('xx', '')), isNull);
  });
}
