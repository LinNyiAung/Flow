import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/models/app_version.dart';
import 'package:frontend/models/budget.dart';
import 'package:frontend/models/chat.dart';
import 'package:frontend/models/feedback.dart';
import 'package:frontend/models/goal.dart';
import 'package:frontend/models/insight.dart';
import 'package:frontend/models/notification.dart';
import 'package:frontend/models/notification_preferences.dart';
import 'package:frontend/models/recurring_transaction.dart';
import 'package:frontend/models/report.dart';
import 'package:frontend/models/voice_image_models.dart';
import 'package:frontend/utils/date_parsing.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../models/transaction.dart';

/// Error raised for any failed API call. [toString] keeps the historical
/// `Exception: message` shape so existing `replaceAll('Exception: ', '')`
/// call sites keep producing a clean message.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'Exception: $message';
}

/// Login/protected call rejected because the account's e-mail address has
/// not been verified yet (HTTP 403).
class EmailNotVerifiedException extends ApiException {
  EmailNotVerifiedException(super.message) : super(statusCode: 403);
}

/// HTTP client used for every API call: applies per-endpoint timeouts and
/// reports invalidated sessions (401 / unverified 403) to [ApiService].
class _ApiClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  static const Duration defaultTimeout = Duration(seconds: 20);
  static const Duration longTimeout = Duration(seconds: 90);

  /// Auth / app-version calls are the first requests after app start, so they
  /// must survive a Render cold start (30–60 s).
  static const Duration coldStartTimeout = Duration(seconds: 60);

  /// Insights GET can generate AND translate in a single request.
  static const Duration insightsTimeout = Duration(seconds: 180);

  static const List<String> _coldStartPrefixes = [
    '/api/auth/',
    '/api/app/check-version',
  ];

  /// Endpoints that run AI generation, uploads or report rendering.
  static const List<String> _longRunningPrefixes = [
    '/api/chat',
    '/api/transactions/transcribe-audio',
    '/api/transactions/extract',
    '/api/transactions/batch-create',
    '/api/budgets/ai-suggest',
    '/api/reports',
  ];

  static Duration timeoutFor(Uri url) {
    final path = url.path;
    if (path.startsWith('/api/insights')) return insightsTimeout;
    for (final prefix in _longRunningPrefixes) {
      if (path.startsWith(prefix)) return longTimeout;
    }
    for (final prefix in _coldStartPrefixes) {
      if (path.startsWith(prefix)) return coldStartTimeout;
    }
    return defaultTimeout;
  }

  /// Sends [request] with ONE overall deadline covering the connection,
  /// upload, headers AND the body download (previously only `send()` was
  /// timed, so a server that stalled mid-body hung the caller forever).
  ///
  /// The body is buffered here; every caller of this client reads the whole
  /// body anyway. The streaming chat uses its own client and is not
  /// affected (it applies an idle timeout per chunk instead).
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final timeout = timeoutFor(request.url);
    final stopwatch = Stopwatch()..start();
    http.StreamedResponse response;
    Uint8List bytes;
    try {
      response = await _inner.send(request).timeout(timeout);
      final remaining = timeout - stopwatch.elapsed;
      bytes = await readBodyWithTimeout(
        response.stream,
        remaining > Duration.zero ? remaining : Duration.zero,
      );
    } on TimeoutException {
      throw ApiException(ApiService.timeoutMessage);
    } on SocketException {
      throw ApiException(ApiService.networkErrorMessage);
    } on http.ClientException catch (e) {
      throw ApiException('${ApiService.networkErrorMessage} (${e.message})');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      await ApiService.checkSessionInvalidated(
        request,
        response.statusCode,
        utf8.decode(bytes, allowMalformed: true),
      );
    }
    return http.StreamedResponse(
      http.ByteStream.fromBytes(bytes),
      response.statusCode,
      contentLength: bytes.length,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }
}

/// Reads [stream] to the end, failing with a [TimeoutException] (and
/// cancelling the subscription, which releases the connection) if it has
/// not finished within [timeout].
@visibleForTesting
Future<Uint8List> readBodyWithTimeout(Stream<List<int>> stream, Duration timeout) {
  final completer = Completer<Uint8List>();
  final builder = BytesBuilder(copy: false);
  late final StreamSubscription<List<int>> subscription;
  final timer = Timer(timeout, () {
    subscription.cancel();
    if (!completer.isCompleted) {
      completer.completeError(TimeoutException('Response body timed out', timeout));
    }
  });
  subscription = stream.listen(
    builder.add,
    onError: (Object error, StackTrace stackTrace) {
      timer.cancel();
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    },
    onDone: () {
      timer.cancel();
      if (!completer.isCompleted) completer.complete(builder.takeBytes());
    },
    cancelOnError: true,
  );
  return completer.future;
}

