import 'package:frontend/utils/date_parsing.dart';

/// Where a custom insight is in its life. `unknown` is any status a newer
/// server sends that this app does not know; show it as not available.
enum CustomInsightStatus { pending, ready, failed, refused, unknown }

CustomInsightStatus _statusOf(dynamic value) {
  if (value is! String) return CustomInsightStatus.unknown;
  for (final s in CustomInsightStatus.values) {
    if (s != CustomInsightStatus.unknown && s.name == value) return s;
  }
  return CustomInsightStatus.unknown;
}

/// The four ready-made questions the server knows (`preset` of a request).
class CustomInsightPreset {
  CustomInsightPreset._();

  static const String whereToSave = 'where_to_save';
  static const String comparePrevious = 'compare_previous';
  static const String biggestChanges = 'biggest_changes';
  static const String budgetsGoals = 'budgets_goals';

  static const List<String> all = [
    whereToSave,
    comparePrevious,
    biggestChanges,
    budgetsGoals,
  ];
}

double _double(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

double? _doubleOrNull(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// `"2026-10-31"` as a local date-only [DateTime].
DateTime _date(dynamic value) {
  final d = parseWallClock(value);
  return DateTime(d.year, d.month, d.day);
}

String _formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One of a currency's biggest spending categories in the range.
class CategoryAmount {
  final String mainCategory;
  final String subCategory;
  final double amount;

  const CategoryAmount({
    required this.mainCategory,
    required this.subCategory,
    required this.amount,
  });

  factory CategoryAmount.fromJson(Map<String, dynamic> json) => CategoryAmount(
        mainCategory: json['main_category'] is String ? json['main_category'] as String : '',
        subCategory: json['sub_category'] is String ? json['sub_category'] as String : '',
        amount: _double(json['amount']),
      );
}

/// The key figures of the range in one currency, with the previous period of
/// equal length. A change percentage is null when the previous figure was 0.
class CurrencyFigures {
  final String currency;
  final double income;
  final double spending;
  final double net;
  final int transactions;
  final List<CategoryAmount> topCategories;
  final double previousIncome;
  final double previousSpending;
  final double? incomeChangePct;
  final double? spendingChangePct;

  const CurrencyFigures({
    required this.currency,
    required this.income,
    required this.spending,
    required this.net,
    required this.transactions,
    this.topCategories = const [],
    required this.previousIncome,
    required this.previousSpending,
    this.incomeChangePct,
    this.spendingChangePct,
  });

  factory CurrencyFigures.fromJson(Map<String, dynamic> json) {
    final top = json['top_categories'];
    return CurrencyFigures(
      currency: json['currency'] is String ? json['currency'] as String : '',
      income: _double(json['income']),
      spending: _double(json['spending']),
      net: _double(json['net']),
      transactions: json['transactions'] is num ? (json['transactions'] as num).toInt() : 0,
      topCategories: top is List
          ? [
              for (final c in top)
                if (c is Map) CategoryAmount.fromJson(Map<String, dynamic>.from(c)),
            ]
          : const [],
      previousIncome: _double(json['previous_income']),
      previousSpending: _double(json['previous_spending']),
      incomeChangePct: _doubleOrNull(json['income_change_pct']),
      spendingChangePct: _doubleOrNull(json['spending_change_pct']),
    );
  }
}

/// The figures stored with a report: one entry per currency that has
/// transactions in the range, plus the dates of the previous period.
class CustomInsightFigures {
  final DateTime previousStart;
  final DateTime previousEnd;
  final List<CurrencyFigures> currencies;

  const CustomInsightFigures({
    required this.previousStart,
    required this.previousEnd,
    this.currencies = const [],
  });

  factory CustomInsightFigures.fromJson(Map<String, dynamic> json) {
    final list = json['currencies'];
    return CustomInsightFigures(
      previousStart: _date(json['previous_start']),
      previousEnd: _date(json['previous_end']),
      currencies: list is List
          ? [
              for (final c in list)
                if (c is Map) CurrencyFigures.fromJson(Map<String, dynamic>.from(c)),
            ]
          : const [],
    );
  }
}

/// A custom insight: a list row (no [content], [figures]) or the full report.
/// Dates are local date-only values; [createdAt] and [completedAt] are instants
/// in local time.
class CustomInsight {
  final String id;
  final DateTime startDate;
  final DateTime endDate;

  /// A [CustomInsightPreset] key, or null.
  final String? preset;
  final String? instruction;
  final CustomInsightStatus status;
  final DateTime createdAt;
  final DateTime? completedAt;

  /// True when a Myanmar translation is stored (the list rows carry no text).
  final bool hasMyanmar;
  final String? content;
  final String? contentMm;
  final CustomInsightFigures? figures;

  const CustomInsight({
    required this.id,
    required this.startDate,
    required this.endDate,
    this.preset,
    this.instruction,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.hasMyanmar = false,
    this.content,
    this.contentMm,
    this.figures,
  });

  bool get isPending => status == CustomInsightStatus.pending;
  bool get isReady => status == CustomInsightStatus.ready;

  factory CustomInsight.fromJson(Map<String, dynamic> json) {
    final preset = json['preset'];
    final instruction = json['instruction'];
    final content = json['content'];
    final contentMm = json['content_mm'];
    final figures = json['figures'];
    return CustomInsight(
      id: json['id'].toString(),
      startDate: _date(json['start_date']),
      endDate: _date(json['end_date']),
      preset: preset is String && preset.isNotEmpty ? preset : null,
      instruction: instruction is String && instruction.isNotEmpty ? instruction : null,
      status: _statusOf(json['status']),
      createdAt: parseInstantOrNull(json['created_at']) ?? DateTime.now(),
      completedAt: parseInstantOrNull(json['completed_at']),
      hasMyanmar: json['has_myanmar'] == true || (contentMm is String && contentMm.isNotEmpty),
      content: content is String ? content : null,
      contentMm: contentMm is String && contentMm.isNotEmpty ? contentMm : null,
      figures: figures is Map
          ? CustomInsightFigures.fromJson(Map<String, dynamic>.from(figures))
          : null,
    );
  }

  /// A copy with the given fields replaced (a null leaves a field as it is).
  CustomInsight copyWith({
    CustomInsightStatus? status,
    DateTime? completedAt,
    bool? hasMyanmar,
    String? content,
    String? contentMm,
    CustomInsightFigures? figures,
  }) =>
      CustomInsight(
        id: id,
        startDate: startDate,
        endDate: endDate,
        preset: preset,
        instruction: instruction,
        status: status ?? this.status,
        createdAt: createdAt,
        completedAt: completedAt ?? this.completedAt,
        hasMyanmar: hasMyanmar ?? this.hasMyanmar,
        content: content ?? this.content,
        contentMm: contentMm ?? this.contentMm,
        figures: figures ?? this.figures,
      );
}

/// The body of `POST /api/custom-insights`: a range and at most one of a
/// preset or the user's own instruction.
class CustomInsightRequest {
  final DateTime startDate;
  final DateTime endDate;
  final String? preset;
  final String? instruction;

  const CustomInsightRequest({
    required this.startDate,
    required this.endDate,
    this.preset,
    this.instruction,
  });

  Map<String, dynamic> toJson() {
    final text = instruction?.trim() ?? '';
    return {
      'start_date': _formatDate(startDate),
      'end_date': _formatDate(endDate),
      if (preset != null) 'preset': preset,
      if (text.isNotEmpty) 'instruction': text,
    };
  }
}

/// The answer of a create: [reused] is true when an earlier ready report for
/// the same range and question was returned (nothing was used up).
class CustomInsightCreateResult {
  final CustomInsight report;
  final bool reused;

  const CustomInsightCreateResult({required this.report, required this.reused});

  factory CustomInsightCreateResult.fromJson(Map<String, dynamic> json) =>
      CustomInsightCreateResult(
        report: CustomInsight.fromJson(Map<String, dynamic>.from(json['report'] as Map)),
        reused: json['reused'] == true,
      );
}
