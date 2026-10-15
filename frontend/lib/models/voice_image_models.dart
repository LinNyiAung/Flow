import 'package:frontend/utils/date_parsing.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/models/user.dart';

class TransactionExtractionRequest {
  final String? text;
  final String? base64Image;
  final String type; // 'voice' or 'image'

  TransactionExtractionRequest({
    this.text,
    this.base64Image,
    required this.type,
  });

  Map<String, dynamic> toJson() {
    return {
      if (text != null) 'text': text,
      if (base64Image != null) 'base64_image': base64Image,
      'type': type,
    };
  }
}

class ExtractedTransactionData {
  final TransactionType type;
  final String mainCategory;
  final String subCategory;
  final DateTime date;
  final String? description;
  final double amount;
  final Currency currency;  // ADDED CURRENCY
  final double confidence;
  final String? reasoning;

  ExtractedTransactionData({
    required this.type,
    required this.mainCategory,
    required this.subCategory,
    required this.date,
    this.description,
    required this.amount,
    required this.currency,  // ADDED CURRENCY
    required this.confidence,
    this.reasoning,
  });

  factory ExtractedTransactionData.fromJson(Map<String, dynamic> json) {
    return ExtractedTransactionData(
      type: json['type'] == 'inflow'
          ? TransactionType.inflow
          : TransactionType.outflow,
      mainCategory: json['main_category'],
      subCategory: json['sub_category'],
      date: parseWallClock(json['date']),
      description: json['description'],
      // The backend returns amount 0 / confidence 0 when the AI couldn't
      // read an amount (see [needsAmount]).
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: Currency.fromString(json['currency'] ?? 'usd'),  // ADDED CURRENCY WITH FALLBACK
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      reasoning: json['reasoning'],
    );
  }

  /// The AI couldn't read an amount: the user must enter one (> 0) before
  /// this item can be saved — the backend rejects amount <= 0 with 422.
  bool get needsAmount => !(amount > 0);

  ExtractedTransactionData copyWith({double? amount}) {
    return ExtractedTransactionData(
      type: type,
      mainCategory: mainCategory,
      subCategory: subCategory,
      date: date,
      description: description,
      amount: amount ?? this.amount,
      currency: currency,
      confidence: confidence,
      reasoning: reasoning,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'main_category': mainCategory,
      'sub_category': subCategory,
      'date': date.toIso8601String(),
      'description': description,
      'amount': amount,
      'currency': currency.name,  // ADDED CURRENCY
    };
  }
}

// NEW: Model for multiple transaction extractions
class MultipleExtractedTransactions {
  final List<ExtractedTransactionData> transactions;
  final int totalCount;
  final double overallConfidence;

  /// May mention how many items were omitted (zero / invalid amounts).
  final String? analysis;

  MultipleExtractedTransactions({
    required this.transactions,
    required this.totalCount,
    required this.overallConfidence,
    this.analysis,
  });

  MultipleExtractedTransactions copyWith({
    List<ExtractedTransactionData>? transactions,
  }) {
    return MultipleExtractedTransactions(
      transactions: transactions ?? this.transactions,
      totalCount: totalCount,
      overallConfidence: overallConfidence,
      analysis: analysis,
    );
  }

  factory MultipleExtractedTransactions.fromJson(Map<String, dynamic> json) {
    final transactions = ((json['transactions'] as List?) ?? const [])
        .map((tx) => ExtractedTransactionData.fromJson(tx))
        .toList();
    return MultipleExtractedTransactions(
      transactions: transactions,
      totalCount: (json['total_count'] as num?)?.toInt() ?? transactions.length,
      overallConfidence: (json['overall_confidence'] as num?)?.toDouble() ?? 0,
      analysis: json['analysis'],
    );
  }
}