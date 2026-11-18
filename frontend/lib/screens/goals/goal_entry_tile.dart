import 'package:flutter/material.dart';
import 'package:frontend/models/goal_entry.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/date_locale.dart';
import 'package:frontend/utils/family_entries.dart';
import 'package:frontend/utils/money.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// One row of a goal's history: the signed amount, what it was (or who did
/// it, in a family book) and when.
class GoalEntryTile extends StatelessWidget {
  final GoalEntry entry;
  final Currency currency;

  /// Show who did it: family books only.
  final bool showName;

  const GoalEntryTile({super.key, required this.entry, required this.currency, required this.showName});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final carriedOver = entry.kind == GoalEntryKind.carriedOver;
    final added = entry.amount >= 0;

    // A carried-over balance has no name and no date: neither is known.
    final by = entry.addedBy;
    final name = showName && by != null && !carriedOver
        ? memberRefName(l, by, Provider.of<FamilyProvider?>(context))
        : null;
    final label = switch (entry.kind) {
      GoalEntryKind.start => name == null ? l.goalEntryStartedWith : '${l.goalEntryStartedWith} · $name',
      GoalEntryKind.carriedOver => l.goalEntryCarriedOver,
      GoalEntryKind.add || GoalEntryKind.withdraw || GoalEntryKind.other => name,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${added ? '+' : '−'}${formatMoney(entry.amount.abs(), currency)}',
                style: AppTheme.money(15, weight: FontWeight.w700, color: added ? scheme.primary : scheme.onSurface),
              ),
              if (label != null) ...[
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        if (!carriedOver) ...[
          const SizedBox(width: 12),
          Text(
            DateFormat('d MMM, h:mm a', dateLocaleOf(context)).format(entry.createdAt),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
