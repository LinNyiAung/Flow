import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/app_navigator.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/read_only_banner.dart';
import 'package:provider/provider.dart';

/// The book chip in a book screen's top bar: always names the open book
/// ("Personal" or the family's name), in both modes, and a tap opens the
/// "Which book?" sheet ([showBookSheet]) to switch without leaving the screen.
///
/// Only members of a family see it (like the dashboard's BookSwitch); for
/// everyone else it takes no space.
class BookChip extends StatelessWidget {
  const BookChip({super.key, required this.routeName});

  static const Key chipKey = ValueKey('book-chip');

  /// The named route of the screen showing the chip: after a switch the same
  /// screen is opened again, in the other book.
  final String routeName;

  @override
  Widget build(BuildContext context) {
    final family = Provider.of<FamilyProvider?>(context);
    final books = Provider.of<BookModeProvider?>(context);
    if (family == null || books == null || !family.inFamily) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final name = books.isFamily ? (family.family?.name ?? '') : l.bookPersonal;
    final readOnly = isFamilyReadOnly(context);

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.4),
          child: Semantics(
            button: true,
            excludeSemantics: true,
            label: l.bookChipLabel(name),
            child: Material(
              key: chipKey,
              color: AppTheme.trackFor(context),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => showBookSheet(context, routeName: routeName),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        books.isFamily ? Icons.family_restroom_rounded : Icons.person_rounded,
                        size: 16,
                        color: AppTheme.accentFor(context),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        readOnly ? Icons.lock_rounded : Icons.expand_more_rounded,
                        size: readOnly ? 14 : 18,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Which book?": Personal and the family, a tick on the open one. Picking the
/// other book switches the whole app (which closes the screens above Home)
/// and opens [routeName] again in that book; picking the open one just closes
/// the sheet.
Future<void> showBookSheet(BuildContext context, {required String routeName}) {
  final books = Provider.of<BookModeProvider>(context, listen: false);
  final family = Provider.of<FamilyProvider>(context, listen: false);
  final l = AppLocalizations.of(context);
  var picked = false;

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      void pick(bool toFamily) {
        if (picked) return; // a second tap while the sheet closes
        picked = true;
        Navigator.pop(sheetContext);
        if (toFamily == books.isFamily) return;
        unawaited(openInBookWith(
          books,
          family: toFamily,
          open: () => navigatorKey.currentState?.pushNamed(routeName),
        ));
      }

      Widget row(Key key, IconData icon, String label, bool open, bool toFamily) => ListTile(
            key: key,
            leading: Icon(icon, color: AppTheme.accentFor(sheetContext)),
            title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: open ? Icon(Icons.check_rounded, color: AppTheme.accentFor(sheetContext)) : null,
            selected: open,
            onTap: () => pick(toFamily),
          );

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(l.bookSheetTitle, style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            row(const ValueKey('book-sheet-personal'), Icons.person_rounded, l.bookPersonal, !books.isFamily, false),
            row(const ValueKey('book-sheet-family'), Icons.family_restroom_rounded, family.family?.name ?? '',
                books.isFamily, true),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
