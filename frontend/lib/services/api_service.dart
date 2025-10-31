import 'dart:convert';
import 'dart:io';
import 'package:frontend/models/chat.dart';
import 'package:frontend/models/goal.dart';
import 'package:frontend/models/insight.dart';
import 'package:frontend/models/report.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../models/transaction.dart';

class ApiService {
  static const String baseUrl = 'http://10.80.21.130:8000';
  
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

  static Future<Map<String, String>> _getHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Auth methods (keeping existing ones)
  static Future<AuthResponse> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      final authResponse = AuthResponse.fromJson(jsonDecode(response.body));
      await saveToken(authResponse.accessToken);
      return authResponse;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Registration failed');
    }
  }

  static Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      final authResponse = AuthResponse.fromJson(jsonDecode(response.body));
      await saveToken(authResponse.accessToken);
      return authResponse;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Login failed');
    }
  }

  static Future<User> getCurrentUser() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/auth/me'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to get user info');
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
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/transactions'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'type': type.name,
        'main_category': mainCategory,
        'sub_category': subCategory,
        'date': date.toIso8601String(),
        'description': description,
        'amount': amount,
      }),
    );

    if (response.statusCode == 200) {
      return Transaction.fromJson(jsonDecode(response.body));
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to create transaction');
    }
  }

  static Future<List<Transaction>> getTransactions({
    int limit = 50,
    int skip = 0,
    TransactionType? type,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    String url = '$baseUrl/api/transactions?limit=$limit&skip=$skip';

    // Add type filter if provided
    if (type != null) {
      url += '&transaction_type=${type.name}';
    }

    // Add date range filters if provided - FIXED: proper URL encoding
    if (startDate != null) {
      // Ensure UTC and format for backend
      final utcStart = startDate.toUtc();
      final formattedStart = Uri.encodeComponent(utcStart.toIso8601String());
      url += '&start_date=$formattedStart';
    }
    if (endDate != null) {
      // Ensure UTC and format for backend
      final utcEnd = endDate.toUtc();
      final formattedEnd = Uri.encodeComponent(utcEnd.toIso8601String());
      url += '&end_date=$formattedEnd';
    }

    print('DEBUG: Fetching transactions from: $url'); // Add debug log

    final response = await http.get(
      Uri.parse(url),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Transaction.fromJson(json)).toList();
    } else {
      print('ERROR: Failed to get transactions - Status: ${response.statusCode}');
      print('ERROR: Response body: ${response.body}');
      throw Exception('Failed to get transactions: ${response.body}');
    }
  }

  static Future<Transaction> getTransaction(String transactionId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/transactions/$transactionId'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return Transaction.fromJson(jsonDecode(response.body));
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to get transaction');
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
  }) async {
    final Map<String, dynamic> updateData = {};

    if (type != null) updateData['type'] = type.name;
    if (mainCategory != null) updateData['main_category'] = mainCategory;
    if (subCategory != null) updateData['sub_category'] = subCategory;
    if (date != null) updateData['date'] = date.toIso8601String();
    if (description != null) updateData['description'] = description;
    if (amount != null) updateData['amount'] = amount;

    if (updateData.isEmpty) {
      throw Exception('No fields provided for update');
    }

    final response = await http.put(
      Uri.parse('$baseUrl/api/transactions/$transactionId'),
      headers: await _getHeaders(),
      body: jsonEncode(updateData),
    );

    if (response.statusCode == 200) {
      return Transaction.fromJson(jsonDecode(response.body));
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to update transaction');
    }
  }

  static Future<void> deleteTransaction(String transactionId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/transactions/$transactionId'),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to delete transaction');
    }
  }

  static Future<List<Category>> getCategories(TransactionType type) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/categories/${type.name}'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Category.fromJson(json)).toList();
    } else {
      throw Exception('Failed to get categories');
    }
  }

  static Future<Balance> getBalance() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/dashboard/balance'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return Balance.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to get balance');
    }
  }


    static Stream<String> streamChatMessage({
    required String message,
    List<ChatMessage>? chatHistory,
  }) async* {
    try {
      final chatRequest = ChatRequest(
        message: message,
        chatHistory: chatHistory,
      );

      final request = http.Request(
        'POST',
        Uri.parse('$baseUrl/api/chat/stream'),
      );
      
      final headers = await _getHeaders();
      request.headers.addAll(headers);
      request.body = jsonEncode(chatRequest.toJson());

      final streamedResponse = await http.Client().send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception('Failed to start streaming chat');
      }

      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        final lines = chunk.split('\n');
        
        for (final line in lines) {
          if (line.startsWith('data: ')) {
            final jsonData = line.substring(6); // Remove 'data: ' prefix
            
            try {
              final data = jsonDecode(jsonData);
              
              // Check for error
              if (data['error'] != null) {
                throw Exception(data['error']);
              }
              
              // Check if streaming is done
              if (data['done'] == true) {
                return; // End the stream
              }
              
              // Yield the text chunk
              final chunk = data['chunk'] as String?;
              if (chunk != null && chunk.isNotEmpty) {
                yield chunk;
              }
              
            } catch (jsonError) {
              // Skip malformed JSON lines
              continue;
            }
          }
        }
      }
    } catch (e) {
      throw Exception('Streaming chat failed: ${e.toString()}');
    }
  }


    // Goals CRUD methods
    static Future<Goal> createGoal({
    required String name,
    required double targetAmount,
    DateTime? targetDate,
    required GoalType goalType,
    double initialContribution = 0.0,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/goals'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'name': name,
        'target_amount': targetAmount,
        'target_date': targetDate?.toIso8601String(),
        'goal_type': goalType.name,
        'initial_contribution': initialContribution,
      }),
    );

    if (response.statusCode == 200) {
      return Goal.fromJson(jsonDecode(response.body));
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to create goal');
    }
  }

  static Future<List<Goal>> getGoals({GoalStatus? statusFilter}) async {
    String url = '$baseUrl/api/goals';
    
    if (statusFilter != null) {
      url += '?status_filter=${statusFilter.name}';
    }

    final response = await http.get(
      Uri.parse(url),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Goal.fromJson(json)).toList();
    } else {
      throw Exception('Failed to get goals');
    }
  }

  static Future<GoalsSummary> getGoalsSummary() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/goals/summary'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return GoalsSummary.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to get goals summary');
    }
  }

  static Future<Goal> getGoal(String goalId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/goals/$goalId'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return Goal.fromJson(jsonDecode(response.body));
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to get goal');
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
    if (targetDate != null) updateData['target_date'] = targetDate.toIso8601String();
    if (goalType != null) updateData['goal_type'] = goalType.name;

    if (updateData.isEmpty) {
      throw Exception('No fields provided for update');
    }

    final response = await http.put(
      Uri.parse('$baseUrl/api/goals/$goalId'),
      headers: await _getHeaders(),
      body: jsonEncode(updateData),
    );

    if (response.statusCode == 200) {
      return Goal.fromJson(jsonDecode(response.body));
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to update goal');
    }
  }

  static Future<Goal> contributeToGoal({
    required String goalId,
    required double amount,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/goals/$goalId/contribute'),
      headers: await _getHeaders(),
      body: jsonEncode({'amount': amount}),
    );

    if (response.statusCode == 200) {
      return Goal.fromJson(jsonDecode(response.body));
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to contribute to goal');
    }
  }

  static Future<Map<String, dynamic>> deleteGoal(String goalId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/goals/$goalId'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to delete goal');
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
    final response = await http.get(
      Uri.parse('$baseUrl/api/chat/history?limit=$limit'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => ChatMessage.fromJson(json)).toList();
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to get chat history');
    }
  }

  static Future<void> clearChatHistory() async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/chat/history'),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to clear chat history');
    }
  }


    static Future<Insight> getInsights() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/insights'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return Insight.fromJson(jsonDecode(response.body));
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to get insights');
    }
  }

  static Future<void> deleteInsights() async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/insights'),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to delete insights');
    }
  }

  static Future<Insight> regenerateInsights() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/insights/regenerate'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return Insight.fromJson(jsonDecode(response.body));
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to regenerate insights');
    }
  }

  static Future<void> refreshAiData() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/chat/refresh-data'),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to refresh AI data');
    }
  }


