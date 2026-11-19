import 'package:frontend/models/family.dart';
import 'package:frontend/utils/money.dart';
import 'package:frontend/utils/date_parsing.dart';
import 'package:frontend/models/recurring_transaction.dart';
import 'package:frontend/models/user.dart';

enum TransactionType { inflow, outflow }


class Transaction {
  final String id;
  final String bookId;
  final TransactionType type;
  final String mainCategory;
  final String subCategory;
  final DateTime date;
  final String? description;
  final double amount;
  final Currency currency; // NEW
  final DateTime createdAt;
  final DateTime updatedAt;
  final TransactionRecurrence? recurrence;
  final String? parentTransactionId;

  /// Family book: who recorded it (null in a personal book).
  final FamilyMemberRef? addedBy;

  /// Family book: the member ids it was for; empty means Whole family.
  final List<String> forWhom;

  /// Set on each leg of a transfer between a personal wallet and the family
  /// wallet; null for a normal entry.
  final String? transferId;

  Transaction({
    required this.id,
    required this.bookId,
    required this.type,
    required this.mainCategory,
    required this.subCategory,
    required this.date,
    this.description,
    required this.amount,
    required this.currency, // NEW
    required this.createdAt,
    required this.updatedAt,
    this.recurrence,
    this.parentTransactionId,
    this.addedBy,
    this.forWhom = const [],
    this.transferId,
  });

  /// One leg of a transfer: not income or spending, and it can't be edited.
  bool get isTransfer => transferId != null;

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'],
      bookId: json['book_id'],
      type: json['type'] == 'inflow'
          ? TransactionType.inflow
          : TransactionType.outflow,
      mainCategory: json['main_category'],
      subCategory: json['sub_category'],
      date: parseWallClock(json['date']),
      description: json['description'],
      amount: json['amount'].toDouble(),
      currency: Currency.fromString(json['currency'] ?? 'usd'), // NEW
      createdAt: parseInstant(json['created_at']),
      updatedAt: parseInstant(json['updated_at']),
      recurrence: json['recurrence'] != null
          ? TransactionRecurrence.fromJson(json['recurrence'])
          : null,
      parentTransactionId: json['parent_transaction_id'],
      addedBy: FamilyMemberRef.tryParse(json['added_by']),
      forWhom: json['for_whom'] is List
          ? List<String>.unmodifiable((json['for_whom'] as List).whereType<String>())
          : const [],
      transferId: json['transfer_id'] is String ? json['transfer_id'] as String : null,
    );
  }

  Map<String, dynamic> toJson({bool forUpdate = false}) {
    Map<String, dynamic> data = {
      'type': type.name,
      'main_category': mainCategory,
      'sub_category': subCategory,
      'date': toWallClockString(date),
      'description': description,
      'amount': amount,
      'currency': currency.name, // NEW
      if (recurrence != null) 'recurrence': recurrence!.toJson(),
    };
    if (forUpdate) {
      data.remove('created_at');
      data.remove('updated_at');
      data.remove('book_id');
      data.remove('id');
    }
    return data;
  }

  // Helper method to display amount with currency symbol
  String get displayAmount {
    return formatMoney(amount, currency);
  }
}

class Balance {
  final Currency currency;
  final double balance;
  final double availableBalance;
  final double allocatedToGoals;
  final double totalInflow;
  final double totalOutflow;

  Balance({
    required this.currency,
    required this.balance,
    required this.availableBalance,
    required this.allocatedToGoals,
    required this.totalInflow,
    required this.totalOutflow,
  });

  factory Balance.fromJson(Map<String, dynamic> json) {
    return Balance(
      currency: Currency.fromString(json['currency'] ?? 'usd'),
      // FIX: Add (json['field'] ?? 0) to handle nulls safely
      balance: (json['balance'] ?? 0).toDouble(),
      availableBalance: (json['available_balance'] ?? 0).toDouble(),
      allocatedToGoals: (json['allocated_to_goals'] ?? 0).toDouble(),
      totalInflow: (json['total_inflow'] ?? 0).toDouble(),
      totalOutflow: (json['total_outflow'] ?? 0).toDouble(),
    );
  }

  // Helper method to display balance with currency symbol
  String get displayBalance {
    return formatMoney(balance, currency);
  }
}

// NEW - Multi-currency balance model
class MultiCurrencyBalance {
  final Map<Currency, Balance> balances;

  MultiCurrencyBalance({required this.balances});

  factory MultiCurrencyBalance.fromJson(Map<String, dynamic> json) {
    final balancesData = json['balances'] as Map<String, dynamic>;
    final balances = <Currency, Balance>{};

    balancesData.forEach((key, value) {
      final currency = Currency.fromString(key);
      balances[currency] = Balance.fromJson(value as Map<String, dynamic>);
    });

    return MultiCurrencyBalance(balances: balances);
  }

  // Get balance for specific currency
  Balance? getBalanceForCurrency(Currency currency) {
    return balances[currency];
  }

  // Get all currencies with transactions
  List<Currency> get currencies => balances.keys.toList();
}

class Category {
  final String mainCategory;
  final List<String> subCategories;

  Category({required this.mainCategory, required this.subCategories});

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      mainCategory: json['main_category'],
      subCategories: List<String>.from(json['sub_categories']),
    );
  }
}
