import 'package:frontend/models/family.dart';
import 'package:frontend/models/user.dart';

// The Family spending screen's data: `GET /api/family/spending` (one month,
// per person it was for) and `GET /api/family/spending/person` (one person's
// month in depth). Amounts are the family book's own split, the same as the
// Reports "Who we spent on" rows.

String? _string(dynamic v) => v is String ? v : null;
double _double(dynamic v) => v is num ? v.toDouble() : 0.0;
int _int(dynamic v) => v is num ? v.toInt() : 0;

List<Map<String, dynamic>> _maps(dynamic v) =>
    v is List ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const [];

/// The 1st of a `YYYY-MM` month (local), or null.
DateTime? parseSpendingMonth(dynamic v) {
  final m = v is String ? RegExp(r'^(\d{4})-(\d{2})$').firstMatch(v) : null;
  return m == null ? null : DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!));
}

/// `YYYY-MM` of [month].
String spendingMonthParam(DateTime month) =>
    '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';

/// One person (or Whole family) in a month.
class FamilySpendingRow {
  /// Null for the Whole family row.
  final String? memberId;

  /// The server's name ("Whole family" in English for that row: show the
  /// app's own string instead).
  final String displayName;

  /// `active` or `former`.
  final String status;
  final double amount;
  final double previousAmount;

  const FamilySpendingRow({
    this.memberId,
    required this.displayName,
    this.status = FamilyMember.statusActive,
    required this.amount,
    this.previousAmount = 0,
  });

  bool get isWholeFamily => memberId == null;
  bool get isFormer => status == FamilyMember.statusFormer;

  factory FamilySpendingRow.fromJson(Map<String, dynamic> json) => FamilySpendingRow(
        memberId: _string(json['member_id']),
        displayName: _string(json['display_name']) ?? '',
        status: _string(json['status']) ?? FamilyMember.statusActive,
        amount: _double(json['amount']),
        previousAmount: _double(json['previous_amount']),
      );
}

/// `GET /api/family/spending`: one month, largest first.
class FamilySpendingOverview {
  final Currency currency;

  /// The 1st of the month.
  final DateTime month;
  final double total;
  final double previousTotal;
  final List<FamilySpendingRow> rows;

  /// The currencies the family book has spending in.
  final List<Currency> currencies;

  /// The first month with spending in [currency]; null when there is none.
  final DateTime? firstMonth;

  const FamilySpendingOverview({
    required this.currency,
    required this.month,
    required this.total,
    this.previousTotal = 0,
    required this.rows,
    this.currencies = const [],
    this.firstMonth,
  });

  factory FamilySpendingOverview.fromJson(Map<String, dynamic> json) => FamilySpendingOverview(
        currency: Currency.fromString(_string(json['currency']) ?? 'usd'),
        month: parseSpendingMonth(json['month']) ?? DateTime(DateTime.now().year, DateTime.now().month),
        total: _double(json['total']),
        previousTotal: _double(json['previous_total']),
        rows: _maps(json['rows']).map(FamilySpendingRow.fromJson).toList(),
        currencies: (json['currencies'] is List ? json['currencies'] as List : const [])
            .whereType<String>()
            .map(Currency.fromString)
            .toList(),
        firstMonth: parseSpendingMonth(json['first_month']),
      );
}

class SubCategorySpending {
  final String subCategory;
  final double amount;
  const SubCategorySpending({required this.subCategory, required this.amount});

  factory SubCategorySpending.fromJson(Map<String, dynamic> json) =>
      SubCategorySpending(subCategory: _string(json['sub_category']) ?? '', amount: _double(json['amount']));
}

/// One main category of a person's month (their share of each entry).
class CategorySpending {
  final String mainCategory;
  final double amount;
  final List<SubCategorySpending> subCategories;
  const CategorySpending({required this.mainCategory, required this.amount, this.subCategories = const []});

  factory CategorySpending.fromJson(Map<String, dynamic> json) => CategorySpending(
        mainCategory: _string(json['main_category']) ?? '',
        amount: _double(json['amount']),
        subCategories: _maps(json['sub_categories']).map(SubCategorySpending.fromJson).toList(),
      );
}