static Future<FinancialReport> generateReport({
  required ReportPeriod period,
  DateTime? startDate,
  DateTime? endDate,
}) async {
  final Map<String, dynamic> requestBody = {
    'period': period.name,
  };

  if (period == ReportPeriod.custom) {
    if (startDate == null || endDate == null) {
      throw Exception('Start date and end date are required for custom period');
    }
    // Create UTC dates at midnight without timezone conversion
    final utcStart = DateTime.utc(startDate.year, startDate.month, startDate.day, 0, 0, 0);
    final utcEnd = DateTime.utc(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    
    requestBody['start_date'] = utcStart.toIso8601String();
    requestBody['end_date'] = utcEnd.toIso8601String();
  }

  final response = await http.post(
    Uri.parse('$baseUrl/api/reports/generate'),
    headers: await _getHeaders(),
    body: jsonEncode(requestBody),
  );

  if (response.statusCode == 200) {
    return FinancialReport.fromJson(jsonDecode(response.body));
  } else {
    final error = jsonDecode(response.body);
    throw Exception(error['detail'] ?? 'Failed to generate report');
  }
}

static Future<String> downloadReportPdf({
  required ReportPeriod period,
  DateTime? startDate,
  DateTime? endDate,
}) async {
  // Get user's timezone offset in minutes
  final now = DateTime.now();
  final timezoneOffset = now.timeZoneOffset.inMinutes;
  
  final Map<String, dynamic> requestBody = {
    'period': period.name,
    'timezone_offset': timezoneOffset,  // Add this line
  };

  if (period == ReportPeriod.custom) {
    if (startDate == null || endDate == null) {
      throw Exception('Start date and end date are required for custom period');
    }
    final utcStart = DateTime.utc(startDate.year, startDate.month, startDate.day, 0, 0, 0);
    final utcEnd = DateTime.utc(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    
    requestBody['start_date'] = utcStart.toIso8601String();
    requestBody['end_date'] = utcEnd.toIso8601String();
  }

  final response = await http.post(
    Uri.parse('$baseUrl/api/reports/download'),
    headers: await _getHeaders(),
    body: jsonEncode(requestBody),
  );

  if (response.statusCode == 200) {
    final directory = await getApplicationDocumentsDirectory();
    
    String filename = 'financial_report.pdf';
    final contentDisposition = response.headers['content-disposition'];
    if (contentDisposition != null) {
      final filenameMatch = RegExp(r'filename="?([^"]+)"?').firstMatch(contentDisposition);
      if (filenameMatch != null) {
        filename = filenameMatch.group(1)!;
      }
    }
    
    final file = File('${directory.path}/$filename');
    await file.writeAsBytes(response.bodyBytes);
    
    return file.path;
  } else {
    final error = jsonDecode(response.body);
    throw Exception(error['detail'] ?? 'Failed to download report');
  }
}


}