import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/screens/budgets/budgets_screen.dart';
import 'package:frontend/screens/goals/goals_screen.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:frontend/screens/notifications/notifications_screen.dart';
import 'package:frontend/screens/settings/change_password_screen.dart';
import 'package:frontend/screens/settings/edit_profile_screen.dart';
import 'package:frontend/screens/settings/feedback_screen.dart';
import 'package:frontend/screens/settings/notification_settings_screen.dart';
import 'package:frontend/screens/settings/settings_screen.dart';
import 'package:frontend/screens/subscription/subscription_screen.dart';
import 'package:frontend/screens/transactions/transactions_list_screen.dart';

import '../support/accounts.dart';
import '../support/harness.dart';

Future<void> openNotifications() async {
  step('open notifications (bell)');
  await tap(find.byIcon(Icons.notifications_rounded).first);
  await waitFor(find.byType(NotificationsScreen));
  await settle(2000);
}

Future<void> openSettings() async {
  await drawerGo(L.settings);
  await waitFor(find.byType(SettingsScreen));
  await settle(800);
}

Future<void> openSettingsRow(String title) async {
  step('settings → $title');
  await scrollTo(find.text(title), maxSwipes: 10);
  await tap(find.text(title).first);
}

void notificationFlows() {
  group('11 Notifications', () {
    e2eTest('notifications: list, tap routes, mark all read, swipe delete', (t) async {
      await login(premium);
      await openNotifications();
      for (final title in ['Large transaction', 'Recurring rent added', 'Welcome to the new version']) {
        check(await scrollTo(find.text(title), maxSwipes: 4), 'Notifications: "$title" not listed');
      }
      for (final title in ['Recurring rent added', 'Large transaction']) {
        step('tap "$title"');
        await scrollTo(find.text(title), maxSwipes: 4);
        await tap(find.text(title).first);
        final ok = await waitFor(find.byType(TransactionsListScreen), timeout: const Duration(seconds: 10), orNull: true);
        check(ok, 'Tapping "$title" did not open the transactions list');
        if (ok) {
          await settle(2000);
          await back();
          await waitFor(find.byType(NotificationsScreen));
          await settle(1000);
        }
      }
      step('tap goal notification (no goal id)');
      await scrollTo(find.text('Goal achieved: New laptop'), maxSwipes: 4);
      await tap(find.text('Goal achieved: New laptop').first);
      await settle(1500);
      check(find.byType(NotificationsScreen).evaluate().isNotEmpty, 'Tapping a goal notification without goal id left the list unexpectedly');
      step('mark all read');
      final markAll = find.text(L.markAllRead);
      if (await waitFor(markAll, timeout: const Duration(seconds: 5), orNull: true)) {
        await tap(markAll);
        await expectSoon(find.text(L.markedAsRead), 'Mark all read: no confirmation snackbar');
        await settle(800);
        check(find.text(L.markAllRead).evaluate().isEmpty, '"Mark all read" still shown after marking all read');
      } else {
        appBug('"Mark all read" button not shown although notifications were unread');
      }
      step('swipe delete');
      final victim = find.text('Welcome to the new version');
      await scrollTo(victim, maxSwipes: 4);
      await t.drag(victim.first, const Offset(-500, 0));
      await settle(2500);
      await expectSoon(find.text(L.notificationDeleted), 'Swipe delete: no "notification deleted" snackbar', timeout: const Duration(seconds: 5));
      check(find.text('Welcome to the new version').evaluate().isEmpty, 'Swiped notification still listed');
      step('back to home, bell cleared');
      await back();
      await waitFor(find.byType(HomeScreen));
      await settle(2000);
      final bellStack = find.ancestor(of: find.byIcon(Icons.notifications_rounded), matching: find.byType(Stack));
      final badgeTexts = find
          .descendant(of: bellStack.first, matching: find.byType(Text))
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .toList();
      check(badgeTexts.isEmpty, 'Bell badge still shows $badgeTexts after marking all read');
      step('server state');
      final token = await apiToken(premium);
      final list = await apiGet(token, '/api/notifications?limit=50');
      final items = list is List ? list : (list['notifications'] as List? ?? const []);
      check(!items.any((n) => n['title'] == 'Welcome to the new version'), 'Swiped notification still exists server-side');
    });

    e2eTest('notifications: settings toggles', (t) async {
      await login(premium);
      await openSettings();
      await openSettingsRow(L.notificationSettings);
      await waitFor(find.byType(NotificationSettingsScreen));
      await settle(2500);
      final switches = find.byType(Switch);
      await waitFor(switches);
      final n = switches.evaluate().length;
      check(n > 3, 'Notification settings: only $n switches');
      step('toggle a type switch off and on');
      await scrollTo(find.text(L.progressUpdates));
      final row = find.ancestor(of: find.text(L.progressUpdates), matching: find.byType(Row)).first;
      final sw = find.descendant(of: row, matching: find.byType(Switch));
      final target = sw.evaluate().isNotEmpty ? sw.first : switches.at(1);
      final before = t.widget<Switch>(target).value;
      await tap(target);
      await settle(1500);
      check(t.widget<Switch>(target).value != before, 'Notification type switch did not toggle');
      await tap(target);
      await settle(1500);
      check(t.widget<Switch>(target).value == before, 'Notification type switch did not toggle back');
      step('reset to defaults');
      await tap(find.byTooltip(L.resetToDefaultsWQ));
      await tap(find.text(L.reset).last);
      await settle(2000);
      await back();
    });
  });
}

