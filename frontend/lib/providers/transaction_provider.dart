import 'package:flutter/material.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/models/recurring_transaction.dart';
import 'package:frontend/models/user.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';
import '../providers/chat_provider.dart'; // Add this import for AI integration

class TransactionProvider with ChangeNotifier {
  List<Transaction> _transactions = [];
  // Every outflow from the last 7 days, for Home's Spending pace card (the
  // recent list above is capped, so it can miss days in a busy week).
  List<Transaction> _weekOutflows = [];
  int _weekRequestId = 0;
  Balance? _balance;
  bool _isLoading = false;
  String? _error;

  /// Bumped on [reset]; responses for an older session are discarded.
  int _generation = 0;
  // Latest balance request; an older response (e.g. for the previous default
  // currency) must not overwrite a newer one.
  int _balanceRequestId = 0;

  // Error of the last create/update/delete only. [error] is shared with
  // background fetches (e.g. Home's refresh), so a form screen reads this one
  // to report why *its* save failed.
  String? _writeError;

  List<Transaction> get transactions => _transactions;
  List<Transaction> get weekOutflows => _weekOutflows;
  Balance? get balance => _balance;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get writeError => _writeError;

  /// Clears all per-user state (called on logout / user switch).
  void reset() {
    _generation++;
    _transactions = [];
    _weekOutflows = [];
    _balance = null;
    _isLoading = false;
    _error = null;
    _writeError = null;
    notifyListeners();
  }

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

