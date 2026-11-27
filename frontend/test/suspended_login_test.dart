import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/api_service.dart';
import 'package:http/http.dart' as http;

void main() {
  // A suspended account is refused with HTTP 423 and {"detail": {"code", "message"}}; the installed app already
  // shows the server's message, so no app release is needed.
  test('a suspended sign-in shows the server message and keeps its code', () {
    final body = jsonEncode({
      'detail': {
        'code': 'account_suspended',
        'message': 'This account is suspended. Please contact us.',
      },
    });
    final error = ApiService.apiError(
      http.Response(body, 423, headers: {'content-type': 'application/json'}),
      'Login failed',
    );
    expect(error.message, 'This account is suspended. Please contact us.');
    expect(error.code, 'account_suspended');
    expect(error.statusCode, 423);
  });
}
