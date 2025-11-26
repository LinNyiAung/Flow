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
      date: DateTime.parse(json['date']),
      description: json['description'],
      amount: json['amount'].toDouble(),
      currency: Currency.fromString(json['currency'] ?? 'usd'),  // ADDED CURRENCY WITH FALLBACK
      confidence: json['confidence'].toDouble(),
      reasoning: json['reasoning'],
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
  final String? analysis;

  MultipleExtractedTransactions({
    required this.transactions,
    required this.totalCount,
    required this.overallConfidence,
    this.analysis,
  });

  factory MultipleExtractedTransactions.fromJson(Map<String, dynamic> json) {
    return MultipleExtractedTransactions(
      transactions: (json['transactions'] as List)
          .map((tx) => ExtractedTransactionData.fromJson(tx))
          .toList(),
      totalCount: json['total_count'],
      overallConfidence: json['overall_confidence'].toDouble(),
      analysis: json['analysis'],
    );
  }
}