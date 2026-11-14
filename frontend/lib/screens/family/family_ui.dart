import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:provider/provider.dart';

/// The longest family or member name the server takes.
const int familyNameMaxLength = 60;

/// Shows the message a family change returned ([error]; null: it worked),
/// unless the app has already said it (a Family-mode `no_family`, see
/// [FamilyProvider.lastErrorReported]).
void showFamilyError(BuildContext context, String? error) {
  if (error == null || !context.mounted) return;
  if (Provider.of<FamilyProvider>(context, listen: false).lastErrorReported) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
}

/// The localized name of a member's role.
String familyRoleLabel(AppLocalizations l, String? role) => switch (role) {
      FamilyMember.roleOwner => l.familyRoleOwner,
      FamilyMember.roleAdmin => l.familyRoleAdmin,
      _ => l.familyRoleMember,
    };

/// The small labels under a member's name: their role (or "Name only"),
/// "Former", and "You".
List<Widget> familyMemberChips(AppLocalizations l, FamilyMember member) => [
      if (member.isAccount)
        FamilyChip(familyRoleLabel(l, member.role), strong: member.isAdmin && member.isActive)
      else
        FamilyChip(l.familyNameOnly),
      if (member.isFormer) FamilyChip(l.familyFormer),
      if (member.isMe) FamilyChip(l.familyYou, strong: true),
    ];

/// A small rounded label (a role, "Name only", "Former", "You").
class FamilyChip extends StatelessWidget {
  const FamilyChip(this.label, {super.key, this.strong = false});

  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: strong ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: strong ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A section title above a card, as on the Settings screen.
class FamilySectionHeader extends StatelessWidget {
  const FamilySectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

/// A member's row: an icon, the name (it wraps; long names are never cut)
/// and the chips. Tappable only when [onTap] is given.
class FamilyMemberRow extends StatelessWidget {
  const FamilyMemberRow({super.key, required this.member, this.onTap});

  final FamilyMember member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final muted = member.isFormer;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: muted ? scheme.surfaceContainerHighest : scheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                member.isPlaceholder ? Icons.person_outline_rounded : Icons.person_rounded,
                size: 22,
                color: muted ? scheme.onSurfaceVariant : scheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.displayName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: muted ? scheme.onSurfaceVariant : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(spacing: 6, runSpacing: 4, children: familyMemberChips(l, member)),
                ],
              ),
            ),
            if (onTap != null) Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// The body of a sheet that asks for one name ([title]): a field and a Save
/// button. [onSave] gets the trimmed name and returns null when it worked
/// (the sheet closes) or the message to show under the field.
class FamilyNameSheet extends StatefulWidget {
  const FamilyNameSheet({
    super.key,
    required this.title,
    required this.label,
    required this.onSave,
    required this.fieldKey,
    required this.saveKey,
    this.initial = '',
    this.hint,
    this.saveLabel,
  });

  final String title;
  final String label;
  final String initial;
  final String? hint;
  final String? saveLabel;
  final Key fieldKey;
  final Key saveKey;
  final Future<String?> Function(String name) onSave;

  @override
  State<FamilyNameSheet> createState() => _FamilyNameSheetState();
}

class _FamilyNameSheetState extends State<FamilyNameSheet> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSave => !_busy && _controller.text.trim().isNotEmpty && _controller.text.trim() != widget.initial.trim();

  Future<void> _save() async {
    final family = Provider.of<FamilyProvider>(context, listen: false);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSave(_controller.text.trim());
    if (!mounted) return;
    if (error == null || family.lastErrorReported) {
      navigator.pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          key: widget.fieldKey,
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          inputFormatters: [LengthLimitingTextInputFormatter(familyNameMaxLength)],
          decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) {
            if (_canSave) _save();
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(fontSize: 13, color: scheme.error, height: 1.4)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          key: widget.saveKey,
          onPressed: _canSave ? _save : null,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.saveLabel ?? l.save),
        ),
      ],
    );
  }
}

/// A confirmation sheet in the app's destructive style (icon circle, title,
/// message, a full-width action, then Cancel), as Log out and Delete budget.
class FamilyConfirmSheet extends StatelessWidget {
  const FamilyConfirmSheet({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.actionKey,
    required this.onConfirm,
    this.destructive = true,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final Key actionKey;
  final VoidCallback onConfirm;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: destructive ? scheme.errorContainer : scheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: destructive ? scheme.error : scheme.primary, size: 26),
        ),
        const SizedBox(height: 14),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          message,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant, height: 1.5),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: actionKey,
            style: destructive ? FilledButton.styleFrom(backgroundColor: scheme.error) : null,
            onPressed: onConfirm,
            child: Text(actionLabel, textAlign: TextAlign.center),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.dialogCancel),
          ),
        ),
      ],
    );
  }
}