void settingsFlows() {
  group('12 Settings', () {
    e2eTest('settings: edit profile name (and restore)', (t) async {
      await login(premium);
      await openSettings();
      for (final newName in ['Maya E2E', premium.name]) {
        await openSettingsRow(L.editProfile);
        await waitFor(find.byType(EditProfileScreen));
        await enter(find.byType(TextFormField).first, newName);
        await hideKeyboard();
        await tap(find.text(L.saveChanges));
        await expectSoon(find.byType(SettingsScreen), 'Save profile did not return to Settings');
        // Scroll the Settings list itself back up to the profile card (the
        // generic main-scrollable pick can grab the wrong Scrollable here).
        await scrollTo(find.text(newName), dy: 400, maxSwipes: 6,
            scrollable: find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first);
        // skipOffstage: false — the list keeps its scroll offset, which can leave
        // the profile card built in the cache area just above the viewport.
        await expectSoon(find.text(newName, skipOffstage: false), 'Settings does not show the new name "$newName"');
        final me = await apiGet(await apiToken(premium), '/api/auth/me');
        check(me['name'] == newName, 'Server name not updated to "$newName": ${me['name']}');
      }
      step('name validation');
      await openSettingsRow(L.editProfile);
      await waitFor(find.byType(EditProfileScreen));
      await enter(find.byType(TextFormField).first, 'A');
      await hideKeyboard();
      await tap(find.text(L.saveChanges));
      await expectSoon(find.text(L.nameTwoCharacters), 'Edit profile: 1-char name not rejected');
      step('discard dialog');
      await back();
      if (find.text(L.discard).evaluate().isNotEmpty) {
        await tap(find.text(L.discard));
      }
      await waitFor(find.byType(SettingsScreen));
    });

    e2eTest('settings: language → Myanmar (home + drawer) → English', (t) async {
      await login(premium);
      await openSettings();
      await openSettingsRow(L.language);
      await tap(find.text('မြန်မာ'));
      await settle(2000);
      await goHome();
      step('home in Burmese');
      await expectSoon(find.text(LM.availableToSpend), 'Home not in Burmese after switching language');
      check(find.text(L.availableToSpend).evaluate().isEmpty, 'English hero label still visible after switching to Burmese');
      await scrollTo(find.text(LM.recentTransactions), maxSwipes: 6);
      await scrollTo(find.text(LM.financialReports), maxSwipes: 10);
      step('drawer in Burmese');
      await openDrawer();
      for (final s in [LM.transactions, LM.budgets, LM.goals, LM.settings]) {
        check(find.descendant(of: find.byType(Drawer), matching: find.text(s)).evaluate().isNotEmpty,
            'Drawer item "$s" not in Burmese');
      }
      await back();
      step('back to English');
      await drawerGo(LM.settings);
      await scrollTo(find.text(LM.language), maxSwipes: 8);
      await tap(find.text(LM.language).first);
      await tap(find.text('English').first);
      await settle(2000);
      await goHome();
      await scrollTo(find.text(L.availableToSpend), dy: 400, maxSwipes: 10);
      await expectSoon(find.text(L.availableToSpend), 'Home not back in English');
      step('language persisted server-side');
      final token = await apiToken(premium);
      final me = await apiGet(token, '/api/auth/me');
      check(me['language'] == 'en', 'Server language not reset to en: ${me['language']}');
    });

    e2eTest('settings: dark theme on Home/Budgets/Goals then light', (t) async {
      await login(premium);
      await openSettings();
      await openSettingsRow(L.theme);
      await tap(find.text(L.themeDark));
      await settle(1000);
      final dark = Theme.of(t.element(find.byType(Scaffold).last)).brightness == Brightness.dark;
      check(dark, 'Theme did not switch to dark');
      await goHome();
      step('dark home');
      await scrollTo(find.text(L.financialReports), maxSwipes: 10);
      await drawerGo(L.budgets);
      await waitFor(find.byType(BudgetsScreen));
      await settle(2000);
      await scrollTo(find.text('Weekly fun'), maxSwipes: 6);
      await drawerGo(L.goals);
      await waitFor(find.byType(GoalsScreen));
      await settle(2000);
      await scrollTo(find.text('New laptop'), maxSwipes: 6);
      await drawerGo(L.settings);
      await openSettingsRow(L.theme);
      await tap(find.text(L.themeLight));
      await settle(1000);
      check(Theme.of(t.element(find.byType(Scaffold).last)).brightness == Brightness.light, 'Theme did not switch back to light');
    });

    e2eTest('settings: feedback form submit', (t) async {
      await login(premium);
      await openSettings();
      await openSettingsRow(L.sendFeedback);
      await waitFor(find.byType(FeedbackScreen));
      step('submit without rating');
      await scrollTo(find.text(L.submitFeedback));
      await tap(find.text(L.submitFeedback));
      await settle(800);
      step('fill');
      await scrollTo(find.byType(ChoiceChip), dy: 300);
      await tap(find.byType(ChoiceChip).at(1));
      await scrollTo(find.byIcon(Icons.star_border_rounded));
      await tap(find.byIcon(Icons.star_border_rounded).at(3));
      await enter(find.byType(TextFormField).first, 'E2E feedback: the dashboard is clear and fast. Thanks!');
      await hideKeyboard();
      await scrollTo(find.text(L.submitFeedback));
      await tap(find.text(L.submitFeedback));
      await expectSoon(find.text(L.feedbackSubmittedSuccess), 'Feedback submit: no success snackbar');
      await expectSoon(find.byType(SettingsScreen), 'Feedback submit did not return to Settings');
    });

    e2eTest('settings: free user claims trial → Premium Active', (t) async {
      await login(free);
      await drawerGo(L.subscription);
      await waitFor(find.byType(SubscriptionScreen));
      await scrollTo(find.text(L.claimOneMonthFree));
      await tap(find.text(L.claimOneMonthFree));
      await expectSoon(find.text(L.welcomeToPremiumCelebration), 'Claim trial: no celebration dialog', timeout: const Duration(seconds: 30));
      if (find.text(L.letsGo).evaluate().isNotEmpty) await tap(find.text(L.letsGo));
      await settle(1500);
      await expectSoon(find.text(L.premiumActive), 'Subscription screen does not show "Premium Active" after claiming the trial');
      step('premium unlocked in drawer/insights');
      await goHome();
      await drawerGo(L.aiInsights);
      check(await waitFor(find.text(L.tryOneMonthFree), timeout: const Duration(seconds: 4), orNull: true) == false,
          'Insights still shows the paywall after claiming the trial');
    });

    e2eTest('settings: change password keeps session, then change back', (t) async {
      await login(empty);
      final pw2 = 'NinaPass456';
      for (final pair in [(empty.password, pw2), (pw2, empty.password)]) {
        await openSettings();
        await openSettingsRow(L.changePassword);
        await waitFor(find.byType(ChangePasswordScreen));
        final cur = find.widgetWithText(TextFormField, L.enterCurrentPassword);
        final nw = find.widgetWithText(TextFormField, L.enterNewPassword);
        final conf = find.widgetWithText(TextFormField, L.confirmYourNewPassword);
        step('wrong current password first');
        await enter(cur, 'Wrong${pair.$1}');
        await scrollTo(nw);
        await enter(nw, pair.$2);
        await scrollTo(conf);
        await enter(conf, pair.$2);
        await hideKeyboard();
        await scrollTo(find.widgetWithText(FilledButton, L.changePassword));
        await tap(find.widgetWithText(FilledButton, L.changePassword));
        await settle(3000);
        check(find.byType(ChangePasswordScreen).evaluate().isNotEmpty, 'Wrong current password accepted');
        step('correct current password');
        await scrollTo(cur, dy: 300);
        await enter(cur, pair.$1);
        await scrollTo(find.widgetWithText(FilledButton, L.changePassword));
        await hideKeyboard();
        await tap(find.widgetWithText(FilledButton, L.changePassword));
        await expectSoon(find.text(L.passwordChangedSuccessfully), 'Change password: no success snackbar', timeout: const Duration(seconds: 20));
        await settle(2000);
        check(find.byType(LoginScreen).evaluate().isEmpty, 'Changing the password logged the user out');
        await goHome();
        step('session still valid (data loads)');
        await drawerGo(L.transactions);
        await settle(2500);
        check(find.byType(LoginScreen).evaluate().isEmpty, 'Session invalid after password change (back at login)');
        await goHome();
      }
    });

    e2eTest('settings: delete account (wrong then right password)', (t) async {
      await login(deleteme);
      await openSettings();
      await openSettingsRow(L.editProfile);
      await waitFor(find.byType(EditProfileScreen));
      await scrollTo(find.widgetWithText(OutlinedButton, L.deleteAccount).evaluate().isNotEmpty
          ? find.widgetWithText(OutlinedButton, L.deleteAccount)
          : find.text(L.deleteAccount));
      for (final pw in ['WrongPass000', deleteme.password]) {
        step('delete with ${pw == deleteme.password ? 'right' : 'wrong'} password');
        await tap(find.text(L.deleteAccount).first);
        await waitFor(find.byType(AlertDialog));
        await enter(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), pw);
        await hideKeyboard();
        await tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(L.deleteAccount)).last);
        await settle(4000);
        if (pw != deleteme.password) {
          check(find.byType(LoginScreen).evaluate().isEmpty, 'Wrong password deleted the account');
          check(find.byType(SnackBar).evaluate().isNotEmpty, 'Wrong delete password: no error shown');
          await settle(4000);
        } else {
          await expectSoon(find.byType(LoginScreen), 'After deleting the account the app is not back on Login', timeout: const Duration(seconds: 30));
        }
      }
      step('deleted account cannot log in');
      await login(deleteme, expectHome: false);
      await settle(3000);
      check(find.byType(HomeScreen).evaluate().isEmpty, 'Deleted account could still log in');
    });
  });
}
