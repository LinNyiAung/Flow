import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every request made through ApiService in this file gets [_respond]'s answer.
/// ONE MockClient for the whole file: ApiService's client binds its inner
/// client the first time it is used.
late http.Response Function(http.Request) _respond;
final List<http.Request> _requests = [];
final _mock = MockClient((request) async {
  _requests.add(request);
  return _respond(request);
});

Future<T> _run<T>(Future<T> Function() call) => http.runWithClient(call, () => _mock);

Future<Object?> _errorOf(Future<void> Function() call) => _run(() async {
      try {
        await call();
        return null;
      } catch (e) {
        return e;
      }
    });

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

http.Response _refusal(int status, String code, String message) => _json({
      'detail': {'code': code, 'message': message}
    }, status);

Map<String, dynamic> _tx({Map<String, dynamic>? addedBy, List<String>? forWhom, String? transferId}) => {
      'id': 't1',
      'book_id': 'u1',
      'type': 'outflow',
      'main_category': 'Food',
      'sub_category': 'Groceries',
      'date': '2026-11-10T00:00:00Z',
      'description': null,
      'amount': 60000,
      'currency': 'mmk',
      'created_at': '2026-11-10T01:00:00Z',
      'updated_at': '2026-11-10T01:00:00Z',
      if (addedBy != null) 'added_by': addedBy,
      if (forWhom != null) 'for_whom': forWhom,
      if (transferId != null) 'transfer_id': transferId,
    };

