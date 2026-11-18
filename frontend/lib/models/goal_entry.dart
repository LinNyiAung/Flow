import 'package:frontend/models/family.dart';
import 'package:frontend/utils/date_parsing.dart';

/// What a goal entry records: the money a goal started with, an Add, a
/// Withdraw, or the balance carried over when history began. [other] is a
/// kind this app doesn't know yet (a newer server): it shows like an Add or a
/// Withdraw, by the amount's sign, instead of failing the whole history.
enum GoalEntryKind {
  start,
  add,
  withdraw,
  carriedOver,
  other;

  static GoalEntryKind fromJson(String value) => switch (value) {
        'start' => start,
        'add' => add,
        'withdraw' => withdraw,
        'carried_over' => carriedOver,
        _ => other,
      };
}

/// One entry of `GET /api/goals/{id}/history`.
class GoalEntry {
  final String id;
  final GoalEntryKind kind;

  /// Signed: negative for a withdrawal.
  final double amount;

  /// Local time.
  final DateTime createdAt;

  /// Who did it; null in a personal book and for a carried-over balance.
  final FamilyMemberRef? addedBy;

  const GoalEntry({
    required this.id,
    required this.kind,
    required this.amount,
    required this.createdAt,
    this.addedBy,
  });

  factory GoalEntry.fromJson(Map<String, dynamic> json) => GoalEntry(
        id: json['id'] as String,
        kind: GoalEntryKind.fromJson(json['kind'] as String),
        amount: (json['amount'] as num).toDouble(),
        createdAt: parseInstant(json['created_at']),
        addedBy: FamilyMemberRef.tryParse(json['added_by']),
      );
}

/// A page of a goal's history (newest first) and how many entries it has.
class GoalHistoryPage {
  final List<GoalEntry> entries;
  final int total;

  const GoalHistoryPage({required this.entries, required this.total});

  factory GoalHistoryPage.fromJson(Map<String, dynamic> json) => GoalHistoryPage(
        entries: [
          for (final e in json['entries'] as List) GoalEntry.fromJson(e as Map<String, dynamic>),
        ],
        total: json['total'] as int,
      );
}
