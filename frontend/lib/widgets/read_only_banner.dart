import 'package:flutter/material.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:provider/provider.dart';

/// True when the app shows the family book and the family is read-only (the
/// owner's plan has lapsed): nothing can be added or changed. False in
/// Personal mode and where the family providers aren't in the tree. Call it
/// from `build` (it listens).
bool isFamilyReadOnly(BuildContext context) {
  final books = Provider.of<BookModeProvider?>(context);
  if (books == null || !books.isFamily) return false;
  return Provider.of<FamilyProvider?>(context)?.readOnly ?? false;
}

/// "This family is read-only: the owner's plan has ended", shown in Family
/// mode while the family is read-only. The owner, whose plan it is, gets an
/// Upgrade button. Takes no space otherwise.
class ReadOnlyBanner extends StatelessWidget {
  const ReadOnlyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!isFamilyReadOnly(context)) return const SizedBox.shrink();
    final isOwner = Provider.of<FamilyProvider?>(context)?.isOwner ?? false;
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.lock_rounded, size: 20, color: scheme.tertiary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Wraps; never cut short.
                Text(
                  l.familyReadOnlyBanner,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                    color: scheme.onTertiaryContainer,
                  ),
                ),
                if (isOwner) ...[
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pushNamed('/subscription'),
                    child: Text(l.upgrade),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
