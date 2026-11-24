import 'package:frontend/utils/date_parsing.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/models/user.dart';

/// `POST /api/transactions/transcribe-audio`. [voiceToken] is present only
/// when the server counted a non-empty transcript; send it back with the exact
/// same text to the text extraction so the voice entry counts as one use. A
/// silent recording has an empty [transcription] and no token.
class TranscriptionResult {
  final String transcription;
  final String? voiceToken;

  const TranscriptionResult({required this.transcription, this.voiceToken});

  bool get isSilent => transcription.trim().isEmpty;

  factory TranscriptionResult.fromJson(Map<String, dynamic> json) {
    final token = json['voice_token'];
    return TranscriptionResult(
      transcription: json['transcription'] is String
          ? json['transcription'] as String
          : '',
      voiceToken: token is String && token.isNotEmpty ? token : null,
    );
  }
}

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

  /// Family book: who it was for (member ids), as chosen in the entry form.
  /// null: not chosen (Whole family), and `for_whom` is not sent.
  final List<String>? forWhom;

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
    this.forWhom,
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
      forWhom: json['for_whom'] is List
          ? List<String>.unmodifiable((json['for_whom'] as List).whereType<String>())
          : null,
    );
  }

  /// The AI couldn't read an amount: the user must enter one (> 0) before
  /// this item can be saved — the backend rejects amount <= 0 with 422.
  bool get needsAmount => !(amount > 0);

  /// [description], [reasoning] and [forWhom] are cleared by passing null;
  /// left out, every field keeps its value.
  ExtractedTransactionData copyWith({
    TransactionType? type,
    String? mainCategory,
    String? subCategory,
    DateTime? date,
    Object? description = _unset,
    double? amount,
    Currency? currency,
    double? confidence,
    Object? reasoning = _unset,
    Object? forWhom = _unset,
  }) {
    return ExtractedTransactionData(
      type: type ?? this.type,
      mainCategory: mainCategory ?? this.mainCategory,
      subCategory: subCategory ?? this.subCategory,
      date: date ?? this.date,
      description: identical(description, _unset) ? this.description : description as String?,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      confidence: confidence ?? this.confidence,
      reasoning: identical(reasoning, _unset) ? this.reasoning : reasoning as String?,
      forWhom: identical(forWhom, _unset) ? this.forWhom : forWhom as List<String>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'main_category': mainCategory,
      'sub_category': subCategory,
      'date': toWallClockString(date),
      'description': description,
      'amount': amount,
      'currency': currency.name,  // ADDED CURRENCY
      // As New entry sends it: family book only; [] is Whole family.
      if (forWhom != null) 'for_whom': forWhom,
    };
  }
}

/// [ExtractedTransactionData.copyWith]: "not given", for the fields that can
/// be cleared with null.
const Object _unset = Object();

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