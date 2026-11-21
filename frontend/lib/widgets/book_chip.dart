import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:frontend/app_navigator.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/app_bar_title.dart';
import 'package:frontend/widgets/read_only_banner.dart';
import 'package:provider/provider.dart';

/// The book chip in a book screen's top bar: always names the open book
/// ("Personal" or the family's name), in both modes, and a tap opens the
/// "Which book?" sheet ([showBookSheet]) to switch without leaving the screen.
///
/// Only members of a family see it (like the dashboard's BookSwitch); for
/// everyone else it takes no space.
class BookChip extends StatelessWidget {
  const BookChip({super.key, required this.routeName, this.maxWidth});

  static const Key chipKey = ValueKey('book-chip');

  /// Never wider than this share of the screen.
  static const double maxScreenShare = 0.4;

  /// With less room than this the chip drops the name and keeps its icon and
  /// ▾ (the sheet and the screen-reader label still name the book).
  static const double compactBelow = 80;

  /// With less room than this (but enough for the name) the ▾ goes first; a
  /// read-only family's lock always stays.
  static const double caretBelow = 120;

  /// The space the chip keeps after itself, outside [maxWidth].
  static const double outerPadding = 4;

  /// The named route of the screen showing the chip: after a switch the same
  /// screen is opened again, in the other book.
  final String routeName;

  /// The room the bar can give the chip; null: [maxScreenShare] of the screen.
  final double? maxWidth;

  /// Whether the chip shows at all (only for members of a family). Call it
  /// from `build` (it listens).
  static bool shows(BuildContext context) {
    final family = Provider.of<FamilyProvider?>(context);
    final books = Provider.of<BookModeProvider?>(context);
    return family != null && books != null && family.inFamily;
  }

  @override
  Widget build(BuildContext context) {
    if (!shows(context)) return const SizedBox.shrink();
    final family = Provider.of<FamilyProvider>(context);
    final books = Provider.of<BookModeProvider>(context);
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final name = books.isFamily ? (family.family?.name ?? '') : l.bookPersonal;
    final readOnly = isFamilyReadOnly(context);
    final width = min(maxWidth ?? double.infinity, MediaQuery.sizeOf(context).width * maxScreenShare);
    final compact = width < compactBelow;
    final trailing = readOnly
        ? Icons.lock_rounded
        : (compact || width >= caretBelow ? Icons.expand_more_rounded : null);
    void open() => showBookSheet(context, routeName: routeName);

    return Padding(
      padding: const EdgeInsets.only(right: outerPadding),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: Semantics(
            button: true,
            excludeSemantics: true,
            label: l.bookChipLabel(name),
            onTap: open,
            child: Material(
              key: chipKey,
              color: AppTheme.trackFor(context),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: open,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        books.isFamily ? Icons.family_restroom_rounded : Icons.person_rounded,
                        size: 16,
                        color: AppTheme.accentFor(context),
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
                          ),
                        ),
                      ],
                      if (trailing != null) ...[
                        const SizedBox(width: 2),
                        Icon(trailing, size: readOnly ? 14 : 18, color: scheme.onSurfaceVariant),
                      ],
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

/// A book screen's top-bar title with the [BookChip] at its end, next to the
/// screen's own actions. The title keeps room to be read (at least
/// [AppBarTitle.minWidth], and 40% of the slot); the chip gets what is
/// left, up to [BookChip.maxScreenShare] of the screen, and drops the name
/// when that is too little. With no family it is just the title.
class BookAppBarTitle extends StatelessWidget {
  const BookAppBarTitle(this.title, {super.key, required this.routeName});

  final String title;
  final String routeName;

  /// The chip's share of a title slot [available] wide, after [lead] (what
  /// sits before the title text in the slot) and the gap.
  static double chipRoom(double available, {double lead = 0}) {
    final forTitle = available - lead - _gap - BookChip.outerPadding;
    return max(0, forTitle - max(AppBarTitle.minWidth, forTitle * 0.4));
  }

  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    if (!BookChip.shows(context)) return AppBarTitle(title);
    return LayoutBuilder(builder: (context, constraints) {
      final chip = BookChip(routeName: routeName, maxWidth: chipRoom(constraints.maxWidth));
      return Row(
        children: [
          Expanded(child: AppBarTitle(title)),
          const SizedBox(width: _gap),
          chip,
        ],
      );
    });
  }
}

/// The navigators with a "Which book?" sheet open (or opening): a second
/// [showBookSheet] on the same navigator, e.g. two taps on the chip in one
/// frame, opens nothing.
final Expando<bool> _sheetOpenOn = Expando<bool>('book sheet open');

/// "Which book?": Personal and the family, a tick on the open one. Picking the
/// other book switches the whole app (which closes the screens above Home)
/// and opens [routeName] again in that book; picking the open one just closes
/// the sheet. One sheet at a time; it follows the family while open and
/// closes itself when the person is no longer in one (removed, left, deleted).
Future<void> showBookSheet(BuildContext context, {required String routeName}) {
  final navigator = Navigator.of(context);
  if (_sheetOpenOn[navigator] == true) return Future<void>.value();
  _sheetOpenOn[navigator] = true;
  final books = Provider.of<BookModeProvider>(context, listen: false);
  final family = Provider.of<FamilyProvider>(context, listen: false);
  final l = AppLocalizations.of(context);
  var closing = false;

  final shown = showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      void close() {
        if (closing) return; // a second tap, or the family going, while the sheet closes
        closing = true;
        Navigator.pop(sheetContext);
      }

      void pick(bool toFamily) {
        if (closing) return;
        close();
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

      return ListenableBuilder(
        listenable: Listenable.merge([family, books]),
        builder: (sheetContext, _) {
          if (!family.inFamily) {
            // No family to pick any more: close (after this frame, not while building).
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (sheetContext.mounted) close();
            });
          }
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(l.bookSheetTitle, style: Theme.of(sheetContext).textTheme.titleMedium),
                ),
                row(const ValueKey('book-sheet-personal'), Icons.person_rounded, l.bookPersonal, !books.isFamily,
                    false),
                if (family.inFamily)
                  row(const ValueKey('book-sheet-family'), Icons.family_restroom_rounded, family.family?.name ?? '',
                      books.isFamily, true),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );
    },
  );
  return shown.whenComplete(() => _sheetOpenOn[navigator] = null);
}
