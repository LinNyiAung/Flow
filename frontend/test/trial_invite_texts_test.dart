import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/app_config.dart';
import 'package:frontend/services/localization_service.dart';

void main() {
  group('AppConfig numbers', () {
    test('missing numbers read as 30 / 14', () {
      final c = AppConfig.fromJson({});
      expect(c.trialDays, 30);
      expect(c.inviteDays, 14);
      expect(AppConfig.open.trialDays, 30);
      expect(AppConfig.open.inviteDays, 14);
    });

    test('server numbers are used', () {
      final c = AppConfig.fromJson({
        'numbers': {'trial_days': 45, 'invite_days': 3},
      });
      expect(c.trialDays, 45);
      expect(c.inviteDays, 3);
    });

    test('bad values fall back', () {
      final c = AppConfig.fromJson({
        'numbers': {'trial_days': '45', 'invite_days': 0},
      });
      expect(c.trialDays, 30);
      expect(c.inviteDays, 14);
      final d = AppConfig.fromJson({
        'numbers': {'trial_days': 400, 'invite_days': 3.5},
      });
      expect(d.trialDays, 30);
      expect(d.inviteDays, 14);
    });
  });

  group('trial and invite texts', () {
    final en = AppLocalizations(const Locale('en'));
    final my = AppLocalizations(const Locale('my'));

    test('English', () {
      expect(en.trialFreeCaps(30), 'ONE MONTH FREE');
      expect(en.trialFreeCaps(45), '45 DAYS FREE');
      expect(en.claimTrialFree(30), 'Claim 1 month free');
      expect(en.claimTrialFree(45), 'Claim 45 days free');
      expect(en.trialFreeAccessGranted(30), contains('1 month'));
      expect(en.trialFreeAccessGranted(45), contains('45 days'));
      expect(en.familyInviteIntroDays(14), endsWith('The invitation lasts 14 days.'));
    });

    test('Myanmar uses Myanmar digits', () {
      expect(my.claimTrialFree(45), '၄၅ ရက် အခမဲ့ ရယူရန်');
      expect(my.trialFreeCaps(45), '၄၅ ရက် အခမဲ့');
      expect(my.trialFreeAccessGranted(45), contains('၄၅ ရက်'));
      expect(my.familyInviteIntroDays(14), endsWith('၁၄ ရက် ခံပါတယ်။'));
      expect(my.claimTrialFree(30), my.claimOneMonthFree);
    });
  });
}
