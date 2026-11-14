import 'package:flutter/material.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/providers/transaction_provider.dart';
import 'package:frontend/screens/family/family_ui.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/date_format.dart';
import 'package:frontend/utils/family_entries.dart';
import 'package:frontend/utils/money.dart';
import 'package:frontend/widgets/app_bar_title.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:provider/provider.dart';

/// One leg of a transfer between a personal wallet and the family wallet,
/// read-only: transfers can't be edited. Its maker (the person whose wallet
/// it moved, see [madeTransfer]) can undo it, which removes both legs; the
/// screen then closes with [undoneResult].
class TransferDetailView extends StatefulWidget {
  const TransferDetailView({super.key, required this.transaction});

  static const Key undoKey = ValueKey('transfer-undo');
  static const Key undoConfirmKey = ValueKey('transfer-undo-confirm');

  /// What the screen returns once the transfer was undone.
  static const String undoneResult = 'undone';

  final Transaction transaction;

  @override
  State<TransferDetailView> createState() => _TransferDetailViewState();
}

class _TransferDetailViewState extends State<TransferDetailView> {
  bool _busy = false;
  String? _error;

  Future<void> _confirmUndo() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showAppBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => FamilyConfirmSheet(
        icon: Icons.undo_rounded,
        title: l.undoTransfer,
        message: l.undoTransferConfirm,
        actionLabel: l.undoTransfer,
        actionKey: TransferDetailView.undoConfirmKey,
        onConfirm: () => Navigator.pop(sheetContext, true),
      ),
    );
    if (confirmed != true || !mounted) return;
    await _undo();
  }

  Future<void> _undo() async {
    final l = AppLocalizations.of(context);
    final transactions = Provider.of<TransactionProvider>(context, listen: false);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await transactions.undoTransfer(widget.transaction.transferId!, context: context);
      if (!mounted) return;
      Navigator.pop(context, TransferDetailView.undoneResult);
    } catch (e) {
      if (!mounted) return;
      // A Family-mode `no_family`: the app goes back to Personal and says why.
      if (e is ApiException && e.reported) return;
      final message = transferErrorMessage(l, e, undo: true);
      setState(() {
        _busy = false;
        _error = message;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = widget.transaction;
    final familyBook = showsFamilyBook(context);
    final family = Provider.of<FamilyProvider?>(context);
    final mine = madeTransfer(t, familyBook: familyBook, family: family);
    // A read-only family refuses an undo from either side.
    final readOnly = family?.readOnly ?? false;
    final isInflow = t.type == TransactionType.inflow;
    final addedBy = t.addedBy;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
        titleSpacing: 0,
        title: AppBarTitle(l.transferTitle, style: const TextStyle(fontSize: 18)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _card(
                context,
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                  child: Column(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
                        child: Icon(Icons.swap_horiz_rounded, color: scheme.onSecondaryContainer, size: 28),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        transferLabel(l, t, familyBook: familyBook),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          formatMoney(isInflow ? t.amount : -t.amount, t.currency, showPlus: true),
                          maxLines: 1,
                          style: AppTheme.money(34,
                              weight: FontWeight.w800, color: isInflow ? scheme.primary : scheme.onSurface),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppDates.full(context, t.date),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _card(
                context,
                Column(
                  children: [
                    if (addedBy != null) ...[
                      _line(context, Icons.person_rounded, l.addedByName(memberRefName(l, addedBy, family))),
                      const Divider(height: 1, indent: 52),
                    ],
                    if ((t.description ?? '').trim().isNotEmpty) ...[
                      _line(context, Icons.notes_rounded, t.description!.trim()),
                      const Divider(height: 1, indent: 52),
                    ],
                    _line(context, Icons.info_outline_rounded, l.transferNotIncome, muted: true),
                  ],
                ),
              ),
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: scheme.error),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer))),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              if (mine && !readOnly)
                OutlinedButton.icon(
                  key: TransferDetailView.undoKey,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    side: BorderSide(color: scheme.error),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  onPressed: _busy ? null : _confirmUndo,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.undo_rounded),
                  label: Text(l.undoTransfer, textAlign: TextAlign.center),
                )
              else
                _note(context, mine ? l.familyReadOnlyBanner : l.transferOnlyMakerUndo),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, Widget child) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Color(0x14101815), blurRadius: 3, offset: Offset(0, 1))],
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );

  /// An icon and a text that wraps (never cut short).
  Widget _line(BuildContext context, IconData icon, String text, {bool muted = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: muted ? scheme.onSurfaceVariant : scheme.onSurface),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: muted ? 13 : 15,
                fontWeight: muted ? FontWeight.w500 : FontWeight.w600,
                height: 1.4,
                color: muted ? scheme.onSurfaceVariant : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.trackFor(context), borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, color: scheme.onSurfaceVariant, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
