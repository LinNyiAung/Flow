enum TransactionType { inflow, outflow }

class Transaction {
  final String id;
  final String userId;
  final TransactionType type;
  final String mainCategory;
  final String subCategory;
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
      description: json['description'],
      amount: json['amount'].toDouble(),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'type': type.name,
      'main_category': mainCategory,
      'sub_category': subCategory,
      'description': description,
      'amount': amount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
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
  final double totalInflow;
  final double totalOutflow;

  Balance({
    required this.balance,
    required this.totalInflow,
    required this.totalOutflow,
  });

  factory Balance.fromJson(Map<String, dynamic> json) {
    return Balance(
      balance: json['balance'].toDouble(),
      totalInflow: json['total_inflow'].toDouble(),
      totalOutflow: json['total_outflow'].toDouble(),
    );
  }
}