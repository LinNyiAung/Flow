import 'package:frontend/models/recurring_transaction.dart';
import 'package:frontend/models/user.dart';

enum TransactionType { inflow, outflow }

class Transaction {
  final String id;
  final String userId;
  final TransactionType type;
  final String mainCategory;
  final String subCategory;
  final DateTime date;
  final String? description;
  final double amount;
  final Currency currency;  // NEW
  final DateTime createdAt;
  final DateTime updatedAt;
  final TransactionRecurrence? recurrence;
  final String? parentTransactionId;

  Transaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.mainCategory,
    required this.subCategory,
    required this.date,
    this.description,
    required this.amount,
    required this.currency,  // NEW
    required this.createdAt,
    required this.updatedAt,
    this.recurrence,
    this.parentTransactionId,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'],
      userId: json['user_id'],
      type: json['type'] == 'inflow' ? TransactionType.inflow : TransactionType.outflow,
      mainCategory: json['main_category'],
      subCategory: json['sub_category'],
      date: DateTime.parse(json['date']),
      description: json['description'],
      amount: json['amount'].toDouble(),
      currency: Currency.fromString(json['currency'] ?? 'usd'),  // NEW
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      recurrence: json['recurrence'] != null
          ? TransactionRecurrence.fromJson(json['recurrence'])
          : null,
      parentTransactionId: json['parent_transaction_id'],
    );
  }

  Map<String, dynamic> toJson({bool forUpdate = false}) {
    Map<String, dynamic> data = {
      'type': type.name,
      'main_category': mainCategory,
      'sub_category': subCategory,
      'date': date.toIso8601String(),
      'description': description,
      'amount': amount,
      'currency': currency.name,  // NEW
      if (recurrence != null) 'recurrence': recurrence!.toJson(),
    };
    if (forUpdate) {
      data.remove('created_at');
      data.remove('updated_at');
      data.remove('user_id');
      data.remove('id');
    }
    return data;
  }
  
  // Helper method to display amount with currency symbol
  String get displayAmount {
    return '${currency.symbol}${amount.toStringAsFixed(2)}';
  }
}

class Balance {
  final Currency currency;  // NEW
  final double balance;
  final double availableBalance;
  final double allocatedToGoals;
  final double totalInflow;
  final double totalOutflow;

  Balance({
    required this.currency,  // NEW
    required this.balance,
    required this.availableBalance,
    required this.allocatedToGoals,
    required this.totalInflow,
    required this.totalOutflow,
  });

  factory Balance.fromJson(Map<String, dynamic> json) {
    return Balance(
      currency: Currency.fromString(json['currency'] ?? 'usd'),  // NEW
      balance: json['balance'].toDouble(),
      availableBalance: json['available_balance'].toDouble(),
      allocatedToGoals: json['allocated_to_goals'].toDouble(),
      totalInflow: json['total_inflow'].toDouble(),
      totalOutflow: json['total_outflow'].toDouble(),
    );
  }
  
  // Helper method to display balance with currency symbol
  String get displayBalance {
    return '${currency.symbol}${balance.toStringAsFixed(2)}';
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

  Category({
    required this.mainCategory,
    required this.subCategories,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      mainCategory: json['main_category'],
      subCategories: List<String>.from(json['sub_categories']),
    );
  }
}

