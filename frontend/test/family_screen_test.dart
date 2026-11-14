import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app_navigator.dart';
import 'package:frontend/models/budget.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/models/goal.dart';
import 'package:frontend/models/notification.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/providers/book_session.dart';
import 'package:frontend/providers/budget_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/providers/goal_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/screens/family/family_invitations_screen.dart';
import 'package:frontend/screens/family/family_invite_screen.dart';
import 'package:frontend/screens/family/family_member_sheet.dart';
import 'package:frontend/screens/family/family_screen.dart';
import 'package:frontend/screens/notifications/notifications_screen.dart';
import 'package:frontend/screens/settings/edit_profile_screen.dart';
import 'package:frontend/screens/settings/settings_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/services/notification_opener.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/push_tap.dart';
import 'package:frontend/widgets/mascot.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// HTTP: ONE MockClient for the file (ApiService binds its inner client once).
// ---------------------------------------------------------------------------

late Future<http.Response> Function(http.Request) _respond;
final List<http.Request> _requests = [];
final _mock = MockClient((request) {
  _requests.add(request);
  return _respond(request);
});

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

// ---------------------------------------------------------------------------
// Fakes.
// ---------------------------------------------------------------------------

class _Auth extends AuthProvider {
  _Auth({this.paid = true});
  final bool paid;
  @override
  bool get isPaid => paid;
}

/// A family that is already known; every change is recorded, and answers
/// [nextError] (null: success).
class _FakeFamily extends FamilyProvider {
  _FakeFamily({FamilyOverview overview = FamilyOverview.none, List<FamilyInvite> mine = const []}) {
    debugApply(overview, myInvites: mine);
  }

  final calls = <String>[];
  String? nextError;

  Future<String?> _record(String call) async {
    calls.add(call);
    return nextError;
  }

  @override
  Future<void> refresh() async {}
  @override
  Future<String?> loadMyInvites() async => null;
  @override
  Future<String?> createFamily(String name) => _record('create:$name');
  @override
  Future<String?> renameFamily(String name) => _record('rename:$name');
  @override
  Future<String?> deleteFamily(String confirmName) => _record('delete:$confirmName');
  @override
  Future<String?> addPlaceholder(String displayName) => _record('placeholder:$displayName');
  @override
  Future<String?> updateMember(String memberId, {String? displayName, String? role}) =>
      _record('update:$memberId:${displayName ?? ''}:${role ?? ''}');
  @override
  Future<String?> removeMember(String memberId) => _record('remove:$memberId');
  @override
  Future<String?> leave() => _record('leave');
  @override
  Future<String?> transferOwnership(String memberId) => _record('owner:$memberId');
  @override
  Future<String?> invite(String email, {String? linkMemberId}) => _record('invite:$email:${linkMemberId ?? ''}');
  @override
  Future<String?> cancelInvite(String inviteId) => _record('cancel:$inviteId');
  @override
  Future<String?> acceptInvite(String inviteId) => _record('accept:$inviteId');
  @override
  Future<String?> declineInvite(String inviteId) => _record('decline:$inviteId');
}

class _FakeNotifications extends NotificationProvider {
  _FakeNotifications([this.items = const []]);
  final List<AppNotification> items;
  @override
  List<AppNotification> get notifications => items;
  @override
  bool get isLoading => false;
  @override
  int get unreadCount => 0;
  @override
  Future<void> fetchNotifications({bool unreadOnly = false}) async {}
  @override
  Future<void> fetchUnreadCount() async {}
  @override
  Future<bool> markAsRead(String notificationId) async => true;
}

/// Records the book the app was in when a budget / goal was fetched.
class _Budgets extends BudgetProvider {
  _Budgets([this.budget]);
  final Budget? budget;
  final fetchedIn = <BookMode>[];
  @override
  Future<Budget?> getBudget(String budgetId) async {
    fetchedIn.add(ApiService.bookMode);
    return budget;
  }
}