Map<String, dynamic> _overview({String role = 'owner', bool readOnly = false}) => {
      'family': {'id': 'f1', 'name': 'Aung family', 'read_only': readOnly},
      'me': {'member_id': 'm1', 'role': role},
      'members': [
        {'id': 'm1', 'display_name': 'Dad', 'kind': 'account', 'role': role, 'status': 'active', 'is_me': true},
        {'id': 'm2', 'display_name': 'Ma Ma', 'kind': 'placeholder', 'role': null, 'status': 'active', 'is_me': false},
        {'id': 'm3', 'display_name': 'Ko Ko', 'kind': 'account', 'role': 'member', 'status': 'former', 'is_me': false},
      ],
      'invites': [
        {
          'id': 'i1',
          'email': 'mum@example.com',
          'link_member_id': 'm2',
          'status': 'pending',
          'created_at': '2026-11-10T00:00:00+00:00',
          'expires_at': '2026-11-24T00:00:00+00:00',
        }
      ],
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
  tearDown(() {
    ApiService.bookMode = BookMode.personal;
    ApiService.onNoFamily = null;
  });

  group('X-Book header', () {
    test('getTransactions: absent in Personal mode', () async {
      _respond = (_) => _json([]);
      await _run(() => ApiService.getTransactions());
      expect(_requests.single.headers.containsKey('X-Book'), isFalse);
      expect(_requests.single.headers['Authorization'], 'Bearer tok');
    });

    test('getTransactions: "family" in Family mode', () async {
      ApiService.bookMode = BookMode.family;
      _respond = (_) => _json([]);
      await _run(() => ApiService.getTransactions());
      expect(_requests.single.headers['X-Book'], 'family');
    });

    http.Response chatAnswer(http.Request _) =>
        http.Response('data: {"chunk": "Hi"}\n\ndata: {"done": true}\n\n', 200);

    test('streamChatMessage: absent in Personal mode', () async {
      _respond = chatAnswer;
      final chunks = await _run(() => ApiService.streamChatMessage(message: 'hello').toList());
      expect(chunks, ['Hi']);
      expect(_requests.single.url.path, '/api/chat/stream');
      expect(_requests.single.headers.containsKey('X-Book'), isFalse);
    });

    test('streamChatMessage: "family" in Family mode', () async {
      ApiService.bookMode = BookMode.family;
      _respond = chatAnswer;
      final chunks = await _run(() => ApiService.streamChatMessage(message: 'hello').toList());
      expect(chunks, ['Hi']);
      expect(_requests.single.headers['X-Book'], 'family');
    });
  });

  group('ApiException.code', () {
    test('parsed from detail.code, with the localized message', () async {
      _respond = (_) => _refusal(403, 'family_read_only', 'မိသားစု စာအုပ်ကို ဖတ်ရုံသာ ရပါသည်။');
      final error = await _errorOf(() => ApiService.getTransactions());
      expect(error, isA<ApiException>());
      error as ApiException;
      expect(error.code, 'family_read_only');
      expect(error.statusCode, 403);
      expect(error.message, 'မိသားစု စာအုပ်ကို ဖတ်ရုံသာ ရပါသည်။');
    });

    test('null for a plain string detail or a non-JSON page', () async {
      _respond = (_) => _json({'detail': 'Transaction not found'}, 404);
      final notFound = await _errorOf(() => ApiService.getTransaction('x')) as ApiException;
      expect(notFound.code, isNull);
      expect(notFound.message, 'Transaction not found');

      _respond = (_) => http.Response('<html>Bad gateway</html>', 502);
      final gateway = await _errorOf(() => ApiService.getTransaction('x')) as ApiException;
      expect(gateway.code, isNull);
    });

    test('the old constructors still work, and plan errors keep their code', () async {
      expect(ApiException('x').code, isNull);
      expect(ApiException('x', statusCode: 400).statusCode, 400);
      _respond = (_) => _json({
            'detail': {'code': 'plan_limit_reached', 'feature': 'chat', 'message': 'Used up'}
          }, 429);
      final error = await _errorOf(() => ApiService.getTransactions());
      expect(error, isA<PlanLimitException>());
      expect((error as ApiException).code, 'plan_limit_reached');
      expect((error as PlanLimitException).isLimitReached, isTrue);
    });
  });

  group('onNoFamily', () {
    late int calls;
    setUp(() {
      calls = 0;
      ApiService.onNoFamily = () => calls++;
    });

    test('fires on a 409 no_family in Family mode', () async {
      ApiService.bookMode = BookMode.family;
      _respond = (_) => _refusal(409, 'no_family', "You're not in a family.");
      final error = await _errorOf(() => ApiService.getTransactions()) as ApiException;
      expect(error.code, 'no_family');
      expect(calls, 1);
    });

    test('fires on the family routes\' 404 no_family in Family mode', () async {
      ApiService.bookMode = BookMode.family;
      _respond = (_) => _refusal(404, 'no_family', "You're not in a family.");
      await _errorOf(() => ApiService.renameFamily('New name'));
      expect(calls, 1);
    });

    test('does not fire in Personal mode', () async {
      _respond = (_) => _refusal(409, 'no_family', "You're not in a family.");
      await _errorOf(() => ApiService.createTransfer(
            direction: TransferDirection.toFamily,
            amount: 1000,
            currency: Currency.mmk,
            date: DateTime(2026, 11, 10),
          ));
      expect(calls, 0);
    });

    test('does not fire for another family code', () async {
      ApiService.bookMode = BookMode.family;
      _respond = (_) => _refusal(403, 'family_read_only', 'Read only');
      await _errorOf(() => ApiService.getTransactions());
      expect(calls, 0);
    });
  });

  group('transactions', () {
    test('a family entry carries who added it, who it was for and no transfer', () {
      final t = Transaction.fromJson(_tx(
        addedBy: {'member_id': 'm1', 'display_name': 'Dad'},
        forWhom: ['m2', 'm3'],
      ));
      expect(t.addedBy!.memberId, 'm1');
      expect(t.addedBy!.displayName, 'Dad');
      expect(t.forWhom, ['m2', 'm3']);
      expect(t.transferId, isNull);
      expect(t.isTransfer, isFalse);
    });

    test('a transfer leg is marked; a personal entry has no family fields', () {
      final leg = Transaction.fromJson(_tx(transferId: 'tr1', forWhom: []));
      expect(leg.isTransfer, isTrue);
      expect(leg.transferId, 'tr1');

      final personal = Transaction.fromJson(_tx());
      expect(personal.addedBy, isNull);
      expect(personal.forWhom, isEmpty);
      expect(personal.isTransfer, isFalse);
    });

    test('createTransaction sends for_whom only when given', () async {
      _respond = (_) => _json(_tx());
      await _run(() => ApiService.createTransaction(
            type: TransactionType.outflow,
            mainCategory: 'Food',
            subCategory: 'Groceries',
            date: DateTime(2026, 11, 10),
            amount: 60000,
            currency: Currency.mmk,
            forWhom: ['m2', 'm3'],
          ));
      await _run(() => ApiService.createTransaction(
            type: TransactionType.outflow,
            mainCategory: 'Food',
            subCategory: 'Groceries',
            date: DateTime(2026, 11, 10),
            amount: 60000,
            currency: Currency.mmk,
          ));
      expect(jsonDecode(_requests[0].body)['for_whom'], ['m2', 'm3']);
      expect((jsonDecode(_requests[1].body) as Map).containsKey('for_whom'), isFalse);
    });

    test('updateTransaction can make an entry Whole family ([])', () async {
      _respond = (_) => _json(_tx());
      await _run(() => ApiService.updateTransaction(transactionId: 't1', forWhom: const []));
      expect(jsonDecode(_requests.single.body), {'for_whom': []});
    });
  });

  test('GET /api/plan: the family limits', () {
    final status = PlanStatus.fromJson({
      'plan': 'plus',
      'family': {'max_members': 6, 'max_placeholders': 20},
    });
    expect(status.familyMaxMembers, 6);
    expect(status.familyMaxPlaceholders, 20);
    final older = PlanStatus.fromJson({'plan': 'free'});
    expect(older.familyMaxMembers, isNull);
    expect(older.familyMaxPlaceholders, isNull);
    expect(status.withUpgradeRequest(null).familyMaxMembers, 6);
  });

  group('family endpoints', () {
    test('getFamily: the overview', () async {
      _respond = (_) => _json(_overview(role: 'admin', readOnly: true));
      final o = await _run(() => ApiService.getFamily());
      expect(_requests.single.method, 'GET');
      expect(_requests.single.url.path, '/api/family');
      expect(o.family!.id, 'f1');
      expect(o.family!.name, 'Aung family');
      expect(o.family!.readOnly, isTrue);
      expect(o.myMemberId, 'm1');
      expect(o.myRole, 'admin');
      expect(o.members.map((m) => m.id), ['m1', 'm2', 'm3']);
      final placeholder = o.members[1];
      expect(placeholder.displayName, 'Ma Ma');
      expect(placeholder.isPlaceholder, isTrue);
      expect(placeholder.role, isNull);
      expect(placeholder.isMe, isFalse);
      expect(o.members[2].isFormer, isTrue);
      expect(o.members[0].isMe, isTrue);
      expect(o.invites.single.email, 'mum@example.com');
      expect(o.invites.single.linkMemberId, 'm2');
      expect(o.invites.single.expiresAt!.isAtSameMomentAs(DateTime.utc(2026, 11, 24)), isTrue);
      expect(o.maxMembers, 6);
      expect(o.maxPlaceholders, 20);
    });

    test('getFamily: outside a family', () async {
      _respond = (_) => _json({'family': null});
      final o = await _run(() => ApiService.getFamily());
      expect(o.family, isNull);
      expect(o.members, isEmpty);
    });

    test('each call goes to its route with its body', () async {
      _respond = (_) => _json(_overview());
      await _run(() async {
        await ApiService.createFamily('Aung family');
        await ApiService.renameFamily('Aung home');
        await ApiService.deleteFamily('Aung home');
        await ApiService.addFamilyPlaceholder('Grandma');
        await ApiService.updateFamilyMember('m2', displayName: 'Ma Ma Lay');
        await ApiService.updateFamilyMember('m4', role: 'admin');
        await ApiService.removeFamilyMember('m2');
        await ApiService.leaveFamily();
        await ApiService.transferFamilyOwnership('m4');
        await ApiService.cancelFamilyInvite('i1');
        await ApiService.acceptFamilyInvite('i2');
      });
      String line(http.Request r) => '${r.method} ${r.url.path} ${r.body}';
      expect(_requests.map(line).toList(), [
        'POST /api/family {"name":"Aung family"}',
        'PATCH /api/family {"name":"Aung home"}',
        'DELETE /api/family {"confirm_name":"Aung home"}',
        'POST /api/family/placeholders {"display_name":"Grandma"}',
        'PATCH /api/family/members/m2 {"display_name":"Ma Ma Lay"}',
        'PATCH /api/family/members/m4 {"role":"admin"}',
        'DELETE /api/family/members/m2 ',
        'POST /api/family/leave ',
        'POST /api/family/transfer-ownership {"member_id":"m4"}',
        'DELETE /api/family/invites/i1 ',
        'POST /api/family/invites/i2/accept ',
      ]);
    });

    test('invites: create, mine, decline', () async {
      _respond = (r) {
        if (r.url.path == '/api/family/invites' && r.method == 'POST') {
          return _json({
            'id': 'i9',
            'email': 'mum@example.com',
            'link_member_id': 'm2',
            'status': 'pending',
            'created_at': '2026-11-10T00:00:00+00:00',
            'expires_at': '2026-11-24T00:00:00+00:00',
          });
        }
        if (r.url.path == '/api/family/invites/mine') {
          return _json({
            'invites': [
              {
                'id': 'i5',
                'family_id': 'f2',
                'family_name': 'U Family',
                'invited_by': 'Daw Mya',
                'created_at': '2026-11-10T00:00:00+00:00',
                'expires_at': '2026-11-24T00:00:00+00:00',
              }
            ]
          });
        }
        return _json({'status': 'declined'});
      };
      final invite = await _run(() => ApiService.createFamilyInvite('Mum@Example.com', linkMemberId: 'm2'));
      expect(jsonDecode(_requests[0].body), {'email': 'Mum@Example.com', 'link_member_id': 'm2'});
      expect(invite.id, 'i9');
      expect(invite.linkMemberId, 'm2');

      final mine = await _run(() => ApiService.getMyFamilyInvites());
      expect(mine.single.familyName, 'U Family');
      expect(mine.single.invitedBy, 'Daw Mya');
      expect(mine.single.familyId, 'f2');

      await _run(() => ApiService.declineFamilyInvite('i5'));
      expect(_requests.last.method, 'POST');
      expect(_requests.last.url.path, '/api/family/invites/i5/decline');
    });

    test('createFamilyInvite leaves link_member_id out when not linked', () async {
      _respond = (_) => _json({'id': 'i9', 'email': 'a@b.co', 'link_member_id': null, 'status': 'pending'});
      await _run(() => ApiService.createFamilyInvite('a@b.co'));
      expect(jsonDecode(_requests.single.body), {'email': 'a@b.co'});
    });

    test('breakdown: whole days, the currency, the rows', () async {
      _respond = (_) => _json({
            'currency': 'mmk',
            'total_spent': 90000,
            'rows': [
              {'member_id': null, 'display_name': 'Whole family', 'status': 'active', 'amount': 50000},
              {'member_id': 'm2', 'display_name': 'Ma Ma', 'status': 'former', 'amount': 40000},
            ],
          });
      final b = await _run(() => ApiService.getFamilyBreakdown(
            DateTime(2026, 11, 1, 15),
            DateTime(2026, 11, 30),
            currency: Currency.mmk,
          ));
      final r = _requests.single;
      expect(r.url.path, '/api/family/breakdown');
      expect(r.url.queryParameters['start_date'], '2026-11-01T00:00:00.000Z');
      expect(r.url.queryParameters['end_date'], '2026-11-30T00:00:00.000Z');
      expect(r.url.queryParameters['currency'], 'mmk');
      expect(b.currency, Currency.mmk);
      expect(b.totalSpent, 90000);
      expect(b.rows.first.isWholeFamily, isTrue);
      expect(b.rows.first.memberId, isNull);
      expect(b.rows.last.memberId, 'm2');
      expect(b.rows.last.displayName, 'Ma Ma');
      expect(b.rows.last.status, 'former');
      expect(b.rows.last.amount, 40000);
    });

    test('transfers: create and undo', () async {
      _respond = (r) => r.method == 'POST'
          ? _json({'transfer_id': 'tr1', 'personal_transaction_id': 'p1', 'family_transaction_id': 'f1'})
          : _json({'message': 'Transfer undone', 'transfer_id': 'tr1'});
      final result = await _run(() => ApiService.createTransfer(
            direction: TransferDirection.toPersonal,
            amount: 5000,
            currency: Currency.mmk,
            date: DateTime(2026, 11, 10, 9, 30),
            description: 'Market cash',
          ));
      final body = jsonDecode(_requests[0].body) as Map;
      expect(_requests[0].url.path, '/api/transfers');
      expect(body['direction'], 'to_personal');
      expect(body['amount'], 5000);
      expect(body['currency'], 'mmk');
      expect(body['date'], DateTime(2026, 11, 10, 9, 30).toIso8601String());
      expect(body['description'], 'Market cash');
      expect(result.transferId, 'tr1');
      expect(result.personalTransactionId, 'p1');
      expect(result.familyTransactionId, 'f1');

      await _run(() => ApiService.undoTransfer('tr1'));
      expect(_requests[1].method, 'DELETE');
      expect(_requests[1].url.path, '/api/transfers/tr1');
    });

    test('a refusal keeps its code (transfer_insufficient)', () async {
      _respond = (_) => _refusal(400, 'transfer_insufficient', 'Not enough money in that wallet.');
      final error = await _errorOf(() => ApiService.createTransfer(
            direction: TransferDirection.toFamily,
            amount: 5000,
            currency: Currency.mmk,
            date: DateTime(2026, 11, 10),
          )) as ApiException;
      expect(error.code, 'transfer_insufficient');
      expect(error.message, 'Not enough money in that wallet.');
    });
  });
}
