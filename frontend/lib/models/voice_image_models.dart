import 'package:frontend/models/transaction.dart';

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
  final double confidence;
  final String? reasoning;

  ExtractedTransactionData({
    required this.type,
    required this.mainCategory,
    required this.subCategory,
    required this.date,
    this.description,
    required this.amount,
    required this.confidence,
    this.reasoning,
  });

  factory ExtractedTransactionData.fromJson(Map<String, dynamic> json) {
    return ExtractedTransactionData(
      type: json['type'] == 'inflow' ? TransactionType.inflow : TransactionType.outflow,
      mainCategory: json['main_category'],
      subCategory: json['sub_category'],
      date: DateTime.parse(json['date']),
      description: json['description'],
      amount: json['amount'].toDouble(),
      confidence: json['confidence'].toDouble(),
      reasoning: json['reasoning'],
    );
  }
}