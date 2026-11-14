import 'package:flutter/material.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/read_only_banner.dart';
import 'package:provider/provider.dart';

/// Whether the signed-in person may create, change or delete budgets and
/// goals (and take money out of a goal): always in a Personal book; in the
/// family book only an admin (owner or admin) and only while the family is
/// not read-only. Call it from `build` (it listens), or with `listen: false`
/// elsewhere.
bool canManageBudgetsGoals(BuildContext context, {bool listen = true}) {
  final books = Provider.of<BookModeProvider?>(context, listen: listen);
  if (books == null || !books.isFamily) return true;
  final family = Provider.of<FamilyProvider?>(context, listen: listen);
  return family != null && family.isAdmin && !family.readOnly;
}

/// Whether the signed-in person may add money to a goal: always in a
/// Personal book; in the family book any member, unless it is read-only.
/// Listens like [canManageBudgetsGoals].
bool canAddToGoal(BuildContext context, {bool listen = true}) {
  final books = Provider.of<BookModeProvider?>(context, listen: listen);
  if (books == null || !books.isFamily) return true;
  final family = Provider.of<FamilyProvider?>(context, listen: listen);
  return family != null && family.inFamily && !family.readOnly;
}

/// Why the create, edit and delete controls are missing, shown in Family mode
/// above the budgets or goals: the read-only banner while the family is
/// read-only, else a short "only admins" line for a member. Takes no space
/// for someone who can manage them, and in Personal mode.
class FamilyManageNote extends StatelessWidget {
  const FamilyManageNote({super.key, required this.goals});

  /// True on the Goals screen, false on Budgets (the wording differs).
  final bool goals;

  @override
  Widget build(BuildContext context) {
    if (canManageBudgetsGoals(context)) return const SizedBox.shrink();
    if (isFamilyReadOnly(context)) return const ReadOnlyBanner();
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('family-admins-only-note'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              goals ? l.onlyAdminsChangeFamilyGoals : l.onlyAdminsChangeFamilyBudgets,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.45, color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}