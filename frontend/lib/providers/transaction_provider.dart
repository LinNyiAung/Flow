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

  Future<bool> createTransaction({
    required TransactionType type,
    required String mainCategory,
    required String subCategory,
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
        description: description,
        amount: amount,
      );
      
      _transactions.insert(0, transaction);
      await fetchBalance();
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

  Future<bool> updateTransaction({
    required String transactionId,
    TransactionType? type,
    String? mainCategory,
    String? subCategory,
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
        description: description,
        amount: amount,
      );
      
      // Update transaction in the list
      final index = _transactions.indexWhere((t) => t.id == transactionId);
            if (index != -1) {
        _transactions[index] = updatedTransaction;
      }
      
      await fetchBalance();
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

  Future<bool> deleteTransaction(String transactionId) async {
    _setLoading(true);
    _setError(null);

    try {
      await ApiService.deleteTransaction(transactionId);
      
      // Remove transaction from the list
      _transactions.removeWhere((t) => t.id == transactionId);
      
      await fetchBalance();
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

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

  Future<Transaction?> getTransaction(String transactionId) async {
    try {
      return await ApiService.getTransaction(transactionId);
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      return null;
    }
  }

  Future<void> fetchBalance() async {
    try {
      _balance = await ApiService.getBalance();
      notifyListeners();
    } catch (e) {
      // Handle silently for now
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}