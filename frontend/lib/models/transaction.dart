enum TransactionType { inflow, outflow }

class Transaction {
  final String id;
  final String userId;
  final TransactionType type;
  final String mainCategory;
  final String subCategory;
  final DateTime date; // Added date field
  final String? description;
  final double amount;
  final DateTime createdAt;
  final DateTime updatedAt;

  Transaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.mainCategory,
    required this.subCategory,
    required this.date, // Added date field
    this.description,
    required this.amount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'],
      userId: json['user_id'],
      type: json['type'] == 'inflow' ? TransactionType.inflow : TransactionType.outflow,
      mainCategory: json['main_category'],
      subCategory: json['sub_category'],
      date: DateTime.parse(json['date']), // Parse the date
      description: json['description'],
      amount: json['amount'].toDouble(),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson({bool forUpdate = false}) {
    // For update, we don't need id, user_id, created_at, updated_at
    Map<String, dynamic> data = {
      'type': type.name,
      'main_category': mainCategory,
      'sub_category': subCategory,
      'date': date.toIso8601String(), // Format date for JSON
      'description': description,
      'amount': amount,
    };
    if (forUpdate) {
      data.remove('created_at'); // Remove fields not typically updated directly
      data.remove('updated_at');
      data.remove('user_id');
      data.remove('id');
    }
    return data;
  }
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

class Balance {
  final double balance;
  final double availableBalance;
  final double allocatedToGoals;
  final double totalInflow;
  final double totalOutflow;

  Balance({
    required this.balance,
    required this.availableBalance,
    required this.allocatedToGoals,
    required this.totalInflow,
    required this.totalOutflow,
  });

  factory Balance.fromJson(Map<String, dynamic> json) {
    return Balance(
      balance: json['balance'].toDouble(),
      availableBalance: json['available_balance'].toDouble(),
      allocatedToGoals: json['allocated_to_goals'].toDouble(),
      totalInflow: json['total_inflow'].toDouble(),
      totalOutflow: json['total_outflow'].toDouble(),
    );
  }
}