class _Goals extends GoalProvider {
  final fetchedIn = <BookMode>[];
  @override
  Future<Goal?> getGoal(String goalId) async {
    fetchedIn.add(ApiService.bookMode);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Data.
// ---------------------------------------------------------------------------

const _longMyFamily = 'ဦးအောင်သူဝင်းနှင့် ဒေါ်ခင်မြတ်တို့ ရန်ကုန်မိသားစု';
const _longMyName = 'ဒေါ်ခင်မြတ်မြတ်နိုင် (ရန်ကုန်တိုင်းဒေသကြီး)';
const _longEnName = 'Daw Khin Myat Myat Noe of Bahan Township, Yangon';

/// Me (m1, [role]), the owner or an admin (m2), a member (m3), a
/// placeholder (p1), a former account member (f1), a former placeholder
/// (f2), and (admins) one pending invite linked to p1.
FamilyOverview _overview({
  String role = FamilyMember.roleOwner,
  bool readOnly = false,
  String name = 'Aung family',
  String? longName,
}) {
  String n(String short) => longName == null ? short : '$longName $short';
  return FamilyOverview(
    family: Family(id: 'f', name: name, readOnly: readOnly),
    myMemberId: 'm1',
    myRole: role,
    members: [
      FamilyMember(id: 'm1', displayName: n('Dad'), kind: 'account', role: role, isMe: true),
      FamilyMember(
          id: 'm2', displayName: n('Mum'), kind: 'account', role: role == 'owner' ? 'admin' : 'owner'),
      FamilyMember(id: 'm3', displayName: n('Ko Ko'), kind: 'account', role: 'member'),
      FamilyMember(id: 'p1', displayName: n('Ma Ma'), kind: 'placeholder'),
      FamilyMember(id: 'f1', displayName: n('Uncle'), kind: 'account', role: 'member', status: 'former'),
      FamilyMember(id: 'f2', displayName: n('Grandpa'), kind: 'placeholder', status: 'former'),
    ],
    invites: role == FamilyMember.roleMember
        ? const []
        : [
            FamilyInvite(
                id: 'i1',
                email: longName == null ? 'aunt@example.com' : 'daw.khin.myat.myat.noe.bahan@example.com',
                linkMemberId: 'p1',
                expiresAt: DateTime(2026, 11, 27)),
          ],
    maxMembers: 6,
    maxPlaceholders: 20,
  );
}

FamilyInvite _received({String id = 'inv1', String family = 'Tun family', String by = 'Ko Tun'}) =>
    FamilyInvite(id: id, familyId: 'tf', familyName: family, invitedBy: by, expiresAt: DateTime(2026, 11, 27));

AppNotification _notice(String type, {String? goalId, String? book, String title = 'A notice'}) =>
    AppNotification.fromJson({
      'id': 'n-$type',
      'user_id': 'u1',
      'type': type,
      'title': title,
      'message': 'Something happened',
      'goal_id': goalId,
      'goal_name': null,
      'currency': null,
      'created_at': '2026-11-14T08:00:00Z',
      'is_read': true,
      'extra': book == null ? null : {'book': book},
    });

late ThemeData _light;
late ThemeData _dark;

final _en = AppLocalizations(const Locale('en'));
final _my = AppLocalizations(const Locale('my'));

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required FamilyProvider family,
  bool paid = true,
  BookModeProvider? books,
  NotificationProvider? notifications,
  BudgetProvider? budgets,
  GoalProvider? goals,
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
  double width = 360,
  double height = 1600,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: _Auth(paid: paid)),
      ChangeNotifierProvider<FamilyProvider>.value(value: family),
      ChangeNotifierProvider<BookModeProvider>.value(value: books ?? BookModeProvider()),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ChangeNotifierProvider<NotificationProvider>.value(value: notifications ?? _FakeNotifications()),
      ChangeNotifierProvider<BudgetProvider>.value(value: budgets ?? _Budgets()),
      ChangeNotifierProvider<GoalProvider>.value(value: goals ?? _Goals()),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      locale: locale,
      theme: _light,
      darkTheme: _dark,
      themeMode: themeMode,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('my')],
      routes: {
        '/subscription': (_) => const Scaffold(body: Text('plans screen')),
        '/family': (_) => const FamilyScreen(),
      },
      home: home,
    ),
  ));
  await tester.pumpAndSettle();
}

/// Every element [finder] finds lies inside the screen, left to right.
void _expectOnScreen(WidgetTester tester, Finder finder, double width) {
  expect(finder, findsWidgets);
  for (final element in finder.evaluate()) {
    final rect = tester.getRect(find.byElementPredicate((e) => e == element));
    expect(rect.left, greaterThanOrEqualTo(0), reason: '$finder');
    expect(rect.right, lessThanOrEqualTo(width + 0.01), reason: '$finder');
  }
}

