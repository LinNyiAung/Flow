import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/localization_service.dart';

/// The app is "Toe Pwar" (Myanmar: တိုးပွား); "Flow Finance" was its old name.
void main() {
  test('feedback and test-notification texts name Toe Pwar', () {
    final en = AppLocalizations(const Locale('en'));
    final my = AppLocalizations(const Locale('my'));

    expect(en.feedbackHeaderSubtitle, contains('Toe Pwar'));
    expect(en.testNotificationDes, contains('Toe Pwar'));
    expect(my.feedbackHeaderSubtitle, contains(my.toePwar));
    expect(my.testNotificationDes, contains(my.toePwar));
    for (final s in [en.feedbackHeaderSubtitle, en.testNotificationDes, my.feedbackHeaderSubtitle, my.testNotificationDes]) {
      expect(s, isNot(contains('Flow')));
    }
  });

  test('no user-facing "Flow Finance" / "FlowFinance" is left in the app', () {
    final offenders = <String>[];
    final pattern = RegExp(r'flow\s*finance', caseSensitive: false);
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) offenders.add('${f.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(offenders, isEmpty);
  });
}