class ApiService {
  /// Override at build/run time, e.g.
  /// `flutter run --dart-define=API_BASE_URL=http://10.80.21.130:8000`.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.80.21.130:8000',
  );

  static final _ApiClient _client = _ApiClient();

  /// Client-side timeout applied to a request for [url].
  @visibleForTesting
  static Duration timeoutFor(Uri url) => _ApiClient.timeoutFor(url);

  /// True when [error] means the stored session is definitely invalid
  /// (401, or 403 "Email not verified") — as opposed to a timeout, network
  /// failure or server error, after which the session should be kept.
  static bool isSessionRejection(Object error) {
    if (error is EmailNotVerifiedException) return true;
    if (error is! ApiException) return false;
    if (error.statusCode == 401) return true;
    return error.statusCode == 403 &&
        error.message.toLowerCase().contains('email not verified');
  }

  /// Current UI language ('en' | 'my'); kept in sync by the app so that
  /// services without a BuildContext can localize messages / requests.
  static String currentLanguage = 'en';

  static AppLocalizations get _strings =>
      AppLocalizations(Locale(currentLanguage));

  static String get timeoutMessage => _strings.errorRequestTimedOut;

  static String get networkErrorMessage => _strings.errorNetworkUnreachable;

  /// Invoked (once per token) when the backend reports that the stored
  /// session is no longer valid, with the token the rejected request used
  /// (always the currently stored token). Set by the app to log out and
  /// show login; it must only remove that exact token.
  static void Function(String token)? onSessionExpired;

  /// Token already reported to [onSessionExpired] (dedupes the burst of
  /// 401s that parallel requests produce).
  static String? _notifiedExpiredToken;

  /// Auth endpoints whose 401/403 means "wrong credentials / unverified",
  /// not "session expired".
  static const List<String> _sessionCheckExemptPaths = [
    '/api/auth/login',
    '/api/auth/register',
    '/api/auth/resend-verification',
    '/api/auth/forgot-password',
    '/api/auth/change-password',
    '/api/auth/delete-account',
    '/api/auth/fcm-token',
  ];

  /// The bearer token of an `Authorization` header value, or null.
  static String? _bearerToken(String? authorization) {
    if (authorization == null) return null;
    const prefix = 'Bearer ';
    if (!authorization.startsWith(prefix)) return null;
    final token = authorization.substring(prefix.length).trim();
    return token.isEmpty ? null : token;
  }

  /// Reports a 401 / unverified 403 to [onSessionExpired] — but only when
  /// the request was authenticated with the token that is stored NOW. A
  /// late 401 for an older token (e.g. a request started before logout +
  /// login) must never sign out the fresh session.
  @visibleForTesting
  static Future<void> checkSessionInvalidated(
    http.BaseRequest request,
    int statusCode,
    String body,
  ) async {
    final usedToken = _bearerToken(request.headers['Authorization']);
    if (usedToken == null) return;
    final path = request.url.path;
    if (_sessionCheckExemptPaths.any(path.startsWith)) return;
    final isUnverified =
        statusCode == 403 && body.toLowerCase().contains('email not verified');
    if (statusCode != 401 && !isUnverified) return;
    if (await getToken() != usedToken) return;
    if (_notifiedExpiredToken == usedToken) return;
    _notifiedExpiredToken = usedToken;
    onSessionExpired?.call(usedToken);
  }

  /// Extracts a human-readable message from an error response:
  /// * `detail` string (400 business errors, 401/403/404, ...)
  /// * `detail` list of `{loc, msg}` (422 validation errors) → joined msgs
  /// * non-JSON bodies (proxy / 5xx pages) → [fallback]
  static String errorMessage(http.Response response, String fallback) {
    final body = response.body.trim();
    if (body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        dynamic detail;
        if (decoded is Map) {
          detail = decoded['detail'] ?? decoded['message'] ?? decoded['error'];
        } else {
          detail = decoded;
        }
        final message = _detailToMessage(detail);
        if (message != null && message.trim().isNotEmpty) return message.trim();
      } on FormatException {
        // Non-JSON body (HTML error page, plain text from a proxy, ...).
      }
    }
    if (response.statusCode >= 500) {
      return '$fallback (${response.statusCode})';
    }
    return fallback;
  }

  static String? _detailToMessage(dynamic detail) {
    if (detail == null) return null;
    if (detail is String) return detail;
    if (detail is List) {
      final messages = <String>[];
      for (final item in detail) {
        if (item is Map && item['msg'] != null) {
          var msg = item['msg'].toString().replaceFirst('Value error, ', '');
          final loc = item['loc'];
          if (loc is List && loc.isNotEmpty) {
            final field = loc.last.toString();
            if (field != 'body' && int.tryParse(field) == null) {
              msg = '$field: $msg';
            }
          }
          messages.add(msg);
        } else if (item != null) {
          messages.add(item.toString());
        }
      }
      return messages.isEmpty ? null : messages.join('\n');
    }
    if (detail is Map && detail['msg'] != null) return detail['msg'].toString();
    return detail.toString();
  }

  static ApiException apiError(http.Response response, String fallback) {
    return ApiException(
      errorMessage(response, fallback),
      statusCode: response.statusCode,
    );
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', token);
  }

  static Future<void> removeToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
  }

  /// Removes the stored token only if it is still [token], so a token saved
  /// by a newer login is never deleted by an older logout / failed check.
  static Future<void> removeTokenIfMatches(String token) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('access_token') == token) {
      await prefs.remove('access_token');
    }
  }

  static Future<Map<String, String>> _getHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ==================== APP VERSION ====================

  /// Check whether the current installed version is up to date.
  /// [currentVersion] e.g. "1.2.0"
  /// [platform] "android" or "ios"
  static Future<VersionCheckResponse> checkAppVersion({
    required String currentVersion,
    required String platform,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/app/check-version'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'current_version': currentVersion,
        'platform': platform,
      }),
    );

    if (response.statusCode == 200) {
      return VersionCheckResponse.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to check app version');
    }
  }

  // ==================== FCM ====================

  static Future<void> updateFCMToken(String fcmToken) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/auth/update-fcm-token'),
      headers: await _getHeaders(),
      body: jsonEncode({'fcm_token': fcmToken}),
    );

    if (response.statusCode != 200) {
      throw apiError(response, 'Failed to update FCM token');
    }
  }

  /// Unregisters this device's FCM token so the previous user stops
  /// receiving pushes after logout. Must be called while the token is valid.
  static Future<void> deleteFCMToken({String? authToken}) async {
    final headers = await _getHeaders();
    if (authToken != null) headers['Authorization'] = 'Bearer $authToken';
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/auth/fcm-token'),
      headers: headers,
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw apiError(response, 'Failed to remove FCM token');
    }
  }

  /// Always succeeds server-side (no account enumeration).
  static Future<void> resendVerificationEmail({required String email}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/auth/resend-verification'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );

    if (response.statusCode != 200) {
      throw apiError(response, 'Failed to resend verification email');
    }
  }

  // Auth methods (keeping existing ones)
  static Future<AuthResponse> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final authResponse = AuthResponse.fromJson(jsonDecode(response.body));
      // Unverified accounts get a token back, but every protected endpoint
      // rejects it until the e-mail is verified — never store it.
      if (authResponse.user.isVerified) {
        await saveToken(authResponse.accessToken);
      }
      return authResponse;
    } else {
      throw apiError(response, 'Registration failed');
    }
  }

  static Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final authResponse = AuthResponse.fromJson(jsonDecode(response.body));
      if (!authResponse.user.isVerified) {
        throw EmailNotVerifiedException('Email not verified');
      }
      await saveToken(authResponse.accessToken);
      return authResponse;
    } else if (response.statusCode == 403) {
      throw EmailNotVerifiedException(
        errorMessage(response, 'Email not verified'),
      );
    } else {
      throw apiError(response, 'Login failed');
    }
  }

  static Future<void> requestPasswordResetOtp({required String email}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/auth/forgot-password/request-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );

    if (response.statusCode != 200) {
      throw apiError(response, 'Failed to send OTP');
    }
  }

  static Future<String> verifyPasswordResetOtp({
    required String email,
    required String otp,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/auth/forgot-password/verify-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'otp': otp}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['reset_token'] as String;
    } else {
      throw apiError(response, 'Invalid OTP');
    }
  }

  static Future<void> resetPassword({
    required String email,
    required String resetToken,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/auth/forgot-password/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'reset_token': resetToken,
        'new_password': newPassword,
        'confirm_password': confirmPassword,
      }),
    );

    if (response.statusCode != 200) {
      throw apiError(response, 'Failed to reset password');
    }
  }

  static Future<void> updateLanguage(String language) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/api/auth/language'),
      headers: await _getHeaders(),
      body: jsonEncode({'language': language}),
    );

    if (response.statusCode != 200) {
      throw apiError(response, 'Failed to update language');
    }
  }

  static Future<void> deleteAccount({required String password}) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/auth/delete-account'),
      headers: await _getHeaders(),
      body: jsonEncode({'password': password}),
    );

    if (response.statusCode == 200) {
      await removeToken();
      return;
    } else {
      throw apiError(response, 'Failed to delete account');
    }
  }

  static Future<User> getCurrentUser() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/auth/me'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to get user info');
    }
  }

  static Future<User> updateDefaultCurrency({
    required Currency currency,
  }) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/api/auth/currency'),
      headers: await _getHeaders(),
      body: jsonEncode({'default_currency': currency.name}),
    );

    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to update currency');
    }
  }

  static Future<User> updateProfile({required String name}) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/api/auth/profile'),
      headers: await _getHeaders(),
      body: jsonEncode({'name': name}),
    );

    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to update profile');
    }
  }

  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/api/auth/change-password'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
        'confirm_password': confirmPassword,
      }),
    );

    if (response.statusCode == 200) {
      // Changing the password revokes every previously issued token; the
      // response carries a fresh one that must replace the stored token.
      try {
        final data = jsonDecode(response.body);
        final newToken = data is Map ? data['access_token'] : null;
        if (newToken is String && newToken.isNotEmpty) {
          await saveToken(newToken);
        }
      } on FormatException {
        // Older backend without a token in the response.
      }
      return;
    } else {
      throw apiError(response, 'Failed to change password');
    }
  }

  // ==================== SUBSCRIPTION ====================

  static Future<User> claimFreeTrial() async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/auth/claim-free-trial'),
      headers: await _getHeaders(),
    );
 
    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to claim free trial');
    }
  }

  static Future<SubscriptionStatus> getSubscriptionStatus() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/auth/subscription-status'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return SubscriptionStatus.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to get subscription status');
    }
  }

  static Future<bool> canAccessPremiumFeature() async {
    try {
      final status = await getSubscriptionStatus();
      return status.isPremium;
    } catch (e) {
      return false;
    }
  }

  // Notification Preferences
  static Future<NotificationPreferencesResponse>
  getNotificationPreferences() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/notifications/preferences'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return NotificationPreferencesResponse.fromJson(
        jsonDecode(response.body),
      );
    } else {
      throw apiError(response, 'Failed to get notification preferences');
    }
  }

  static Future<NotificationPreferencesResponse> updateNotificationPreferences({
    required Map<String, bool> preferences,
  }) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/api/notifications/preferences'),
      headers: await _getHeaders(),
      body: jsonEncode({'preferences': preferences}),
    );

    if (response.statusCode == 200) {
      return NotificationPreferencesResponse.fromJson(
        jsonDecode(response.body),
      );
    } else {
      throw apiError(response, 'Failed to update notification preferences');
    }
  }

  static Future<void> resetNotificationPreferences() async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/notifications/preferences/reset'),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      throw apiError(response, 'Failed to reset notification preferences');
    }
  }

  // Transaction CRUD methods
  static Future<Transaction> createTransaction({
    required TransactionType type,
    required String mainCategory,
    required String subCategory,
    required DateTime date,
    String? description,
    required double amount,
    required Currency currency,
    TransactionRecurrence? recurrence,
  }) async {
    final body = {
      'type': type.name,
      'main_category': mainCategory,
      'sub_category': subCategory,
      'date': date.toIso8601String(),
      'description': description,
      'amount': amount,
      'currency': currency.name, // NEW
    };
    if (recurrence != null) {
      body['recurrence'] = recurrence.toJson();
    }
    final response = await _client.post(
      Uri.parse('$baseUrl/api/transactions'),
      headers: await _getHeaders(),
      body: jsonEncode(body),
    );
    if (response.statusCode == 200) {
      return Transaction.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to create transaction');
    }
  }

  static Future<void> disableTransactionRecurrence(String transactionId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/transactions/$transactionId/disable-recurrence'),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      throw apiError(response, 'Failed to disable recurrence');
    }
  }

  static Future<void> disableParentTransactionRecurrence(
    String transactionId,
  ) async {
    final response = await _client.post(
      Uri.parse(
        '$baseUrl/api/transactions/$transactionId/disable-parent-recurrence',
      ),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      throw apiError(response, 'Failed to disable parent recurrence');
    }
  }

  static Future<List<DateTime>> previewRecurrence({
    required TransactionRecurrence recurrence,
    required DateTime startDate,
    int count = 5,
  }) async {
    if (recurrence.config == null) {
      throw Exception('Recurrence config is required');
    }

    // Build the request body with all config fields. Dates are wall-clock
    // values (same convention as transaction dates): keep the local fields
    // and tag them as UTC rather than shifting by the device offset.
    final requestBody = {
      'start_date': wallClockToUtcIso(startDate),
      'frequency': recurrence.config!.frequency.name,
      if (recurrence.config!.dayOfWeek != null)
        'day_of_week': recurrence.config!.dayOfWeek,
      if (recurrence.config!.dayOfMonth != null)
        'day_of_month': recurrence.config!.dayOfMonth,
      if (recurrence.config!.month != null) 'month': recurrence.config!.month,
      if (recurrence.config!.dayOfYear != null)
        'day_of_year': recurrence.config!.dayOfYear,
      if (recurrence.config!.endDate != null)
        'end_date': wallClockToUtcIso(recurrence.config!.endDate!),
    };

    final response = await _client.post(
      Uri.parse('$baseUrl/api/transactions/preview-recurrence?count=$count'),
      headers: await _getHeaders(),
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List<dynamic> occurrences = data['occurrences'];
      return occurrences.map((date) => parseWallClock(date)).toList();
    } else {
      throw apiError(response, 'Failed to preview recurrence');
    }
  }

  static Future<List<Transaction>> getTransactions({
    int limit = 50,
    int skip = 0,
    TransactionType? type,
    DateTime? startDate,
    DateTime? endDate,
    Currency? currency, // NEW
  }) async {
    String url = '$baseUrl/api/transactions?limit=$limit&skip=$skip';

    if (type != null) {
      url += '&transaction_type=${type.name}';
    }
    if (currency != null) {
      // NEW
      url += '&currency=${currency.name}';
    }
    // Transaction dates are wall-clock values stored tagged as UTC, so the
    // filter bounds must be the same wall-clock fields tagged as UTC (NOT
    // local midnight converted to UTC, which shifts the day for UTC+ users).
    if (startDate != null) {
      final iso = startDate.isUtc
          ? startDate.toIso8601String()
          : wallClockToUtcIso(startDate);
      url += '&start_date=${Uri.encodeComponent(iso)}';
    }
    if (endDate != null) {
      final iso =
          endDate.isUtc ? endDate.toIso8601String() : wallClockToUtcIso(endDate);
      url += '&end_date=${Uri.encodeComponent(iso)}';
    }
    final response = await _client.get(
      Uri.parse(url),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Transaction.fromJson(json)).toList();
    } else {
      throw apiError(response, 'Failed to get transactions');
    }
  }

  static Future<Transaction> getTransaction(String transactionId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/transactions/$transactionId'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return Transaction.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to get transaction');
    }
  }

  static Future<Transaction> updateTransaction({
    required String transactionId,
    TransactionType? type,
    String? mainCategory,
    String? subCategory,
    DateTime? date,
    String? description,
    double? amount,
    Currency? currency, // NEW
    TransactionRecurrence? recurrence,
  }) async {
    final Map<String, dynamic> updateData = {};
    if (type != null) updateData['type'] = type.name;
    if (mainCategory != null) updateData['main_category'] = mainCategory;
    if (subCategory != null) updateData['sub_category'] = subCategory;
    if (date != null) updateData['date'] = date.toIso8601String();
    if (description != null) updateData['description'] = description;
    if (amount != null) updateData['amount'] = amount;
    if (currency != null) updateData['currency'] = currency.name; // NEW
    if (recurrence != null) {
      updateData['recurrence'] = recurrence.toJson();
    }
    if (updateData.isEmpty) {
      throw Exception('No fields provided for update');
    }
    final response = await _client.put(
      Uri.parse('$baseUrl/api/transactions/$transactionId'),
      headers: await _getHeaders(),
      body: jsonEncode(updateData),
    );

    if (response.statusCode == 200) {
      return Transaction.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to update transaction');
    }
  }

  static Future<void> deleteTransaction(String transactionId) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/transactions/$transactionId'),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      throw apiError(response, 'Failed to delete transaction');
    }
  }

  static Future<List<Category>> getCategories(TransactionType type) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/categories/${type.name}'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Category.fromJson(json)).toList();
    } else {
      throw apiError(response, 'Failed to get categories');
    }
  }

  static Future<Balance> getBalance({Currency? currency}) async {
    String url = '$baseUrl/api/dashboard/balance';
    if (currency != null) {
      url += '?currency=${currency.name}';
    }
    final response = await _client.get(
      Uri.parse(url),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      // If currency specified, return single balance
      if (currency != null) {
        return Balance.fromJson(data);
      }

      // Otherwise, return balance for user's default currency
      // (The frontend will need to handle multi-currency case separately)
      final balances = data['balances'] as Map<String, dynamic>;
      final firstCurrency = balances.keys.first;
      return Balance.fromJson(balances[firstCurrency]);
    } else {
      throw apiError(response, 'Failed to get balance');
    }
  }

  static Future<MultiCurrencyBalance> getAllBalances() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/dashboard/balance'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return MultiCurrencyBalance.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to get balances');
    }
  }

  static Stream<String> streamChatMessage({
    required String message,
    List<ChatMessage>? chatHistory,
    ResponseStyle? responseStyle,
    AIProvider? aiProvider, // NEW parameter
  }) async* {
    final chatRequest = ChatRequest(
      message: message,
      chatHistory: chatHistory,
      responseStyle: responseStyle ?? ResponseStyle.normal,
      aiProvider: aiProvider ?? AIProvider.openai,
    );

    final request = http.Request('POST', Uri.parse('$baseUrl/api/chat/stream'));
    request.headers.addAll(await _getHeaders());
    request.body = jsonEncode(chatRequest.toJson());

    // A dedicated client per stream so that [cancelChatStream] can abort the
    // underlying connection (cancelling the Dart subscription alone does not).
    final client = http.Client();
    _activeChatClient?.close();
    _activeChatClient = client;

    try {
      final http.StreamedResponse streamedResponse;
      try {
        streamedResponse = await client
            .send(request)
            .timeout(_ApiClient.longTimeout);
      } on TimeoutException {
        throw ApiException(timeoutMessage);
      } on SocketException {
        throw ApiException(networkErrorMessage);
      }

      if (streamedResponse.statusCode != 200) {
        final http.Response response;
        try {
          response = http.Response.bytes(
            await readBodyWithTimeout(streamedResponse.stream, _ApiClient.longTimeout),
            streamedResponse.statusCode,
            headers: streamedResponse.headers,
            request: streamedResponse.request,
          );
        } on TimeoutException {
          throw ApiException(timeoutMessage);
        }
        await checkSessionInvalidated(request, response.statusCode, response.body);
        throw apiError(response, 'Failed to start streaming chat');
      }

      // No total timeout on the stream body (answers can stream for a long
      // time), but a stream that goes silent for too long is abandoned.
      final chunks = streamedResponse.stream.timeout(
        _chatStreamIdleTimeout,
        onTimeout: (sink) {
          sink.addError(ApiException(timeoutMessage));
          sink.close();
        },
      );

      // SSE frames (`data: {json}\n\n`) can be split across network reads:
      // keep the unfinished tail in a buffer and only parse complete lines.
      var buffer = '';
      await for (final text in chunks.transform(utf8.decoder)) {
        buffer += text;
        var newlineIndex = buffer.indexOf('\n');
        while (newlineIndex != -1) {
          final line = buffer.substring(0, newlineIndex).trimRight();
          buffer = buffer.substring(newlineIndex + 1);
          newlineIndex = buffer.indexOf('\n');

          if (!line.startsWith('data:')) continue;
          final payload = line.substring(5).trimLeft();
          if (payload.isEmpty) continue;

          final dynamic data;
          try {
            data = jsonDecode(payload);
          } on FormatException {
            continue; // malformed frame — skip it
          }
          if (data is! Map) continue;

          if (data['error'] != null) {
            throw ApiException(data['error'].toString());
          }

          final chunk = data['chunk'];
          if (chunk is String && chunk.isNotEmpty) {
            yield chunk;
          }

          if (data['done'] == true) return;
        }
      }
    } finally {
      client.close();
      if (identical(_activeChatClient, client)) _activeChatClient = null;
    }
  }

  static http.Client? _activeChatClient;

  /// Longest silence tolerated between two chunks of the streaming chat.
  static const Duration _chatStreamIdleTimeout = _ApiClient.longTimeout;

  /// Aborts the in-flight chat stream (if any) by closing its HTTP client.
  static void cancelChatStream() {
    _activeChatClient?.close();
    _activeChatClient = null;
  }

  // Goals CRUD methods
  static Future<Goal> createGoal({
    required String name,
    required double targetAmount,
    DateTime? targetDate,
    required GoalType goalType,
    double initialContribution = 0.0,
    required Currency currency, // NEW
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/goals'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'name': name,
        'target_amount': targetAmount,
        'target_date': targetDate?.toIso8601String(),
        'goal_type': goalType.name,
        'initial_contribution': initialContribution,
        'currency': currency.name, // NEW
      }),
    );

    if (response.statusCode == 200) {
      return Goal.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to create goal');
    }
  }

  static Future<List<Goal>> getGoals({
    GoalStatus? statusFilter,
    Currency? currency, // NEW
  }) async {
    String url = '$baseUrl/api/goals';

    List<String> queryParams = [];
    if (statusFilter != null) {
      queryParams.add('status_filter=${statusFilter.name}');
    }
    if (currency != null) {
      // NEW
      queryParams.add('currency=${currency.name}');
    }

    if (queryParams.isNotEmpty) {
      url += '?${queryParams.join('&')}';
    }

    final response = await _client.get(
      Uri.parse(url),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Goal.fromJson(json)).toList();
    } else {
      throw apiError(response, 'Failed to get goals');
    }
  }

  static Future<GoalsSummary> getGoalsSummary({Currency? currency}) async {
    // NEW - add currency parameter
    String url = '$baseUrl/api/goals/summary';
    if (currency != null) {
      // NEW
      url += '?currency=${currency.name}';
    }

    final response = await _client.get(
      Uri.parse(url),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return GoalsSummary.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to get goals summary');
    }
  }

  static Future<MultiCurrencyGoalsSummary>
  getMultiCurrencyGoalsSummary() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/goals/summary/all-currencies'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return MultiCurrencyGoalsSummary.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to get multi-currency goals summary');
    }
  }

  static Future<Goal> getGoal(String goalId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/goals/$goalId'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return Goal.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to get goal');
    }
  }

  static Future<Goal> updateGoal({
    required String goalId,
    String? name,
    double? targetAmount,
    DateTime? targetDate,
    GoalType? goalType,
  }) async {
    final Map<String, dynamic> updateData = {};

    if (name != null) updateData['name'] = name;
    if (targetAmount != null) updateData['target_amount'] = targetAmount;
    if (targetDate != null)
      updateData['target_date'] = targetDate.toIso8601String();
    if (goalType != null) updateData['goal_type'] = goalType.name;

    if (updateData.isEmpty) {
      throw Exception('No fields provided for update');
    }

    final response = await _client.put(
      Uri.parse('$baseUrl/api/goals/$goalId'),
      headers: await _getHeaders(),
      body: jsonEncode(updateData),
    );

    if (response.statusCode == 200) {
      return Goal.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to update goal');
    }
  }

  static Future<Goal> contributeToGoal({
    required String goalId,
    required double amount,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/goals/$goalId/contribute'),
      headers: await _getHeaders(),
      body: jsonEncode({'amount': amount}),
    );

    if (response.statusCode == 200) {
      return Goal.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to contribute to goal');
    }
  }

  static Future<Map<String, dynamic>> deleteGoal(String goalId) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/goals/$goalId'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw apiError(response, 'Failed to delete goal');
    }
  }

  static Future<ChatResponse> sendChatMessage({
    required String message,
    List<ChatMessage>? chatHistory,
  }) async {
    String fullResponse = '';
    DateTime? timestamp;

    await for (final chunk in streamChatMessage(
      message: message,
      chatHistory: chatHistory,
    )) {
      fullResponse += chunk;
      timestamp ??= DateTime.now();
    }

    return ChatResponse(
      response: fullResponse,
      timestamp: timestamp ?? DateTime.now(),
    );
  }

  static Future<List<ChatMessage>> getChatHistory({int limit = 20}) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/chat/history?limit=$limit'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => ChatMessage.fromJson(json)).toList();
    } else {
      throw apiError(response, 'Failed to get chat history');
    }
  }

  static Future<void> clearChatHistory() async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/chat/history'),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      throw apiError(response, 'Failed to clear chat history');
    }
  }

  static Future<Insight> getInsights({
    String language = 'en',
    AIProvider? aiProvider,
    String insightType = 'weekly', // NEW parameter
  }) async {
    String url =
        '$baseUrl/api/insights?language=$language&insight_type=$insightType';

    if (aiProvider != null) {
      url += '&ai_provider=${aiProvider.name}';
    }

    final response = await _client.get(
      Uri.parse(url),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return Insight.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to get insights');
    }
  }

  static Future<Insight> regenerateInsights({
    String language = 'en',
    AIProvider? aiProvider,
    String insightType = 'weekly', // NEW parameter
  }) async {
    String url =
        '$baseUrl/api/insights/regenerate?language=$language&insight_type=$insightType';

    if (aiProvider != null) {
      url += '&ai_provider=${aiProvider.name}';
    }

    final response = await _client.post(
      Uri.parse(url),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return Insight.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to regenerate insights');
    }
  }

  static Future<void> deleteInsights({AIProvider? aiProvider}) async {
    String url = '$baseUrl/api/insights';

    if (aiProvider != null) {
      url += '?ai_provider=${aiProvider.name}';
    }

    final response = await _client.delete(
      Uri.parse(url),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      throw apiError(response, 'Failed to delete insights');
    }
  }

  // NEW: Method to translate existing insights
  static Future<void> translateInsightsToMyanmar({
    AIProvider? aiProvider,
    String insightType = 'weekly',
  }) async {
    String url =
        '$baseUrl/api/insights/translate-myanmar?insight_type=$insightType';

    if (aiProvider != null) {
      url += '&ai_provider=${aiProvider.name}';
    }

    final response = await _client.post(
      Uri.parse(url),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      throw apiError(response, 'Failed to translate insights');
    }
  }

  static Future<void> refreshAiData({AIProvider? aiProvider}) async {
    String url = '$baseUrl/api/chat/refresh-data';

    if (aiProvider != null) {
      url += '?ai_provider=${aiProvider.name}';
    }

    final response = await _client.post(
      Uri.parse(url),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      throw apiError(response, 'Failed to refresh AI data');
    }
  }

  static Future<FinancialReport> generateReport({
    required ReportPeriod period,
    DateTime? startDate,
    DateTime? endDate,
    Currency? currency, // NEW parameter
  }) async {
    final Map<String, dynamic> requestBody = {
      'period': period.name,
      // Minutes east of UTC, so the server computes week/month/year
      // boundaries in the user's local time.
      'timezone_offset': DateTime.now().timeZoneOffset.inMinutes,
    };

    if (currency != null) {
      // NEW
      requestBody['currency'] = currency.name;
    }

    if (period == ReportPeriod.custom) {
      if (startDate == null || endDate == null) {
        throw Exception(
          'Start date and end date are required for custom period',
        );
      }
      final utcStart = DateTime.utc(
        startDate.year,
        startDate.month,
        startDate.day,
        0,
        0,
        0,
      );
      final utcEnd = DateTime.utc(
        endDate.year,
        endDate.month,
        endDate.day,
        23,
        59,
        59,
      );

      requestBody['start_date'] = utcStart.toIso8601String();
      requestBody['end_date'] = utcEnd.toIso8601String();
    }

    final response = await _client.post(
      Uri.parse('$baseUrl/api/reports/generate'),
      headers: await _getHeaders(),
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      return FinancialReport.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to generate report');
    }
  }

  static Future<String> downloadReportPdf({
    required ReportPeriod period,
    DateTime? startDate,
    DateTime? endDate,
    Currency? currency, // NEW parameter
  }) async {
    final now = DateTime.now();
    final timezoneOffset = now.timeZoneOffset.inMinutes;

    final Map<String, dynamic> requestBody = {
      'period': period.name,
      'timezone_offset': timezoneOffset,
    };

    if (currency != null) {
      // NEW
      requestBody['currency'] = currency.name;
    }

    if (period == ReportPeriod.custom) {
      if (startDate == null || endDate == null) {
        throw Exception(
          'Start date and end date are required for custom period',
        );
      }
      final utcStart = DateTime.utc(
        startDate.year,
        startDate.month,
        startDate.day,
        0,
        0,
        0,
      );
      final utcEnd = DateTime.utc(
        endDate.year,
        endDate.month,
        endDate.day,
        23,
        59,
        59,
      );

      requestBody['start_date'] = utcStart.toIso8601String();
      requestBody['end_date'] = utcEnd.toIso8601String();
    }

    final response = await _client.post(
      Uri.parse('$baseUrl/api/reports/download'),
      headers: await _getHeaders(),
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      final directory = await getApplicationDocumentsDirectory();

      String filename = 'financial_report.pdf';
      final contentDisposition = response.headers['content-disposition'];
      if (contentDisposition != null) {
        final filenameMatch = RegExp(
          r'filename="?([^"]+)"?',
        ).firstMatch(contentDisposition);
        if (filenameMatch != null) {
          filename = filenameMatch.group(1)!;
        }
      }

      final file = File('${directory.path}/$filename');
      await file.writeAsBytes(response.bodyBytes);

      return file.path;
    } else {
      throw apiError(response, 'Failed to download report');
    }
  }

  static Future<MultiCurrencyFinancialReport> generateMultiCurrencyReport({
    required ReportPeriod period,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final Map<String, dynamic> requestBody = {
      'period': period.name,
      'timezone_offset': DateTime.now().timeZoneOffset.inMinutes,
    };

    if (period == ReportPeriod.custom) {
      if (startDate == null || endDate == null) {
        throw Exception(
          'Start date and end date are required for custom period',
        );
      }
      final utcStart = DateTime.utc(
        startDate.year,
        startDate.month,
        startDate.day,
        0,
        0,
        0,
      );
      final utcEnd = DateTime.utc(
        endDate.year,
        endDate.month,
        endDate.day,
        23,
        59,
        59,
      );

      requestBody['start_date'] = utcStart.toIso8601String();
      requestBody['end_date'] = utcEnd.toIso8601String();
    }

    final response = await _client.post(
      Uri.parse('$baseUrl/api/reports/generate-multi-currency'),
      headers: await _getHeaders(),
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      return MultiCurrencyFinancialReport.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to generate multi-currency report');
    }
  }

  /// [language] ('en' | 'my') is sent only when the user explicitly chose
  /// it; null lets the backend auto-detect the spoken language.
  static Future<String> transcribeAudio(
    File audioFile, {
    String? language,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/transactions/transcribe-audio'),
      );

      final headers = await _getHeaders();
      request.headers.addAll(headers);

      request.files.add(
        await http.MultipartFile.fromPath(
          'audio',
          audioFile.path,
          contentType: MediaType('audio', 'wav'),
        ),
      );

      // Only hint the speech-to-text model when the user explicitly picked
      // the spoken language; otherwise the backend auto-detects it (users
      // often speak Burmese with an English UI, or vice versa).
      if (language == 'en' || language == 'my') {
        request.fields['language'] = language!;
      }

      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['transcription'];
      } else {
        throw apiError(response, 'Failed to transcribe audio');
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Audio transcription failed: $e');
    }
  }

  static Future<ExtractedTransactionData> extractTransactionFromText(
    String text,
  ) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/transactions/extract-from-text'),
        headers: await _getHeaders(),
        body: jsonEncode({'text': text}),
      );

      if (response.statusCode == 200) {
        return ExtractedTransactionData.fromJson(jsonDecode(response.body));
      } else {
        throw apiError(response, 'Failed to extract transaction');
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Transaction extraction failed: $e');
    }
  }

  static Future<ExtractedTransactionData> extractTransactionFromImage(
    File imageFile,
  ) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/transactions/extract-from-image'),
      );

      final headers = await _getHeaders();
      request.headers.addAll(headers);

      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          imageFile.path,
          contentType: MediaType('image', 'jpeg'),
        ),
      );

      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return ExtractedTransactionData.fromJson(jsonDecode(response.body));
      } else {
        throw apiError(response, 'Failed to extract from image');
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Image extraction failed: $e');
    }
  }

  static Future<MultipleExtractedTransactions>
  extractMultipleTransactionsFromText(String text) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/transactions/extract-multiple-from-text'),
        headers: await _getHeaders(),
        body: jsonEncode({'text': text}),
      );

      if (response.statusCode == 200) {
        return MultipleExtractedTransactions.fromJson(
          jsonDecode(response.body),
        );
      } else {
        throw apiError(response, 'Failed to extract transactions');
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Transaction extraction failed: $e');
    }
  }

  static Future<List<Transaction>> batchCreateTransactions({
    required List<ExtractedTransactionData> transactions,
  }) async {
    try {
      final List<Map<String, dynamic>> transactionsList = transactions
          .map((tx) => tx.toJson())
          .toList();

      final response = await _client.post(
        Uri.parse('$baseUrl/api/transactions/batch-create'),
        headers: await _getHeaders(),
        body: jsonEncode(transactionsList),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => Transaction.fromJson(json)).toList();
      } else {
        throw apiError(response, 'Failed to create transactions');
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Batch transaction creation failed: $e');
    }
  }

  static Future<AIBudgetSuggestion> getAIBudgetSuggestions({
    required BudgetPeriod period,
    required DateTime startDate,
    DateTime? endDate,
    List<String>? includeCategories,
    int analysisMonths = 3,
    String? userContext,
    required Currency currency, // NEW - make it required
  }) async {
    final Map<String, dynamic> requestBody = {
      'period': period.name,
      'start_date': wallClockToUtcIso(startDate),
      'analysis_months': analysisMonths,
      'currency': currency.name, // NEW
    };

    if (endDate != null) {
      requestBody['end_date'] = wallClockToUtcIso(endDate);
    }

    if (includeCategories != null && includeCategories.isNotEmpty) {
      requestBody['include_categories'] = includeCategories;
    }

    if (userContext != null && userContext.isNotEmpty) {
      requestBody['user_context'] = userContext;
    }

    final response = await _client.post(
      Uri.parse('$baseUrl/api/budgets/ai-suggest'),
      headers: await _getHeaders(),
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      return AIBudgetSuggestion.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to get AI budget suggestions');
    }
  }

  static Future<Budget> createBudget({
    required String name,
    required BudgetPeriod period,
    required DateTime startDate,
    DateTime? endDate,
    required List<CategoryBudget> categoryBudgets,
    required double totalBudget,
    String? description,
    bool autoCreateEnabled = false,
    bool autoCreateWithAi = false,
    required Currency currency, // NEW - make it required
  }) async {
    final Map<String, dynamic> requestBody = {
      'name': name,
      'period': period.name,
      'start_date': wallClockToUtcIso(startDate),
      'category_budgets': categoryBudgets.map((cat) => cat.toJson()).toList(),
      'total_budget': totalBudget,
      'auto_create_enabled': autoCreateEnabled,
      'auto_create_with_ai': autoCreateWithAi,
      'currency': currency.name, // NEW
    };

    if (endDate != null) {
      requestBody['end_date'] = wallClockToUtcIso(endDate);
    }

    if (description != null) {
      requestBody['description'] = description;
    }

    final response = await _client.post(
      Uri.parse('$baseUrl/api/budgets'),
      headers: await _getHeaders(),
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      return Budget.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to create budget');
    }
  }

  static Future<List<Budget>> getBudgets({
    bool activeOnly = false,
    BudgetPeriod? period,
    Currency? currency, // NEW - optional filter
  }) async {
    String url = '$baseUrl/api/budgets?active_only=$activeOnly';

    if (period != null) {
      url += '&period=${period.name}';
    }

    if (currency != null) {
      // NEW
      url += '&currency=${currency.name}';
    }

    final response = await _client.get(
      Uri.parse(url),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Budget.fromJson(json)).toList();
    } else {
      throw apiError(response, 'Failed to get budgets');
    }
  }

  static Future<BudgetSummary> getBudgetsSummary({
    Currency?
    currency, // NEW - optional, will use user's default if not provided
  }) async {
    String url = '$baseUrl/api/budgets/summary';

    if (currency != null) {
      url += '?currency=${currency.name}';
    }

    final response = await _client.get(
      Uri.parse(url),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return BudgetSummary.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to get budgets summary');
    }
  }

  static Future<MultiCurrencyBudgetSummary>
  getMultiCurrencyBudgetsSummary() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/budgets/summary/all-currencies'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return MultiCurrencyBudgetSummary.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to get multi-currency budgets summary');
    }
  }

  static Future<Budget> getBudget(String budgetId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/budgets/$budgetId'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return Budget.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to get budget');
    }
  }

  static Future<Budget> updateBudget({
    required String budgetId,
    String? name,
    List<CategoryBudget>? categoryBudgets,
    double? totalBudget,
    String? description,
    bool? autoCreateEnabled, // NEW
    bool? autoCreateWithAi, // NEW
  }) async {
    final Map<String, dynamic> updateData = {};

    if (name != null) updateData['name'] = name;
    if (description != null) updateData['description'] = description;
    if (totalBudget != null) updateData['total_budget'] = totalBudget;
    if (categoryBudgets != null) {
      updateData['category_budgets'] = categoryBudgets
          .map((cat) => cat.toJson())
          .toList();
    }
    if (autoCreateEnabled != null)
      updateData['auto_create_enabled'] = autoCreateEnabled; // NEW
    if (autoCreateWithAi != null)
      updateData['auto_create_with_ai'] = autoCreateWithAi; // NEW

    if (updateData.isEmpty) {
      throw Exception('No fields provided for update');
    }

    final response = await _client.put(
      Uri.parse('$baseUrl/api/budgets/$budgetId'),
      headers: await _getHeaders(),
      body: jsonEncode(updateData),
    );

    if (response.statusCode == 200) {
      return Budget.fromJson(jsonDecode(response.body));
    } else {
      throw apiError(response, 'Failed to update budget');
    }
  }

  static Future<void> deleteBudget(String budgetId) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/budgets/$budgetId'),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      throw apiError(response, 'Failed to delete budget');
    }
  }

  static Future<void> refreshBudget(String budgetId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/budgets/$budgetId/refresh'),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      throw apiError(response, 'Failed to refresh budget');
    }
  }

  static Future<List<AppNotification>> getNotifications({
    int limit = 50,
    bool unreadOnly = false,
  }) async {
    String url =
        '$baseUrl/api/notifications?limit=$limit&unread_only=$unreadOnly';

    final response = await _client.get(
      Uri.parse(url),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => AppNotification.fromJson(json)).toList();
    } else {
      throw apiError(response, 'Failed to get notifications');
    }
  }

  static Future<void> markNotificationRead(String notificationId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/notifications/$notificationId/mark-read'),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      throw apiError(response, 'Failed to mark notification as read');
    }
  }

  static Future<void> markAllNotificationsRead() async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/notifications/mark-all-read'),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      throw apiError(response, 'Failed to mark all notifications as read');
    }
  }

  static Future<void> deleteNotification(String notificationId) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/notifications/$notificationId'),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      throw apiError(response, 'Failed to delete notification');
    }
  }

  static Future<int> getUnreadNotificationCount() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/notifications/unread-count'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['unread_count'];
    } else {
      throw apiError(response, 'Failed to get unread count');
    }
  }

  // ==================== FEEDBACK ====================

  static Future<void> submitFeedback(FeedbackCreate feedback) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/feedback'),
      headers: await _getHeaders(),
      body: jsonEncode(feedback.toJson()),
    );

    if (response.statusCode != 200) {
      throw apiError(response, 'Failed to submit feedback');
    }
  }

  // ==================== TRANSACTIONS ====================
  // (All your existing transaction, goal, budget, report, insight,
  //  chat methods go here unchanged — no modifications needed.)
}