class MonthAmount {
  /// The 1st of the month.
  final DateTime month;
  final double amount;
  const MonthAmount({required this.month, required this.amount});

  factory MonthAmount.fromJson(Map<String, dynamic> json) =>
      MonthAmount(month: parseSpendingMonth(json['month']) ?? DateTime(1970), amount: _double(json['amount']));
}

/// One of a person's biggest entries in the month.
class SpendingEntry {
  final String id;

  /// The entry's calendar date.
  final DateTime date;
  final String mainCategory;
  final String subCategory;
  final String? description;

  /// The whole entry.
  final double amount;

  /// This person's part of it.
  final double share;

  /// How many people it was for (0: Whole family, 1: only this person).
  final int splitBetween;

  const SpendingEntry({
    required this.id,
    required this.date,
    required this.mainCategory,
    required this.subCategory,
    this.description,
    required this.amount,
    required this.share,
    required this.splitBetween,
  });

  factory SpendingEntry.fromJson(Map<String, dynamic> json) => SpendingEntry(
        id: _string(json['id']) ?? '',
        date: DateTime.tryParse(_string(json['date']) ?? '') ?? DateTime(1970),
        mainCategory: _string(json['main_category']) ?? '',
        subCategory: _string(json['sub_category']) ?? '',
        description: _string(json['description']),
        amount: _double(json['amount']),
        share: _double(json['share']),
        splitBetween: _int(json['split_between']),
      );
}

class AddedByCount {
  final String memberId;
  final String displayName;

  /// [FamilyMember.statusActive] or [FamilyMember.statusFormer] (left the family).
  final String status;
  final int count;
  const AddedByCount(
      {required this.memberId, required this.displayName, this.status = FamilyMember.statusActive, required this.count});

  bool get isFormer => status == FamilyMember.statusFormer;

  factory AddedByCount.fromJson(Map<String, dynamic> json) => AddedByCount(
        memberId: _string(json['member_id']) ?? '',
        displayName: _string(json['display_name']) ?? '',
        status: _string(json['status']) ?? FamilyMember.statusActive,
        count: _int(json['count']),
      );
}

/// `GET /api/family/spending/person`: one person's month (or Whole family's).
class FamilyPersonSpending {
  final Currency currency;
  final DateTime month;
  final String? memberId;
  final String displayName;
  final String status;
  final double amount;
  final double previousAmount;
  final List<CategorySpending> categories;

  /// Six months, oldest first, ending at [month].
  final List<MonthAmount> trend;
  final List<SpendingEntry> topEntries;
  final List<AddedByCount> addedBy;

  const FamilyPersonSpending({
    required this.currency,
    required this.month,
    this.memberId,
    required this.displayName,
    this.status = FamilyMember.statusActive,
    required this.amount,
    this.previousAmount = 0,
    this.categories = const [],
    this.trend = const [],
    this.topEntries = const [],
    this.addedBy = const [],
  });

  bool get isWholeFamily => memberId == null;
  bool get isFormer => status == FamilyMember.statusFormer;

  factory FamilyPersonSpending.fromJson(Map<String, dynamic> json) => FamilyPersonSpending(
        currency: Currency.fromString(_string(json['currency']) ?? 'usd'),
        month: parseSpendingMonth(json['month']) ?? DateTime(1970),
        memberId: _string(json['member_id']),
        displayName: _string(json['display_name']) ?? '',
        status: _string(json['status']) ?? FamilyMember.statusActive,
        amount: _double(json['amount']),
        previousAmount: _double(json['previous_amount']),
        categories: _maps(json['categories']).map(CategorySpending.fromJson).toList(),
        trend: _maps(json['trend']).map(MonthAmount.fromJson).toList(),
        topEntries: _maps(json['top_entries']).map(SpendingEntry.fromJson).toList(),
        addedBy: _maps(json['added_by']).map(AddedByCount.fromJson).toList(),
      );
}
