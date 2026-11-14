import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/screens/family/family_ui.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:provider/provider.dart';

/// What the signed-in person may do to one member, from the family's rules
/// (the server checks them too):
/// - admins rename placeholders and former members (an active account
///   member's name is their own), and remove members and placeholders, but
///   not admins;
/// - only the owner makes or unmakes admins, and removes an admin;
/// - nobody acts on the owner or on themselves here (Leave is on the screen).
class FamilyMemberSheet extends StatefulWidget {
  const FamilyMemberSheet({super.key, required this.member});

  final FamilyMember member;

  static const Key renameKey = ValueKey('member-rename');
  static const Key makeAdminKey = ValueKey('member-make-admin');
  static const Key removeAdminKey = ValueKey('member-remove-admin');
  static const Key removeKey = ValueKey('member-remove');
  static const Key removeConfirmKey = ValueKey('member-remove-confirm');
  static const Key nameFieldKey = ValueKey('member-name-field');
  static const Key saveKey = ValueKey('member-save');

  static bool canRename(FamilyProvider family, FamilyMember m) =>
      family.isAdmin && !m.isMe && (m.isPlaceholder || m.isFormer);

  static bool canChangeRole(FamilyProvider family, FamilyMember m) =>
      family.isOwner && m.isAccount && m.isActive && !m.isOwner && !m.isMe;

  static bool canRemove(FamilyProvider family, FamilyMember m) {
    if (!family.isAdmin || !m.isActive || m.isMe || m.isOwner) return false;
    if (m.isAccount && m.isAdmin && !family.isOwner) return false;
    return true;
  }

  /// Whether the sheet would offer anything for [m].
  static bool hasActions(FamilyProvider family, FamilyMember m) =>
      canRename(family, m) || canChangeRole(family, m) || canRemove(family, m);

  /// Opens the sheet for [member].
  static Future<void> show(BuildContext context, FamilyMember member) =>
      showAppBottomSheet<void>(context: context, builder: (_) => FamilyMemberSheet(member: member));

  @override
  State<FamilyMemberSheet> createState() => _FamilyMemberSheetState();
}

enum _Step { actions, rename, remove }

class _FamilyMemberSheetState extends State<FamilyMemberSheet> {
  _Step _step = _Step.actions;
  bool _busy = false;
  String? _error;
  late final TextEditingController _name = TextEditingController(text: widget.member.displayName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Runs a change; closes the sheet when it worked (or the app already
  /// said why it didn't), otherwise shows the message here.
  Future<void> _run(Future<String?> Function(FamilyProvider family) change) async {
    final family = Provider.of<FamilyProvider>(context, listen: false);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await change(family);
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
    final family = Provider.of<FamilyProvider>(context);
    final m = widget.member;

    final body = switch (_step) {
      _Step.actions => _actions(context, l, family, m),
      _Step.rename => _rename(l),
      _Step.remove => _remove(context, l, m),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(m.displayName, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: familyMemberChips(l, m)),
        const SizedBox(height: 20),
        ...body,
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(fontSize: 13, color: scheme.error, height: 1.4)),
        ],
      ],
    );
  }

  List<Widget> _actions(BuildContext context, AppLocalizations l, FamilyProvider family, FamilyMember m) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = !_busy;
    return [
      if (FamilyMemberSheet.canRename(family, m))
        _ActionButton(
          key: FamilyMemberSheet.renameKey,
          icon: Icons.edit_rounded,
          label: l.familyRenameMember,
          onPressed: enabled ? () => setState(() => _step = _Step.rename) : null,
        ),
      if (FamilyMemberSheet.canChangeRole(family, m))
        m.role == FamilyMember.roleAdmin
            ? _ActionButton(
                key: FamilyMemberSheet.removeAdminKey,
                icon: Icons.remove_moderator_rounded,
                label: l.familyRemoveAdmin,
                onPressed: enabled ? () => _run((f) => f.updateMember(m.id, role: FamilyMember.roleMember)) : null,
              )
            : _ActionButton(
                key: FamilyMemberSheet.makeAdminKey,
                icon: Icons.admin_panel_settings_rounded,
                label: l.familyMakeAdmin,
                onPressed: enabled ? () => _run((f) => f.updateMember(m.id, role: FamilyMember.roleAdmin)) : null,
              ),
      if (FamilyMemberSheet.canRemove(family, m))
        _ActionButton(
          key: FamilyMemberSheet.removeKey,
          icon: Icons.person_remove_rounded,
          label: l.familyRemoveMember,
          color: scheme.error,
          onPressed: enabled ? () => setState(() => _step = _Step.remove) : null,
        ),
    ];
  }

  List<Widget> _rename(AppLocalizations l) {
    bool canSave() => !_busy && _name.text.trim().isNotEmpty && _name.text.trim() != widget.member.displayName;
    return [
      TextField(
        key: FamilyMemberSheet.nameFieldKey,
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        inputFormatters: [LengthLimitingTextInputFormatter(familyNameMaxLength)],
        decoration: InputDecoration(labelText: l.familyMemberNameLabel),
        onChanged: (_) => setState(() => _error = null),
      ),
      const SizedBox(height: 20),
      FilledButton(
        key: FamilyMemberSheet.saveKey,
        onPressed: canSave() ? () => _run((f) => f.updateMember(widget.member.id, displayName: _name.text.trim())) : null,
        child: Text(l.save),
      ),
    ];
  }

  List<Widget> _remove(BuildContext context, AppLocalizations l, FamilyMember m) {
    final scheme = Theme.of(context).colorScheme;
    return [
      Text(l.familyRemoveConfirmTitle(m.displayName), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(
        l.familyRemoveConfirm,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant, height: 1.5),
      ),
      const SizedBox(height: 20),
      FilledButton(
        key: FamilyMemberSheet.removeConfirmKey,
        style: FilledButton.styleFrom(backgroundColor: scheme.error),
        onPressed: _busy ? null : () => _run((f) => f.removeMember(m.id)),
        child: Text(l.familyRemoveMember, textAlign: TextAlign.center),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _busy ? null : () => setState(() => _step = _Step.actions),
        child: Text(l.dialogCancel),
      ),
    ];
  }
}

/// A full-width outlined action whose label wraps.
class _ActionButton extends StatelessWidget {
  const _ActionButton({super.key, required this.icon, required this.label, required this.onPressed, this.color});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: color),
        label: Text(label, style: color == null ? null : TextStyle(color: color)),
        style: OutlinedButton.styleFrom(
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          side: color == null ? null : BorderSide(color: color!),
        ),
      ),
    );
  }
}
