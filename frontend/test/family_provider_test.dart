import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ONE MockClient for the file (ApiService binds its inner client once).
late Future<http.Response> Function(http.Request) _respond;
final List<http.Request> _requests = [];
final _mock = MockClient((request) {
  _requests.add(request);
  return _respond(request);
});

Future<T> _run<T>(Future<T> Function() call) => http.runWithClient(call, () => _mock);

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _overview({String role = 'owner', bool readOnly = false, String name = 'Aung family'}) => {
      'family': {'id': 'f1', 'name': name, 'read_only': readOnly},
      'me': {'member_id': 'm1', 'role': role},
      'members': [
        {'id': 'm1', 'display_name': 'Dad', 'kind': 'account', 'role': role, 'status': 'active', 'is_me': true},
        {'id': 'm2', 'display_name': 'Ma Ma', 'kind': 'placeholder', 'role': null, 'status': 'active', 'is_me': false},
        {'id': 'm3', 'display_name': 'Ko Ko', 'kind': 'account', 'role': 'member', 'status': 'former', 'is_me': false},
      ],
      'invites': [],
      'limits': {'max_members': 6, 'max_placeholders': 20},
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'access_token': 'tok'});
    ApiService.currentLanguage = 'en';
    ApiService.bookMode = BookMode.personal;
    ApiService.onNoFamily = null;
    _requests.clear();
  });

  test('refresh loads the family, the members and my role', () async {
    _respond = (_) async => _json(_overview(role: 'admin', readOnly: true));
    final p = FamilyProvider();
    expect(p.loaded, isFalse);
    expect(p.inFamily, isFalse);

    await _run(p.refresh);

    expect(p.loaded, isTrue);
    expect(p.inFamily, isTrue);
    expect(p.family!.name, 'Aung family');
    expect(p.readOnly, isTrue);
    expect(p.me!.id, 'm1');
    expect(p.isAdmin, isTrue);
    expect(p.isOwner, isFalse);
    expect(p.members, hasLength(3));
    expect(p.activeMembers.map((m) => m.id), ['m1', 'm2']);
    expect(p.maxMembers, 6);
    expect(p.maxPlaceholders, 20);
  });

  test('the owner is an admin too; a member is neither', () async {
    final p = FamilyProvider();
    _respond = (_) async => _json(_overview(role: 'owner'));
    await _run(p.refresh);
    expect(p.isOwner, isTrue);
    expect(p.isAdmin, isTrue);

    _respond = (_) async => _json(_overview(role: 'member'));
    await _run(p.refresh);
    expect(p.isOwner, isFalse);
    expect(p.isAdmin, isFalse);
  });

  test('outside a family: loaded, not in a family', () async {
    _respond = (_) async => _json({'family': null});
    final p = FamilyProvider();
    await _run(p.refresh);
    expect(p.loaded, isTrue);
    expect(p.inFamily, isFalse);
    expect(p.me, isNull);
    expect(p.members, isEmpty);
    expect(p.isAdmin, isFalse);
  });

  test('a failed refresh keeps what is shown and is not "loaded"', () async {
    _respond = (_) async => http.Response('<html>Bad gateway</html>', 502);
    final p = FamilyProvider();
    await _run(p.refresh);
    expect(p.loaded, isFalse);
    expect(p.error, isNotNull);
  });

  test('refresh does nothing when nobody is signed in', () async {
    SharedPreferences.setMockInitialValues({});
    _respond = (_) async => _json(_overview());
    final p = FamilyProvider();
    await _run(p.refresh);
    expect(_requests, isEmpty);
    expect(p.loaded, isFalse);
  });

  test('a mutation returns null and applies the new overview', () async {
    _respond = (_) async => _json(_overview(name: 'Aung home'));
    final p = FamilyProvider();
    final error = await _run(() => p.renameFamily('Aung home'));
    expect(error, isNull);
    expect(p.family!.name, 'Aung home');
    expect(p.loaded, isTrue);
  });

  test("a refusal returns the server's localized message", () async {
    ApiService.currentLanguage = 'my';
    _respond = (_) async => _json({
          'detail': {'code': 'family_full', 'message': 'မိသားစု ပြည့်နေပါပြီ။'}
        }, 409);
    final p = FamilyProvider();
    expect(await _run(() => p.invite('a@b.co')), 'မိသားစု ပြည့်နေပါပြီ။');
  });

  test('anything else falls back to a generic message in the app language', () async {
    ApiService.currentLanguage = 'my';
    _respond = (_) async => http.Response('<html>Bad gateway</html>', 502);
    final p = FamilyProvider();
    expect(await _run(() => p.addPlaceholder('Grandma')),
        AppLocalizations(const Locale('my')).genericErrorOccurred);
  });

  test('leave and deleteFamily clear the family', () async {
    final p = FamilyProvider();
    _respond = (_) async => _json(_overview());
    await _run(p.refresh);
    _respond = (_) async => _json({'family': null});
    expect(await _run(p.leave), isNull);
    expect(p.inFamily, isFalse);

    _respond = (_) async => _json(_overview());
    await _run(p.refresh);
    _respond = (_) async => _json({'family': null});
    expect(await _run(() => p.deleteFamily('Aung family')), isNull);
    expect(p.inFamily, isFalse);
  });

  test('invite adds the pending invite (replacing one to the same address)', () async {
    final p = FamilyProvider();
    _respond = (_) async => _json(_overview());
    await _run(p.refresh);
    var n = 0;
    _respond = (_) async => _json({
          'id': 'i${++n}',
          'email': 'mum@example.com',
          'link_member_id': null,
          'status': 'pending',
          'created_at': '2026-11-10T00:00:00+00:00',
          'expires_at': '2026-11-24T00:00:00+00:00',
        });
    expect(await _run(() => p.invite('mum@example.com')), isNull);
    expect(await _run(() => p.invite('Mum@Example.com')), isNull);
    expect(p.invites.map((i) => i.id), ['i2']);
  });

  test('my invites: load, accept (joins), decline (drops it)', () async {
    final p = FamilyProvider();
    Map<String, dynamic> inv(String id) => {
          'id': id,
          'family_id': 'f1',
          'family_name': 'Aung family',
          'invited_by': 'Dad',
          'created_at': '2026-11-10T00:00:00+00:00',
          'expires_at': '2026-11-24T00:00:00+00:00',
        };
    _respond = (_) async => _json({
          'invites': [inv('i1'), inv('i2')]
        });
    expect(await _run(p.loadMyInvites), isNull);
    expect(p.myInvites.map((i) => i.id), ['i1', 'i2']);

    _respond = (_) async => _json({'status': 'declined'});
    expect(await _run(() => p.declineInvite('i2')), isNull);
    expect(p.myInvites.map((i) => i.id), ['i1']);

    _respond = (_) async => _json(_overview(role: 'member'));
    expect(await _run(() => p.acceptInvite('i1')), isNull);
    expect(p.myInvites, isEmpty);
    expect(p.inFamily, isTrue);
  });

  test('reset clears everything and drops a late refresh', () async {
    final p = FamilyProvider();
    _respond = (_) async => _json(_overview());
    await _run(p.refresh);

    final gate = Completer<http.Response>();
    _respond = (_) => gate.future;
    final stale = _run(p.refresh);
    await pumpEventQueue();
    p.reset();
    expect(p.inFamily, isFalse);
    expect(p.loaded, isFalse);
    expect(p.isLoading, isFalse);
    gate.complete(_json(_overview()));
    await stale;
    expect(p.inFamily, isFalse, reason: "the previous user's family must not come back");
    expect(p.loaded, isFalse);
  });

  test('a refresh started before a mutation never overwrites its result', () async {
    final p = FamilyProvider();
    final gate = Completer<http.Response>();
    _respond = (_) => gate.future;
    final slow = _run(p.refresh);
    await pumpEventQueue();

    _respond = (_) async => _json(_overview(name: 'Aung home'));
    expect(await _run(() => p.renameFamily('Aung home')), isNull);
    gate.complete(_json(_overview(name: 'Aung family')));
    await slow;
    expect(p.family!.name, 'Aung home');
    expect(p.isLoading, isFalse);
  });
}