  // Error state for create/update/delete: sets both the shared [error] (kept
  // for existing listeners) and [writeError].
  void _setWriteError(String? error) {
    _writeError = error;
    _setError(error);
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


  // Note: filtered / paginated lists (Transactions screen, analytics) are
  // kept local to their screens — this list is Home's unfiltered recent set.

  // Create a new transaction - UPDATED with context parameter
  Future<bool> createTransaction({
  required TransactionType type,
  required String mainCategory,
  required String subCategory,
  required DateTime date,
  String? description,
  required double amount,
  required Currency currency,  // NEW
  BuildContext? context,
  TransactionRecurrence? recurrence,
  List<String>? forWhom,
  BookMode? bookOverride,
}) async {
  _setLoading(true);
  _setWriteError(null);
  // An entry added to the other book (New entry's book chip) never joins
  // this list, which shows the app's current book.
  final otherBook = bookOverride != null && bookOverride != ApiService.bookMode;

  try {
    final transaction = await ApiService.createTransaction(
      type: type,
      mainCategory: mainCategory,
      subCategory: subCategory,
      date: date,
      description: description,
      amount: amount,
      currency: currency,  // NEW
      recurrence: recurrence,
      forWhom: forWhom,
      bookOverride: otherBook ? bookOverride : null,
    );

    if (!otherBook) _transactions.insert(0, transaction);
    await Future.wait([fetchBalance(), fetchWeekSpending()]);
    
    _refreshAiData(context);
    
    _setLoading(false);
    return true;
  } catch (e) {
    _setWriteError(e.toString().replaceAll('Exception: ', ''));
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
  Currency? currency,  // NEW
  BuildContext? context,
  TransactionRecurrence? recurrence,
  List<String>? forWhom,
}) async {
  _setLoading(true);
  _setWriteError(null);

  try {
    final updatedTransaction = await ApiService.updateTransaction(
      transactionId: transactionId,
      type: type,
      mainCategory: mainCategory,
      subCategory: subCategory,
      date: date,
      description: description,
      amount: amount,
      currency: currency,  // NEW
      recurrence: recurrence,
      forWhom: forWhom,
    );

    final index = _transactions.indexWhere((t) => t.id == transactionId);
    if (index != -1) {
      _transactions[index] = updatedTransaction;
    }

    await Future.wait([fetchBalance(), fetchWeekSpending()]);
    
    _refreshAiData(context);
    
    _setLoading(false);
    return true;
  } catch (e) {
    _setWriteError(e.toString().replaceAll('Exception: ', ''));
    _setLoading(false);
    return false;
  }
}

  // Delete a transaction - UPDATED with context parameter
  Future<bool> deleteTransaction(String transactionId, {BuildContext? context}) async {
    _setLoading(true);
    _setWriteError(null);

    try {
      await ApiService.deleteTransaction(transactionId);
      _transactions.removeWhere((t) => t.id == transactionId);
      await Future.wait([fetchBalance(), fetchWeekSpending()]);
      
      // Refresh AI data after deleting transaction
      _refreshAiData(context);
      
      _setLoading(false);
      return true;
    } catch (e) {
      _setWriteError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
      return false;
    }
  }

  /// Undoes a transfer the user made: both legs go together. Throws the
  /// server's refusal (an [ApiException] with its code) for the caller to
  /// explain; on success both legs leave the list and the balance reloads.
  Future<void> undoTransfer(String transferId, {BuildContext? context}) async {
    // Looked up before the request: [context] may be gone once it answers.
    ChatProvider? chat;
    if (context != null) {
      try {
        chat = Provider.of<ChatProvider>(context, listen: false);
      } catch (_) {
        // No chat in the tree (tests): nothing to refresh.
      }
    }
    await ApiService.undoTransfer(transferId);
    _transactions.removeWhere((t) => t.transferId == transferId);
    _weekOutflows = _weekOutflows.where((t) => t.transferId != transferId).toList();
    notifyListeners();
    await Future.wait([fetchBalance(), fetchWeekSpending()]);
    chat?.refreshAiData();
  }

  // Fetch all transactions for the user, optionally filtered by type and date range
  Future<void> fetchTransactions({
  TransactionType? type,
  DateTime? startDate,
  DateTime? endDate,
  Currency? currency,  // NEW
  int? limit,
  int? skip,
}) async {
  _setLoading(true);
  _setError(null);
  final gen = _generation;

  try {
    final int nonNullableLimit = limit ?? 50;
    final int nonNullableSkip = skip ?? 0;

    final result = await ApiService.getTransactions(
      type: type,
      startDate: startDate,
      endDate: endDate,
      currency: currency,  // NEW
      limit: nonNullableLimit,
      skip: nonNullableSkip,
    );
    if (gen != _generation) return;
    _transactions = result;
    _setLoading(false);
  } catch (e) {
    if (gen != _generation) return;
    _setError(e.toString().replaceAll('Exception: ', ''));
    _setLoading(false);
  }
}

  // Fetch every outflow from the last 7 calendar days (all currencies) for
  // the Spending pace card. Bounds are the phone's local day boundaries, as
  // the list screen's filter uses (transaction dates are local date-times).
  Future<void> fetchWeekSpending({DateTime? today}) async {
    final gen = _generation;
    final requestId = ++_weekRequestId;
    final now = today ?? DateTime.now();
    try {
      final result = await ApiService.getTransactions(
        type: TransactionType.outflow,
        startDate: DateTime(now.year, now.month, now.day - 6),
        endDate: DateTime(now.year, now.month, now.day), // today, all of it (sent as a day)
        limit: 10000,
      );
      if (gen != _generation || requestId != _weekRequestId) return;
      // A transfer to the family wallet is not spending.
      _weekOutflows = result.where((t) => !t.isTransfer).toList();
      notifyListeners();
    } catch (e) {
      debugPrint("Error fetching week spending: $e");
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
Future<void> fetchBalance({Currency? currency}) async {
  final gen = _generation;
  final requestId = ++_balanceRequestId;
  try {
    final result = await ApiService.getBalance(currency: currency);
    if (gen != _generation || requestId != _balanceRequestId) return;
    _balance = result;
    notifyListeners();
  } catch (e) {
    debugPrint("Error fetching balance: $e");
  }
}

  // Clear any displayed error message
  void clearError() {
    _error = null;
    notifyListeners();
  }
}