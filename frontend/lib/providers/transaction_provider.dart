import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';

class TransactionProvider with ChangeNotifier {
  List<Transaction> _transactions = [];
  Balance? _balance;
  bool _isLoading = false;
  String? _error;

  List<Transaction> get transactions => _transactions;
  Balance? get balance => _balance;
  bool get isLoading => _isLoading;
  String? get error => _error;

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  // Create a new transaction
  Future<bool> createTransaction({
    required TransactionType type,
    required String mainCategory,
    required String subCategory,
    required DateTime date, // Added date parameter
    String? description,
    required double amount,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final transaction = await ApiService.createTransaction(
        type: type,
        mainCategory: mainCategory,
        subCategory: subCategory,
        date: date, // Pass the selected date
        description: description,
        amount: amount,
      );

      _transactions.insert(0, transaction); // Add new transaction to the beginning of the list
      await fetchBalance(); // Refresh balance after creating a transaction
      _setLoading(false);
      return true; // Indicate success
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', '')); // Set error message
      _setLoading(false);
      return false; // Indicate failure
    }
  }

  // Update an existing transaction
  Future<bool> updateTransaction({
    required String transactionId,
    TransactionType? type,
    String? mainCategory,
    String? subCategory,
    DateTime? date, // Added date parameter
    String? description,
    double? amount,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final updatedTransaction = await ApiService.updateTransaction(
        transactionId: transactionId,
        type: type,
        mainCategory: mainCategory,
        subCategory: subCategory,
        date: date, // Pass the selected date
        description: description,
        amount: amount,
      );

      // Update the transaction in the local list
      final index = _transactions.indexWhere((t) => t.id == transactionId);
      if (index != -1) {
        _transactions[index] = updatedTransaction;
      }

      await fetchBalance(); // Refresh balance after updating
      _setLoading(false);
      return true; // Indicate success
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', '')); // Set error message
      _setLoading(false);
      return false; // Indicate failure
    }
  }

  // Delete a transaction
  Future<bool> deleteTransaction(String transactionId) async {
    _setLoading(true);
    _setError(null);

    try {
      await ApiService.deleteTransaction(transactionId);

      // Remove the transaction from the local list
      _transactions.removeWhere((t) => t.id == transactionId);

      await fetchBalance(); // Refresh balance after deleting
      _setLoading(false);
      return true; // Indicate success
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', '')); // Set error message
      _setLoading(false);
      return false; // Indicate failure
    }
  }

  // Fetch all transactions
  Future<void> fetchTransactions() async {
    _setLoading(true);
    _setError(null);

    try {
      _transactions = await ApiService.getTransactions();
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

  // Fetch the user's balance
  Future<void> fetchBalance() async {
    try {
      _balance = await ApiService.getBalance();
      // No need to set loading/error here if this is called during refresh or init
      // It's already handled by fetchTransactions if it's a full refresh
      notifyListeners(); // Notify listeners when balance is updated
    } catch (e) {
      // Handle error if necessary, e.g., log it or set an error message if balance is critical
      print("Error fetching balance: $e");
    }
  }

  // Clear any displayed error message
  void clearError() {
    _error = null;
    notifyListeners();
  }
}