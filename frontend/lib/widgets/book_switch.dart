import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// The Personal / Family switch, at the top of the dashboard and in the side
/// menu: two segments, "Personal" and the family's name. The selected one is
/// the book the whole app shows.
///
/// Only members of a family see it; for everyone else (and where the family
/// providers aren't in the tree) it takes no space, so the app looks as it
/// always did.
class BookSwitch extends StatelessWidget {
  const BookSwitch({super.key, this.onBeforeSwitch});

  static const Key personalKey = ValueKey('book-switch-personal');
  static const Key familyKey = ValueKey('book-switch-family');

  /// Runs before a switch (the side menu closes itself).
  final VoidCallback? onBeforeSwitch;

  @override
  Widget build(BuildContext context) {
    final family = Provider.of<FamilyProvider?>(context);
    final books = Provider.of<BookModeProvider?>(context);
    if (family == null || books == null || !family.inFamily) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);

    void select(BookMode mode) {
      if (books.mode == mode) return;
      onBeforeSwitch?.call();
      unawaited(books.setMode(mode));
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppTheme.trackFor(context), borderRadius: BorderRadius.circular(12)),
      // Both segments as tall as the taller one (a long family name wraps).
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Segment(
                key: personalKey,
                icon: Icons.person_rounded,
                label: l.bookPersonal,
                selected: !books.isFamily,
                onTap: () => select(BookMode.personal),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _Segment(
                key: familyKey,
                icon: Icons.family_restroom_rounded,
                label: family.family?.name ?? '',
                selected: books.isFamily,
                onTap: () => select(BookMode.family),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = selected ? scheme.onSurface : scheme.onSurfaceVariant;

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? (theme.cardTheme.color ?? scheme.surface) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected ? const [BoxShadow(color: Color(0x14101815), blurRadius: 2)] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ExcludeSemantics(
                child: Icon(icon, size: 18, color: selected ? AppTheme.accentFor(context) : ink),
              ),
              const SizedBox(width: 6),
              // A long family name takes two lines, then ends in "…".
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [title] for a screen that shows one book: as is in Personal mode (and for
/// people with no family), "title · family name" in Family mode, so it is
/// always clear which book is open. Call it from `build` (it listens).
String bookTitle(BuildContext context, String title) {
  final name = bookFamilyName(context);
  return name == null ? title : '$title · $name';
}

/// The family's name in Family mode; null in Personal mode, with no family,
/// or where the family providers aren't in the tree. Call it from `build`.
String? bookFamilyName(BuildContext context) {
  final books = Provider.of<BookModeProvider?>(context);
  if (books == null || !books.isFamily) return null;
  final name = Provider.of<FamilyProvider?>(context)?.family?.name.trim();
  return name == null || name.isEmpty ? null : name;
}
