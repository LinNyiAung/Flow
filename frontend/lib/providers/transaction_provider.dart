import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';
import '../providers/chat_provider.dart'; // Add this import for AI integration

class TransactionProvider with ChangeNotifier {
  List<Transaction> _transactions = [];
  Balance? _balance;
  bool _isLoading = false;
  String? _error;

  List<Transaction> get transactions => _transactions;
  Balance? get balance => _balance;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Helper to update loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  // Helper to update error state
  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  // Helper method to refresh AI data after transaction operations
  void _refreshAiData(BuildContext? context) {
    if (context != null) {
      try {
        Provider.of<ChatProvider>(context, listen: false).refreshAiData();
      } catch (e) {
        print('Error refreshing AI data: $e');
      }
    }
  }


  // ADD THIS NEW METHOD to transaction_provider.dart
Future<void> loadMoreTransactions({
  TransactionType? type,
  DateTime? startDate,
  DateTime? endDate,
  required int limit,
  required int currentCount,
}) async {
  // Don't set loading state to avoid full rebuild
  try {
    final newTransactions = await ApiService.getTransactions(
      type: type,
      startDate: startDate,
      endDate: endDate,
      limit: limit,
      skip: 0,
    );
    
    // Only update if we got more transactions than we already have
    if (newTransactions.length > currentCount) {
      _transactions = newTransactions;
      notifyListeners();
    }
  } catch (e) {
    _setError(e.toString().replaceAll('Exception: ', ''));
  }
}

  // Create a new transaction - UPDATED with context parameter
  Future<bool> createTransaction({
    required TransactionType type,
    required String mainCategory,
    required String subCategory,
    required DateTime date,
    String? description,
    required double amount,
    BuildContext? context, // Add context parameter for AI integration
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final transaction = await ApiService.createTransaction(
        type: type,
        mainCategory: mainCategory,
        subCategory: subCategory,
        date: date,
        description: description,
        amount: amount,
      );

      _transactions.insert(0, transaction);
      await fetchBalance();
      
      // Refresh AI data after creating transaction
      _refreshAiData(context);
      
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

  // Update an existing transaction - UPDATED with context parameter
  Future<bool> updateTransaction({
    required String transactionId,
    TransactionType? type,
    String? mainCategory,
    String? subCategory,
    DateTime? date,
    String? description,
    double? amount,
    BuildContext? context, // Add context parameter for AI integration
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final updatedTransaction = await ApiService.updateTransaction(
        transactionId: transactionId,
        type: type,
        mainCategory: mainCategory,
        subCategory: subCategory,
        date: date,
        description: description,
        amount: amount,
      );

      final index = _transactions.indexWhere((t) => t.id == transactionId);
      if (index != -1) {
        _transactions[index] = updatedTransaction;
      }

      await fetchBalance();
      
      // Refresh AI data after updating transaction
      _refreshAiData(context);
      
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

  // Delete a transaction - UPDATED with context parameter
  Future<bool> deleteTransaction(String transactionId, {BuildContext? context}) async {
    _setLoading(true);
    _setError(null);

    try {
      await ApiService.deleteTransaction(transactionId);
      _transactions.removeWhere((t) => t.id == transactionId);
      await fetchBalance();
      
      // Refresh AI data after deleting transaction
      _refreshAiData(context);
      
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

  // Fetch all transactions for the user, optionally filtered by type and date range
  Future<void> fetchTransactions({
    TransactionType? type,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
    int? skip,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final int nonNullableLimit = limit ?? 50;
      final int nonNullableSkip = skip ?? 0;

      _transactions = await ApiService.getTransactions(
        type: type,
        startDate: startDate,
        endDate: endDate,
        limit: nonNullableLimit,
        skip: nonNullableSkip,
      );
      _setLoading(false);
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
    }
  }

  // Fetch a single transaction by ID
  Future<Transaction?> getTransaction(String transactionId) async {
    try {
      return await ApiService.getTransaction(transactionId);
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      return null;
    }
  }

  // Fetch the user's financial balance and totals
  Future<void> fetchBalance() async {
    try {
      _balance = await ApiService.getBalance();
      notifyListeners();
    } catch (e) {
      print("Error fetching balance: $e");
    }
  }

  // Clear any displayed error message
  void clearError() {
    _error = null;
    notifyListeners();
  }
}