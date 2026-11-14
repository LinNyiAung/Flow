import 'package:flutter/material.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/family_entries.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:provider/provider.dart';

/// Who a family entry was for: "Whole family" (nothing selected) or one or
/// more of [members] (placeholders included). Selecting "Whole family" clears
/// the people; selecting a person leaves "Whole family". [onChanged] gets the
/// selected ids in [members]' order.
class ForWhomPicker extends StatelessWidget {
  const ForWhomPicker({
    super.key,
    required this.members,
    required this.selected,
    required this.onChanged,
  });

  /// The "For whom" row on New entry / Edit transaction.
  static const Key rowKey = ValueKey('for-whom-row');
  static const Key wholeFamilyKey = ValueKey('for-whom-whole-family');
  static const Key doneKey = ValueKey('for-whom-done');
  static Key memberKey(String memberId) => ValueKey('for-whom-$memberId');

  final List<FamilyMember> members;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  void _toggle(String id) {
    final next = selected.contains(id) ? selected.where((s) => s != id).toSet() : {...selected, id};
    onChanged([for (final m in members) if (next.contains(m.id)) m.id]);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Option(
          key: wholeFamilyKey,
          icon: Icons.groups_rounded,
          label: l.wholeFamily,
          selected: selected.isEmpty,
          onTap: () => onChanged(const []),
        ),
        for (final m in members) ...[
          const Divider(height: 1, indent: 52),
          _Option(
            key: memberKey(m.id),
            icon: m.isPlaceholder ? Icons.person_outline_rounded : Icons.person_rounded,
            label: m.isFormer ? l.familyFormerName(m.displayName) : m.displayName,
            selected: selected.contains(m.id),
            onTap: () => _toggle(m.id),
          ),
        ],
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({super.key, required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      checked: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              ExcludeSemantics(child: Icon(icon, color: selected ? AppTheme.accentFor(context) : scheme.onSurfaceVariant)),
              const SizedBox(width: 14),
              // Long names wrap; never cut short.
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),
              ExcludeSemantics(
                child: Icon(
                  selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? scheme.primary : scheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "For whom" row of a form's details card: the label and who it is
/// for now ("Whole family", or the names). Tapping it opens the picker.
class ForWhomRow extends StatelessWidget {
  const ForWhomRow({super.key = ForWhomPicker.rowKey, required this.selected, required this.onChanged});

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final family = Provider.of<FamilyProvider?>(context);
    return InkWell(
      onTap: () async {
        final picked = await showForWhomSheet(context, selected: selected);
        if (picked != null) onChanged(picked);
      },
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.groups_rounded, color: scheme.onSurface),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.forWhomLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    forWhomSummary(l, selected, family),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.hintFor(context)),
          ],
        ),
      ),
    );
  }
}

/// The picker in a sheet, starting from [selected]: the family's active
/// members, plus any former member the entry is already for (so its tags
/// show). Null when dismissed; otherwise the new selection.
Future<List<String>?> showForWhomSheet(BuildContext context, {required List<String> selected}) {
  final family = Provider.of<FamilyProvider?>(context, listen: false);
  final members = [
    for (final m in family?.members ?? const <FamilyMember>[])
      if (m.isActive || selected.contains(m.id)) m,
  ];
  var current = List<String>.of(selected);
  return showAppBottomSheet<List<String>>(
    context: context,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final l = AppLocalizations.of(context);
        final scheme = Theme.of(context).colorScheme;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.forWhomTitle, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(l.forWhomHint, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4)),
              const SizedBox(height: 14),
              Flexible(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    child: ForWhomPicker(
                      members: members,
                      selected: current,
                      onChanged: (next) => setSheetState(() => current = next),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: ForWhomPicker.doneKey,
                onPressed: () => Navigator.pop(sheetContext, current),
                child: Text(l.doneLabel),
              ),
            ],
          ),
        );
      },
    ),
  );
}