Future<void> _tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, Finder button) {
  final widget = tester.widget(button);
  if (widget is ButtonStyleButton) return widget.onPressed != null;
  throw StateError('not a button: $widget');
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    runZonedGuarded(() {
      _light = AppTheme.light;
      _dark = AppTheme.dark;
    }, (error, _) {
      if (!'$error'.contains('Manrope')) throw error;
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
    SharedPreferences.setMockInitialValues({});
    _respond = (_) async => _json({'family': null});
    await http.runWithClient(() => ApiService.getFamily(), () => _mock);
  });

  setUp(() {
    _respond = (_) async => _json({});
    _requests.clear();
    SharedPreferences.setMockInitialValues({'access_token': 'tok'});
    ApiService.bookMode = BookMode.personal;
    ApiService.onNoFamily = null;
  });
  tearDown(() {
    ApiService.bookMode = BookMode.personal;
    ApiService.onNoFamily = null;
  });

  group('no family yet', () {
    testWidgets('Free: the Upgrade path; Create stays disabled; no mascot', (tester) async {
      final family = _FakeFamily();
      await _pump(tester, const FamilyScreen(), family: family, paid: false);

      expect(find.text(_en.familyCreateTitle), findsOneWidget);
      expect(find.text(_en.familyCreateNeedsPlan), findsOneWidget);
      expect(find.byType(Mascot), findsNothing);

      await tester.enterText(find.byKey(FamilyScreen.nameFieldKey), 'Aung family');
      await tester.pump();
      expect(_enabled(tester, find.byKey(FamilyScreen.createKey)), isFalse);

      await _tapAndSettle(tester, find.byKey(FamilyScreen.upgradeKey));
      expect(find.text('plans screen'), findsOneWidget);
      expect(family.calls, isEmpty);
    });

    testWidgets('Plus: Create needs a name, then calls createFamily', (tester) async {
      final family = _FakeFamily();
      await _pump(tester, const FamilyScreen(), family: family);

      expect(find.byKey(FamilyScreen.upgradeKey), findsNothing);
      expect(find.byType(Mascot), findsNothing);
      expect(_enabled(tester, find.byKey(FamilyScreen.createKey)), isFalse, reason: 'no name yet');

      await tester.enterText(find.byKey(FamilyScreen.nameFieldKey), '  Aung family ');
      await tester.pump();
      expect(_enabled(tester, find.byKey(FamilyScreen.createKey)), isTrue);
      await _tapAndSettle(tester, find.byKey(FamilyScreen.createKey));
      expect(family.calls, ['create:Aung family']);
    });

    testWidgets('a refused create shows the server message', (tester) async {
      final family = _FakeFamily()..nextError = 'Creating a family needs the Plus or Pro plan.';
      await _pump(tester, const FamilyScreen(), family: family);
      await tester.enterText(find.byKey(FamilyScreen.nameFieldKey), 'Aung family');
      await tester.pump();
      await _tapAndSettle(tester, find.byKey(FamilyScreen.createKey));
      expect(find.text('Creating a family needs the Plus or Pro plan.'), findsOneWidget);
    });

    testWidgets('received invitations are one tap away', (tester) async {
      final family = _FakeFamily(mine: [_received()]);
      await _pump(tester, const FamilyScreen(), family: family);
      expect(find.text(_en.familyInvitationsPending(1)), findsOneWidget);
      await _tapAndSettle(tester, find.byKey(FamilyScreen.invitationsKey));
      expect(find.byType(FamilyInvitationsScreen), findsOneWidget);
      expect(find.text('Tun family'), findsOneWidget);
    });
  });

  group('roles', () {
    testWidgets('a member: no invite, add name, cancel, remove, roles, hand over or delete', (tester) async {
      final family = _FakeFamily(overview: _overview(role: FamilyMember.roleMember));
      await _pump(tester, const FamilyScreen(), family: family);

      expect(find.text('Aung family'), findsOneWidget);
      expect(find.text('Ko Ko'), findsOneWidget);
      expect(find.text('Ma Ma'), findsOneWidget);
      expect(find.byKey(FamilyScreen.inviteKey), findsNothing);
      expect(find.byKey(FamilyScreen.addNameKey), findsNothing);
      expect(find.byKey(FamilyScreen.renameKey), findsNothing);
      expect(find.byKey(FamilyScreen.handOverKey), findsNothing);
      expect(find.byKey(FamilyScreen.deleteKey), findsNothing);
      expect(find.byKey(FamilyScreen.leaveKey), findsOneWidget);
      expect(find.text(_en.familyPendingInvitesSection), findsNothing);

      // Nobody's row opens anything for a member.
      for (final id in ['m2', 'm3', 'p1']) {
        await _tapAndSettle(tester, find.byKey(FamilyScreen.memberKey(id)));
        expect(find.byType(FamilyMemberSheet), findsNothing, reason: id);
      }

      await _tapAndSettle(tester, find.byKey(FamilyScreen.leaveKey));
      await _tapAndSettle(tester, find.byKey(FamilyScreen.leaveConfirmKey));
      expect(family.calls, ['leave']);
    });

    testWidgets('an admin: invites, adds and removes names and members, but not admins, roles or delete',
        (tester) async {
      final family = _FakeFamily(overview: _overview(role: FamilyMember.roleAdmin));
      await _pump(tester, const FamilyScreen(), family: family);

      expect(find.byKey(FamilyScreen.inviteKey), findsOneWidget);
      expect(find.byKey(FamilyScreen.addNameKey), findsOneWidget);
      expect(find.byKey(FamilyScreen.renameKey), findsOneWidget);
      expect(find.byKey(FamilyScreen.deleteKey), findsNothing);
      expect(find.byKey(FamilyScreen.handOverKey), findsNothing);
      expect(find.text('aunt@example.com'), findsOneWidget);

      // The owner's row: nothing for an admin.
      await _tapAndSettle(tester, find.byKey(FamilyScreen.memberKey('m2')));
      expect(find.byType(FamilyMemberSheet), findsNothing);

      // A member: remove, no role change, no rename (their name is their own).
      await _tapAndSettle(tester, find.byKey(FamilyScreen.memberKey('m3')));
      expect(find.byKey(FamilyMemberSheet.removeKey), findsOneWidget);
      expect(find.byKey(FamilyMemberSheet.makeAdminKey), findsNothing);
      expect(find.byKey(FamilyMemberSheet.removeAdminKey), findsNothing);
      expect(find.byKey(FamilyMemberSheet.renameKey), findsNothing);
      await _tapAndSettle(tester, find.byKey(FamilyMemberSheet.removeKey));
      await _tapAndSettle(tester, find.byKey(FamilyMemberSheet.removeConfirmKey));
      expect(family.calls, ['remove:m3']);
      expect(find.byType(FamilyMemberSheet), findsNothing, reason: 'the sheet closes');

      // A placeholder: rename and remove.
      await _tapAndSettle(tester, find.byKey(FamilyScreen.memberKey('p1')));
      await _tapAndSettle(tester, find.byKey(FamilyMemberSheet.renameKey));
      await tester.enterText(find.byKey(FamilyMemberSheet.nameFieldKey), 'Ma Ma Lay');
      await _tapAndSettle(tester, find.byKey(FamilyMemberSheet.saveKey));
      expect(family.calls.last, 'update:p1:Ma Ma Lay:');

      // Cancel the pending invite.
      await _tapAndSettle(tester, find.byKey(FamilyScreen.cancelInviteKey('i1')));
      expect(family.calls.last, 'cancel:i1');

      // Add a name.
      await _tapAndSettle(tester, find.byKey(FamilyScreen.addNameKey));
      await tester.enterText(find.byKey(FamilyScreen.addNameFieldKey), 'Grandma');
      await tester.pump();
      await _tapAndSettle(tester, find.byKey(FamilyScreen.addNameSaveKey));
      expect(family.calls.last, 'placeholder:Grandma');

      // Rename the family.
      await _tapAndSettle(tester, find.byKey(FamilyScreen.renameKey));
      await tester.enterText(find.byKey(FamilyScreen.renameFieldKey), 'The Aungs');
      await tester.pump();
      await _tapAndSettle(tester, find.byKey(FamilyScreen.renameSaveKey));
      expect(family.calls.last, 'rename:The Aungs');
    });

    testWidgets('former members are collapsed; an admin can rename a former member', (tester) async {
      final family = _FakeFamily(overview: _overview(role: FamilyMember.roleAdmin));
      await _pump(tester, const FamilyScreen(), family: family);
      expect(find.text('Uncle'), findsNothing, reason: 'collapsed');
      await _tapAndSettle(tester, find.byKey(FamilyScreen.formerKey));
      expect(find.text('Uncle'), findsOneWidget);
      expect(find.text('Grandpa'), findsOneWidget);

      await _tapAndSettle(tester, find.byKey(FamilyScreen.memberKey('f1')));
      expect(find.byKey(FamilyMemberSheet.removeKey), findsNothing, reason: 'already former');
      await _tapAndSettle(tester, find.byKey(FamilyMemberSheet.renameKey));
      await tester.enterText(find.byKey(FamilyMemberSheet.nameFieldKey), 'Uncle Tun');
      await _tapAndSettle(tester, find.byKey(FamilyMemberSheet.saveKey));
      expect(family.calls, ['update:f1:Uncle Tun:']);
    });

    testWidgets('the owner: role changes, removing an admin, hand over, and no Leave', (tester) async {
      final family = _FakeFamily(overview: _overview());
      await _pump(tester, const FamilyScreen(), family: family);

      // The admin: Remove admin, and remove.
      await _tapAndSettle(tester, find.byKey(FamilyScreen.memberKey('m2')));
      expect(find.byKey(FamilyMemberSheet.makeAdminKey), findsNothing);
      expect(find.byKey(FamilyMemberSheet.removeKey), findsOneWidget);
      await _tapAndSettle(tester, find.byKey(FamilyMemberSheet.removeAdminKey));
      expect(family.calls.last, 'update:m2::member');

      // The member: Make admin.
      await _tapAndSettle(tester, find.byKey(FamilyScreen.memberKey('m3')));
      await _tapAndSettle(tester, find.byKey(FamilyMemberSheet.makeAdminKey));
      expect(family.calls.last, 'update:m3::admin');

      // My own row opens nothing.
      await _tapAndSettle(tester, find.byKey(FamilyScreen.memberKey('m1')));
      expect(find.byType(FamilyMemberSheet), findsNothing);

      // Leave is not offered until ownership is handed over.
      expect(find.text(_en.familyOwnerLeaveHint), findsOneWidget);
      await _tapAndSettle(tester, find.byKey(FamilyScreen.leaveKey));
      expect(find.byKey(FamilyScreen.leaveConfirmKey), findsNothing);
      expect(family.calls.where((c) => c == 'leave'), isEmpty);

      // Hand over: only active account members other than me.
      await _tapAndSettle(tester, find.byKey(FamilyScreen.handOverKey));
      expect(find.byKey(FamilyScreen.handOverToKey('m2')), findsOneWidget);
      expect(find.byKey(FamilyScreen.handOverToKey('m3')), findsOneWidget);
      expect(find.byKey(FamilyScreen.handOverToKey('m1')), findsNothing);
      expect(find.byKey(FamilyScreen.handOverToKey('p1')), findsNothing);
      expect(find.byKey(FamilyScreen.handOverToKey('f1')), findsNothing);
      await _tapAndSettle(tester, find.byKey(FamilyScreen.handOverToKey('m3')));
      await _tapAndSettle(tester, find.byKey(FamilyScreen.handOverConfirmKey));
      expect(family.calls.last, 'owner:m3');
    });

    testWidgets('the owner deletes only with the exact family name typed', (tester) async {
      final family = _FakeFamily(overview: _overview());
      await _pump(tester, const FamilyScreen(), family: family);

      await _tapAndSettle(tester, find.byKey(FamilyScreen.deleteKey));
      final confirm = find.byKey(FamilyScreen.deleteConfirmKey);
      expect(_enabled(tester, confirm), isFalse);
      await tester.enterText(find.byKey(FamilyScreen.deleteFieldKey), 'aung family');
      await tester.pump();
      expect(_enabled(tester, confirm), isFalse, reason: 'case matters');
      await tester.enterText(find.byKey(FamilyScreen.deleteFieldKey), 'Aung famil');
      await tester.pump();
      expect(_enabled(tester, confirm), isFalse);
      await tester.enterText(find.byKey(FamilyScreen.deleteFieldKey), 'Aung family');
      await tester.pump();
      expect(_enabled(tester, confirm), isTrue);
      await _tapAndSettle(tester, confirm);
      expect(family.calls, ['delete:Aung family']);
    });

    testWidgets('a read-only family says so and offers no invites or new names', (tester) async {
      final family = _FakeFamily(overview: _overview(readOnly: true));
      await _pump(tester, const FamilyScreen(), family: family);
      expect(find.text(_en.familyReadOnlyBanner), findsOneWidget);
      expect(find.byKey(FamilyScreen.inviteKey), findsNothing);
      expect(find.byKey(FamilyScreen.addNameKey), findsNothing);
      expect(find.byKey(FamilyScreen.deleteKey), findsOneWidget, reason: 'it can still be repaired or deleted');
      expect(find.byKey(FamilyScreen.handOverKey), findsOneWidget);
    });
  });

  group('invitations', () {
    testWidgets('invite: the email and an optional "This is …" link to a placeholder or former member',
        (tester) async {
      final family = _FakeFamily(overview: _overview(role: FamilyMember.roleAdmin));
      await _pump(tester, const FamilyScreen(), family: family);
      await _tapAndSettle(tester, find.byKey(FamilyScreen.inviteKey));
      expect(find.byType(FamilyInviteScreen), findsOneWidget);

      // Linkable: placeholders and former members; never an active account member.
      expect(find.byKey(FamilyInviteScreen.linkKey('p1')), findsOneWidget);
      expect(find.byKey(FamilyInviteScreen.linkKey('f1')), findsOneWidget);
      expect(find.byKey(FamilyInviteScreen.linkKey('f2')), findsOneWidget);
      expect(find.byKey(FamilyInviteScreen.linkKey('m3')), findsNothing);
      expect(find.byKey(FamilyInviteScreen.linkKey('m1')), findsNothing);

      // A bad address is caught here.
      await tester.enterText(find.byKey(FamilyInviteScreen.emailKey), 'not-an-email');
      await _tapAndSettle(tester, find.byKey(FamilyInviteScreen.sendKey));
      expect(find.text(_en.enterValidEmailError), findsOneWidget);
      expect(family.calls, isEmpty);

      await tester.enterText(find.byKey(FamilyInviteScreen.emailKey), ' Aunt@Example.com ');
      await _tapAndSettle(tester, find.byKey(FamilyInviteScreen.linkKey('p1')));
      await _tapAndSettle(tester, find.byKey(FamilyInviteScreen.sendKey));
      expect(family.calls, ['invite:Aunt@Example.com:p1']);
      expect(find.byType(FamilyInviteScreen), findsNothing, reason: 'closes when sent');
      expect(find.text(_en.familyInviteSent('Aunt@Example.com')), findsOneWidget);
    });

    testWidgets('invite: someone new sends no link; a refusal keeps the screen open with the message',
        (tester) async {
      final family = _FakeFamily(overview: _overview(role: FamilyMember.roleAdmin))
        ..nextError = 'The family already has as many members as it can have.';
      await _pump(tester, const FamilyInviteScreen(), family: family);
      await tester.enterText(find.byKey(FamilyInviteScreen.emailKey), 'aunt@example.com');
      await _tapAndSettle(tester, find.byKey(FamilyInviteScreen.sendKey));
      expect(family.calls, ['invite:aunt@example.com:']);
      expect(find.byType(FamilyInviteScreen), findsOneWidget);
      expect(find.text('The family already has as many members as it can have.'), findsOneWidget);
    });

    testWidgets('received invitations: Join and Decline', (tester) async {
      final family = _FakeFamily(mine: [_received(), _received(id: 'inv2', family: 'Mya family', by: 'Daw Mya')]);
      await _pump(tester, const FamilyInvitationsScreen(), family: family);

      expect(find.text('Tun family'), findsOneWidget);
      expect(find.text(_en.familyInvitedBy('Ko Tun')), findsOneWidget);
      await _tapAndSettle(tester, find.byKey(FamilyInvitationsScreen.declineKey('inv2')));
      expect(family.calls, ['decline:inv2']);
      await _tapAndSettle(tester, find.byKey(FamilyInvitationsScreen.joinKey('inv1')));
      expect(family.calls, ['decline:inv2', 'accept:inv1']);
    });

    testWidgets('Join while already in a family: leave first, nothing is sent', (tester) async {
      final family = _FakeFamily(overview: _overview(role: FamilyMember.roleMember), mine: [_received()]);
      await _pump(tester, const FamilyInvitationsScreen(), family: family);
      await _tapAndSettle(tester, find.byKey(FamilyInvitationsScreen.joinKey('inv1')));
      expect(find.text(_en.familyLeaveFirst), findsOneWidget);
      expect(family.calls, isEmpty);
    });

    testWidgets('no invitations: a plain line, no mascot', (tester) async {
      await _pump(tester, const FamilyInvitationsScreen(), family: _FakeFamily());
      expect(find.text(_en.familyInvitationsNone), findsOneWidget);
      expect(find.byType(Mascot), findsNothing);
    });
  });

  group('no_family is said once', () {
    Map<String, dynamic> overviewJson() => {
          'family': {'id': 'f', 'name': 'Aung family', 'read_only': false},
          'me': {'member_id': 'm1', 'role': 'owner'},
          'members': [
            {'id': 'm1', 'display_name': 'Dad', 'kind': 'account', 'role': 'owner', 'status': 'active', 'is_me': true},
          ],
          'invites': [],
          'limits': {'max_members': 6, 'max_placeholders': 20},
        };
    final noFamily = _json({
      'detail': {'code': 'no_family', 'message': "You're not in a family."}
    }, 404);

    Future<FamilyProvider> loaded(WidgetTester tester) async {
      _respond = (r) async => _json(overviewJson());
      final family = FamilyProvider();
      await tester.runAsync(family.refresh);
      expect(family.inFamily, isTrue);
      return family;
    }

    testWidgets('Family mode: the app root reports it; the screen shows nothing more', (tester) async {
      final family = await loaded(tester);
      var reported = 0;
      ApiService.onNoFamily = () => reported++;
      ApiService.bookMode = BookMode.family;
      await _pump(tester, const FamilyScreen(), family: family);

      _respond = (r) async => noFamily;
      await _tapAndSettle(tester, find.byKey(FamilyScreen.renameKey));
      await tester.enterText(find.byKey(FamilyScreen.renameFieldKey), 'The Aungs');
      await tester.pump();
      await tester.tap(find.byKey(FamilyScreen.renameSaveKey));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      expect(reported, 1);
      expect(family.lastErrorReported, isTrue);
      expect(find.text("You're not in a family."), findsNothing);
    });

    testWidgets('Personal mode: the screen says it and reloads the family', (tester) async {
      final family = await loaded(tester);
      var reported = 0;
      ApiService.onNoFamily = () => reported++;
      await _pump(tester, const FamilyScreen(), family: family);

      _respond = (r) async => r.method == 'GET' ? _json({'family': null}) : noFamily;
      await _tapAndSettle(tester, find.byKey(FamilyScreen.renameKey));
      await tester.enterText(find.byKey(FamilyScreen.renameFieldKey), 'The Aungs');
      await tester.pump();
      await tester.tap(find.byKey(FamilyScreen.renameSaveKey));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      expect(reported, 0);
      expect(family.lastErrorReported, isFalse);
      expect(find.text("You're not in a family."), findsOneWidget);
      expect(family.inFamily, isFalse, reason: 'reloaded');
      expect(find.byKey(FamilyScreen.nameFieldKey), findsOneWidget, reason: 'the create form now');
    });
  });

  group('settings and profile', () {
    testWidgets('Settings has a Family row between Account and Appearance; it opens the family', (tester) async {
      await _pump(tester, SettingsScreen(), family: _FakeFamily(overview: _overview()), height: 2400);
      final row = find.byKey(SettingsScreen.familyRowKey);
      expect(row, findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('Aung family')), findsOneWidget);
      expect(tester.getRect(row).top, greaterThan(tester.getRect(find.text(_en.account)).bottom));
      expect(tester.getRect(row).bottom, lessThan(tester.getRect(find.text(_en.appearance)).top));
      await _tapAndSettle(tester, row);
      expect(find.byType(FamilyScreen), findsOneWidget);
    });

    testWidgets('Settings, no family: "Create or join a family"', (tester) async {
      await _pump(tester, SettingsScreen(), family: _FakeFamily(), height: 2400);
      expect(find.descendant(of: find.byKey(SettingsScreen.familyRowKey), matching: find.text(_en.familyCreateOrJoin)),
          findsOneWidget);
    });

    for (final (label, overview, note) in [
      ('a member', _overview(role: FamilyMember.roleMember), _en.familyDeleteAccountNote),
      ('the owner', _overview(), _en.familyDeleteAccountNoteOwner),
    ]) {
      testWidgets('delete account: $label gets the family line', (tester) async {
        await _pump(tester, EditProfileScreen(), family: _FakeFamily(overview: overview));
        await _tapAndSettle(tester, find.text(_en.deleteAccount));
        expect(find.text('• $note'), findsOneWidget);
      });
    }

    testWidgets('delete account, no family: no family line', (tester) async {
      await _pump(tester, EditProfileScreen(), family: _FakeFamily());
      await _tapAndSettle(tester, find.text(_en.deleteAccount));
      expect(find.text('• ${_en.familyDeleteAccountNote}'), findsNothing);
      expect(find.text('• ${_en.familyDeleteAccountNoteOwner}'), findsNothing);
    });
  });

  group('notifications', () {
    test('extra.book and the family types are read', () {
      final n = _notice('budget_threshold', goalId: 'b1', book: 'family');
      expect(n.book, 'family');
      expect(n.isFamilyBook, isTrue);
      expect(_notice('budget_threshold').isFamilyBook, isFalse);
      for (final type in ['family_invite', 'family_invite_accepted', 'family_removed', 'family_owner']) {
        expect(_notice(type).type.name, type);
      }
    });

    testWidgets('the family types have their own icons', (tester) async {
      await _pump(tester, NotificationsScreen(),
          family: _FakeFamily(),
          notifications: _FakeNotifications([
            _notice('family_invite', title: 'Family invitation'),
            _notice('family_invite_accepted', title: 'New family member'),
            _notice('family_removed', title: 'Removed from family'),
            _notice('family_owner', title: "You're the family owner now"),
          ]));
      expect(find.byIcon(Icons.mail_rounded), findsOneWidget);
      expect(find.byIcon(Icons.group_add_rounded), findsOneWidget);
      expect(find.byIcon(Icons.person_remove_rounded), findsOneWidget);
      expect(find.byIcon(Icons.key_rounded), findsOneWidget);
      expect(find.byIcon(Icons.campaign_rounded), findsNothing, reason: 'no broadcast fallback');
    });

    testWidgets('family_invite opens the invitations', (tester) async {
      await _pump(tester, NotificationsScreen(),
          family: _FakeFamily(mine: [_received()]),
          notifications: _FakeNotifications([_notice('family_invite', goalId: 'inv1', title: 'Family invitation')]));
      await _tapAndSettle(tester, find.text('Family invitation'));
      expect(find.byType(FamilyInvitationsScreen), findsOneWidget);
    });

    testWidgets('a family budget notice tapped in Personal mode switches to Family before it is fetched',
        (tester) async {
      final books = BookModeProvider();
      final budgets = _Budgets();
      await _pump(tester, NotificationsScreen(),
          family: _FakeFamily(overview: _overview()),
          books: books,
          budgets: budgets,
          notifications: _FakeNotifications([
            _notice('budget_threshold', goalId: 'b1', book: 'family', title: 'Family budget'),
          ]));
      await _tapAndSettle(tester, find.text('Family budget'));
      expect(books.mode, BookMode.family);
      expect(budgets.fetchedIn, [BookMode.family]);
    });

    testWidgets('a personal goal notice tapped in Family mode switches to Personal first', (tester) async {
      final books = BookModeProvider();
      await books.setMode(BookMode.family);
      final goals = _Goals();
      await _pump(tester, NotificationsScreen(),
          family: _FakeFamily(overview: _overview()),
          books: books,
          goals: goals,
          notifications: _FakeNotifications([_notice('goal_achieved', goalId: 'g1', title: 'Goal reached')]));
      await _tapAndSettle(tester, find.text('Goal reached'));
      expect(books.mode, BookMode.personal);
      expect(goals.fetchedIn, [BookMode.personal]);
    });
  });

  group('opening a notice (list and push)', () {
    Budget budget() => Budget.fromJson({
          'id': 'b1',
          'user_id': 'u1',
          'name': 'Family food',
          'period': 'monthly',
          'start_date': '2026-11-01T00:00:00Z',
          'end_date': '2026-11-30T00:00:00Z',
          'category_budgets': [],
          'total_budget': 100000,
          'total_spent': 0,
          'remaining_budget': 100000,
          'percentage_used': 0,
          'status': 'active',
          'is_active': true,
          'currency': 'mmk',
          'created_at': '2026-11-01T00:00:00Z',
          'updated_at': '2026-11-01T00:00:00Z',
        });

    testWidgets('the switch closes the screens above Home, then the budget opens through navigatorKey',
        (tester) async {
      final books = BookModeProvider();
      final family = _FakeFamily(overview: _overview());
      final session = BookSession(
        books: books,
        family: family,
        navigatorKey: navigatorKey,
        resetBookData: () {},
        showMessage: (_) {},
        noLongerMemberText: () => '',
      )..attach();
      addTearDown(session.detach);
      final budgets = _Budgets(budget());
      await _pump(tester, const Scaffold(body: Text('home')), family: family, books: books, budgets: budgets);
      navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('notices'))));
      await tester.pumpAndSettle();

      final opener = NotificationOpener(
        navigatorKey: navigatorKey,
        books: books,
        family: family,
        budgets: budgets,
        goals: _Goals(),
        budgetPage: (b) => Scaffold(body: Text('budget ${b.name}')),
      );
      var closed = 0;
      final opened = opener.open('budget_exceeded', goalId: 'b1', family: true, onClosed: () => closed++);
      await tester.pumpAndSettle();
      expect(await opened, isTrue);
      expect(find.text('budget Family food'), findsOneWidget);
      expect(budgets.fetchedIn, [BookMode.family]);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget, reason: 'Back goes to Home, not to the closed list');
      expect(closed, 1);
    });

    test('push gate: a family push waits for the family, then opens; gone from the family: dropped', () {
      final family = FamilyProvider();
      final opener = NotificationOpener(
        navigatorKey: GlobalKey<NavigatorState>(),
        books: BookModeProvider(),
        family: family,
        budgets: _Budgets(),
        goals: _Goals(),
      );
      // No navigator yet / signed out: kept.
      expect(opener.openPush('budget_exceeded', goalId: 'b1', family: true, signedIn: false), isFalse);
      expect(opener.openPush('budget_exceeded', goalId: 'b1', family: true, signedIn: true), isFalse);
    });

    testWidgets('push gate with a navigator', (tester) async {
      final books = BookModeProvider();
      final family = _UnloadedFamily();
      final budgets = _Budgets();
      await _pump(tester, const Scaffold(body: Text('home')), family: family, books: books, budgets: budgets);
      final opener = NotificationOpener(
        navigatorKey: navigatorKey,
        books: books,
        family: family,
        budgets: budgets,
        goals: _Goals(),
      );
      // The family isn't known yet: a remembered Family mode may still be
      // applied (and would close what was opened), so wait.
      expect(opener.openPush('budget_exceeded', goalId: 'b1', family: true, signedIn: true), isFalse);
      expect(opener.openPush('goal_achieved', goalId: 'g1', family: false, signedIn: true), isFalse);
      // Not about a book: opens now.
      expect(opener.openPush('family_invite', goalId: 'inv1', family: false, signedIn: true), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(FamilyInvitationsScreen), findsOneWidget);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();

      // Known, not in a family: a family push is dropped; a personal one opens.
      family.known(inFamily: false);
      expect(opener.openPush('budget_exceeded', goalId: 'b1', family: true, signedIn: true), isTrue);
      await tester.pumpAndSettle();
      expect(budgets.fetchedIn, isEmpty);
      expect(books.mode, BookMode.personal);
      expect(opener.openPush('budget_exceeded', goalId: 'b1', family: false, signedIn: true), isTrue);
      await tester.pumpAndSettle();
      expect(budgets.fetchedIn, [BookMode.personal]);

      // In a family: the family push switches to Family, then opens.
      family.known(inFamily: true);
      expect(opener.openPush('budget_exceeded', goalId: 'b1', family: true, signedIn: true), isTrue);
      await tester.pumpAndSettle();
      expect(budgets.fetchedIn, [BookMode.personal, BookMode.family]);
      expect(books.mode, BookMode.family);

      // A failed family request: personal pushes don't wait for ever.
      family.failed();
      expect(opener.openPush('goal_achieved', goalId: 'g1', family: false, signedIn: true), isTrue);
      // Nothing to open for this type: done.
      expect(opener.openPush('system_broadcast', family: false, signedIn: true), isTrue);
    });

    test('push tap payloads carry the type, the id and the book', () {
      expect(pushTapPayload('budget_exceeded', 'b1', 'family'), 'budget_exceeded|b1|family');
      expect(pushTapPayload('goal_achieved', 'g1', null), 'goal_achieved|g1|');
      expect(pushTapPayload('custom_insight_ready', null, 'family'), 'custom_insight_ready||family');
      expect(pushTapPayload('system_broadcast', null, null), isNull, reason: 'opens nothing');

      final family = parsePushTapPayload('budget_exceeded|b1|family')!;
      expect((family.type, family.goalId, family.family), ('budget_exceeded', 'b1', true));
      final personal = parsePushTapPayload('goal_achieved|g1|')!;
      expect((personal.type, personal.goalId, personal.family), ('goal_achieved', 'g1', false));
      // The older custom insight payload still reads.
      final old = parsePushTapPayload('custom_insight_ready|r1')!;
      expect((old.type, old.goalId, old.family), ('custom_insight_ready', 'r1', false));
      expect(parsePushTapPayload('3f2a9c0e-notification-id'), isNull);
      expect(parsePushTapPayload(null), isNull);
    });
  });

  group('layout: Myanmar 360, light and dark, long names', () {
    for (final mode in const [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('${mode.name}: the family screen (owner, everything open)', (tester) async {
        final family = _FakeFamily(overview: _overview(name: _longMyFamily, longName: _longMyName));
        await _pump(tester, const FamilyScreen(),
            family: family, locale: const Locale('my'), themeMode: mode, height: 2600);
        expect(tester.takeException(), isNull);
        await _tapAndSettle(tester, find.byKey(FamilyScreen.formerKey));
        expect(tester.takeException(), isNull);

        _expectOnScreen(tester, find.text(_longMyFamily), 360);
        _expectOnScreen(tester, find.text('$_longMyName Ko Ko'), 360);
        _expectOnScreen(tester, find.text('$_longMyName Uncle'), 360);
        _expectOnScreen(tester, find.text(_my.familyRoleOwner), 360);
        _expectOnScreen(tester, find.text(_my.familyDelete), 360);
        _expectOnScreen(tester, find.text(_my.familyOwnerLeaveHint), 360);
        _expectOnScreen(tester, find.text('daw.khin.myat.myat.noe.bahan@example.com'), 360);
        // Long names wrap rather than being cut.
        expect(tester.getSize(find.text('$_longMyName Ko Ko')).height, greaterThan(30));

        await _tapAndSettle(tester, find.byKey(FamilyScreen.memberKey('m2')));
        expect(tester.takeException(), isNull);
        _expectOnScreen(tester, find.byKey(FamilyMemberSheet.removeAdminKey), 360);
        _expectOnScreen(tester, find.byKey(FamilyMemberSheet.removeKey), 360);
        await _tapAndSettle(tester, find.byKey(FamilyMemberSheet.removeKey));
        expect(tester.takeException(), isNull);
        _expectOnScreen(tester, find.byKey(FamilyMemberSheet.removeConfirmKey), 360);
        Navigator.of(tester.element(find.byType(FamilyMemberSheet))).pop();
        await tester.pumpAndSettle();

        await _tapAndSettle(tester, find.byKey(FamilyScreen.deleteKey));
        expect(tester.takeException(), isNull);
        _expectOnScreen(tester, find.byKey(FamilyScreen.deleteConfirmKey), 360);
        Navigator.of(tester.element(find.byKey(FamilyScreen.deleteFieldKey))).pop();
        await tester.pumpAndSettle();

        await _tapAndSettle(tester, find.byKey(FamilyScreen.handOverKey));
        expect(tester.takeException(), isNull);
        _expectOnScreen(tester, find.byKey(FamilyScreen.handOverToKey('m3')), 360);
      });

      testWidgets('${mode.name}: no family (Free) and no family (Plus)', (tester) async {
        for (final paid in [false, true]) {
          await _pump(tester, const FamilyScreen(),
              family: _FakeFamily(mine: [_received(family: _longMyFamily, by: _longMyName)]),
              paid: paid,
              locale: const Locale('my'),
              themeMode: mode,
              height: 1200);
          expect(tester.takeException(), isNull);
          _expectOnScreen(tester, find.text(_my.familyCreateTitle), 360);
          _expectOnScreen(tester, find.byKey(FamilyScreen.createKey), 360);
          if (!paid) _expectOnScreen(tester, find.byKey(FamilyScreen.upgradeKey), 360);
          _expectOnScreen(tester, find.byKey(FamilyScreen.invitationsKey), 360);
        }
      });

      testWidgets('${mode.name}: the invite screen and the invitations', (tester) async {
        await _pump(tester, const FamilyInviteScreen(),
            family: _FakeFamily(overview: _overview(role: FamilyMember.roleAdmin, longName: _longMyName)),
            locale: const Locale('my'),
            themeMode: mode);
        expect(tester.takeException(), isNull);
        _expectOnScreen(tester, find.text('$_longMyName Ma Ma'), 360);
        _expectOnScreen(tester, find.byKey(FamilyInviteScreen.sendKey), 360);

        await _pump(tester, const FamilyInvitationsScreen(),
            family: _FakeFamily(mine: [_received(family: _longMyFamily, by: _longMyName)]),
            locale: const Locale('my'),
            themeMode: mode);
        expect(tester.takeException(), isNull);
        _expectOnScreen(tester, find.text(_longMyFamily), 360);
        _expectOnScreen(tester, find.byKey(FamilyInvitationsScreen.joinKey('inv1')), 360);
        _expectOnScreen(tester, find.byKey(FamilyInvitationsScreen.declineKey('inv1')), 360);
      });

      testWidgets('${mode.name}: English, very long names too', (tester) async {
        await _pump(tester, const FamilyScreen(),
            family: _FakeFamily(overview: _overview(name: _longEnName, longName: _longEnName)),
            themeMode: mode,
            height: 2600);
        expect(tester.takeException(), isNull);
        _expectOnScreen(tester, find.text(_longEnName), 360);
      });
    }
  });
}

/// A family whose request hasn't answered yet; [known] / [failed] answer it.
class _UnloadedFamily extends FamilyProvider {
  bool _known = false;
  bool _in = false;
  String? _err;

  void known({required bool inFamily}) {
    _known = true;
    _in = inFamily;
    _err = null;
    notifyListeners();
  }

  void failed() {
    _known = false;
    _err = 'offline';
    notifyListeners();
  }

  @override
  bool get loaded => _known;
  @override
  bool get inFamily => _in;
  @override
  Family? get family => _in ? const Family(id: 'f', name: 'Aung family') : null;
  @override
  String? get error => _err;
  @override
  Future<void> refresh() async {}
  @override
  Future<String?> loadMyInvites() async => null;
}
