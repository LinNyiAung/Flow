import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../models/transaction.dart';

class ApiService {
  static const String baseUrl = 'https://flow-6l8z.onrender.com';
  
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
    required DateTime date, // Added date parameter
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
        'date': date.toIso8601String(), // Send date in ISO format
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
  }) async {
    String url = '$baseUrl/api/transactions?limit=$limit&skip=$skip';
    if (type != null) {
      url += '&transaction_type=${type.name}';
    }

    final response = await http.get(
      Uri.parse(url),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Transaction.fromJson(json)).toList();
    } else {
      throw Exception('Failed to get transactions');
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
    DateTime? date, // Added date parameter
    String? description,
    double? amount,
  }) async {
    final Map<String, dynamic> updateData = {};

    if (type != null) updateData['type'] = type.name;
    if (mainCategory != null) updateData['main_category'] = mainCategory;
    if (subCategory != null) updateData['sub_category'] = subCategory;
    if (date != null) updateData['date'] = date.toIso8601String(); // Send date in ISO format
    if (description != null) updateData['description'] = description;
    if (amount != null) updateData['amount'] = amount;

    if (updateData.isEmpty) {
        // No fields to update, return existing transaction or throw error
        // For simplicity, let's return the original transaction data or fetch it again if needed.
        // Or we can throw an error indicating nothing was updated.
        // For now, we'll just return the existing transaction if nothing changed.
        // A better approach might be to check if the data has changed.
        // If no updates are provided, we can just return the fetched transaction or throw a specific exception.
        // For this example, let's assume a call with no data means no update.
        // However, the API expects some data. Let's return an error if updateData is empty.
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
}