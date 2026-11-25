import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/screens/family/family_invitations_screen.dart';
import 'package:frontend/screens/family/family_invite_screen.dart';
import 'package:frontend/screens/family/family_member_sheet.dart';
import 'package:frontend/screens/family/family_ui.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/date_format.dart';
import 'package:frontend/widgets/app_bar_title.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:frontend/widgets/app_list_row.dart';
import 'package:frontend/widgets/paused_feature.dart';
import 'package:provider/provider.dart';

/// The family (`/family`, from Settings): create one, or see and manage the
/// one you're in. What each person sees follows their role (see
/// [FamilyMemberSheet] for the member rules):
/// - **not in a family:** "Create a family" (Plus or Pro; Free users get the
///   same form with Create disabled and an Upgrade button) and the
///   invitations received;
/// - **in a family:** the members (account members, then name-only ones,
///   then the former members, collapsed), the pending invitations (admins),
///   and the actions: rename and invite (admins), add a name (admins), hand
///   over ownership and delete (the owner), leave (everyone but the owner).
///
/// No mascot: this is a form, not an empty list.
class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  static const Key nameFieldKey = ValueKey('family-name-field');
  static const Key createKey = ValueKey('family-create');
  static const Key upgradeKey = ValueKey('family-upgrade');
  static const Key invitationsKey = ValueKey('family-invitations');
  static const Key renameKey = ValueKey('family-rename');
  static const Key renameFieldKey = ValueKey('family-rename-field');
  static const Key renameSaveKey = ValueKey('family-rename-save');
  static const Key inviteKey = ValueKey('family-invite');
  static const Key addNameKey = ValueKey('family-add-name');
  static const Key addNameFieldKey = ValueKey('family-add-name-field');
  static const Key addNameSaveKey = ValueKey('family-add-name-save');
  static const Key handOverKey = ValueKey('family-hand-over');
  static const Key handOverConfirmKey = ValueKey('family-hand-over-confirm');
  static const Key leaveKey = ValueKey('family-leave');
  static const Key leaveConfirmKey = ValueKey('family-leave-confirm');
  static const Key deleteKey = ValueKey('family-delete');
  static const Key deleteFieldKey = ValueKey('family-delete-field');
  static const Key deleteConfirmKey = ValueKey('family-delete-confirm');
  static const Key formerKey = ValueKey('family-former');

  static Key memberKey(String id) => ValueKey('family-member-$id');
  static Key cancelInviteKey(String id) => ValueKey('family-cancel-invite-$id');
  static Key handOverToKey(String id) => ValueKey('family-hand-over-$id');

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  final TextEditingController _name = TextEditingController();
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final family = Provider.of<FamilyProvider>(context, listen: false);
      if (!family.loaded && !family.isLoading) unawaited(family.refresh());
      unawaited(family.loadMyInvites());
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final family = Provider.of<FamilyProvider>(context, listen: false);
    await Future.wait([family.refresh(), family.loadMyInvites()]);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final family = Provider.of<FamilyProvider>(context);

    Widget body;
    if (!family.loaded) {
      body = family.error == null || family.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _LoadError(message: family.error!, onRetry: _reload);
    } else {
      body = RefreshIndicator(
        onRefresh: _reload,
        child: family.inFamily ? _inFamily(context, l, family) : _noFamily(context, l, family),
      );
    }

    return Scaffold(
      appBar: AppBar(title: AppBarTitle(l.familyTitle)),
      body: body,
    );
  }

  // ---- not in a family ----

  Widget _noFamily(BuildContext context, AppLocalizations l, FamilyProvider family) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final paid = Provider.of<AuthProvider>(context).isPaid;
    final canCreate = paid && !_creating && _name.text.trim().isNotEmpty;
    final received = family.myInvites.length;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _IconCircle(icon: Icons.family_restroom_rounded),
                    const SizedBox(width: 14),
                    Expanded(child: Text(l.familyCreateTitle, style: textTheme.titleMedium)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  l.familyCreateIntro,
                  style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: FamilyScreen.nameFieldKey,
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [LengthLimitingTextInputFormatter(familyNameMaxLength)],
                  decoration: InputDecoration(labelText: l.familyNameLabel),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                PausedLook(
                  featureKey: 'family_new',
                  child: FilledButton(
                    key: FamilyScreen.createKey,
                    onPressed: canCreate ? _create : null,
                    child: _creating
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(l.familyCreateButton),
                  ),
                ),
                if (!paid) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.lock_rounded, size: 20, color: scheme.tertiary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                l.familyCreateNeedsPlan,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.45,
                                  color: scheme.onTertiaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          key: FamilyScreen.upgradeKey,
                          onPressed: () => Navigator.of(context).pushNamed('/subscription'),
                          child: Text(l.upgrade),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        FamilySectionHeader(l.familyInvitationsTitle),
        Card(
          child: AppListRow(
            key: FamilyScreen.invitationsKey,
            icon: Icons.mail_rounded,
            title: l.familyInvitationsTitle,
            subtitle: received > 0 ? l.familyInvitationsPending(received) : l.familyInvitationsNone,
            trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.hintFor(context)),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const FamilyInvitationsScreen())),
          ),
        ),
      ],
    );
  }

  Future<void> _create() async {
    if (showIfPaused(context, 'family_new')) return;
    final family = Provider.of<FamilyProvider>(context, listen: false);
    setState(() => _creating = true);
    final error = await family.createFamily(_name.text.trim());
    if (!mounted) return;
    setState(() => _creating = false);
    if (error == null) {
      _name.clear();
      return;
    }
    showFamilyError(context, error);
  }

  // ---- in a family ----

  Widget _inFamily(BuildContext context, AppLocalizations l, FamilyProvider family) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final me = family.me;
    final members = family.members;
    final accounts = members.where((m) => m.isAccount && m.isActive).toList();
    final names = members.where((m) => m.isPlaceholder && m.isActive).toList();
    final former = members.where((m) => m.isFormer).toList();
    final admin = family.isAdmin;
    final owner = family.isOwner;
    final writable = !family.readOnly;
    final maxMembers = family.maxMembers;

    Widget memberRow(FamilyMember m) => FamilyMemberRow(
          key: FamilyScreen.memberKey(m.id),
          member: m,
          onTap: FamilyMemberSheet.hasActions(family, m) ? () => FamilyMemberSheet.show(context, m) : null,
        );

    List<Widget> divided(Iterable<Widget> rows) {
      final out = <Widget>[];
      for (final row in rows) {
        if (out.isNotEmpty) out.add(const Divider());
        out.add(row);
      }
      return out;
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // The family: its name, my role, how many account members.
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 8, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconCircle(icon: Icons.family_restroom_rounded),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(family.family?.name ?? '', style: textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          FamilyChip(familyRoleLabel(l, me?.role ?? family.myRole), strong: true),
                          if (maxMembers != null) FamilyChip(l.familyMembersCount(accounts.length, maxMembers)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (admin)
                  IconButton(
                    key: FamilyScreen.renameKey,
                    tooltip: l.familyRename,
                    icon: const Icon(Icons.edit_rounded),
                    onPressed: () => _rename(context, l, family),
                  )
                else
                  const SizedBox(width: 10),
              ],
            ),
          ),
        ),
        if (family.readOnly) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(16)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_rounded, size: 20, color: scheme.tertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.familyReadOnlyBanner,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),

        FamilySectionHeader(l.familyMembersSection),
        Card(child: Column(children: divided(accounts.map(memberRow)))),

        if (names.isNotEmpty || (admin && writable)) ...[
          const SizedBox(height: 24),
          FamilySectionHeader(l.familyPlaceholdersSection),
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
            child: Text(
              l.familyPlaceholdersHint,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.45),
            ),
          ),
          Card(
            child: Column(
              children: divided([
                ...names.map(memberRow),
                if (admin && writable)
                  AppListRow(
                    key: FamilyScreen.addNameKey,
                    icon: Icons.person_add_alt_rounded,
                    title: l.familyAddName,
                    onTap: () => _addName(context, l, family),
                  ),
              ]),
            ),
          ),
        ],

        if (admin && family.invites.isNotEmpty) ...[
          const SizedBox(height: 24),
          FamilySectionHeader(l.familyPendingInvitesSection),
          Card(
            child: Column(
              children: divided(family.invites.map((i) => _InviteRow(
                    invite: i,
                    linkedName: _nameOf(members, i.linkMemberId),
                    onCancel: () => _cancelInvite(context, family, i),
                  ))),
            ),
          ),
        ],

        if (former.isNotEmpty) ...[
          const SizedBox(height: 24),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Theme(
              // No lines above and below the expanded tile.
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: FamilyScreen.formerKey,
                title: Text(
                  l.familyFormerSection(former.length),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
                ),
                childrenPadding: EdgeInsets.zero,
                children: divided(former.map(memberRow)),
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),
        FamilySectionHeader(l.familyActionsSection),
        Card(
          child: Column(
            children: divided([
              if (admin && writable)
                PausedLook(
                  featureKey: 'family_new',
                  child: AppListRow(
                    key: FamilyScreen.inviteKey,
                    icon: Icons.person_add_rounded,
                    title: l.familyInviteAction,
                    trailing: Icon(Icons.chevron_right_rounded, color: AppTheme.hintFor(context)),
                    onTap: () {
                      if (showIfPaused(context, 'family_new')) return;
                      Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => const FamilyInviteScreen()));
                    },
                  ),
                ),
              if (owner)
                AppListRow(
                  key: FamilyScreen.handOverKey,
                  icon: Icons.key_rounded,
                  title: l.familyHandOver,
                  onTap: () => _handOver(context, l, family),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppListRow(
                    key: FamilyScreen.leaveKey,
                    icon: Icons.logout_rounded,
                    iconColor: owner ? scheme.onSurfaceVariant : scheme.error,
                    iconBg: owner ? scheme.surfaceContainerHighest : scheme.errorContainer,
                    title: l.familyLeave,
                    onTap: owner ? null : () => _leave(context, l, family),
                  ),
                  if (owner)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(70, 0, 16, 14),
                      child: Text(
                        l.familyOwnerLeaveHint,
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.45),
                      ),
                    ),
                ],
              ),
              if (owner)
                AppListRow(
                  key: FamilyScreen.deleteKey,
                  icon: Icons.delete_forever_rounded,
                  iconColor: scheme.error,
                  iconBg: scheme.errorContainer,
                  title: l.familyDelete,
                  onTap: () => _delete(context, l, family),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  static String? _nameOf(List<FamilyMember> members, String? id) {
    if (id == null) return null;
    for (final m in members) {
      if (m.id == id) return m.displayName;
    }
    return null;
  }

  void _rename(BuildContext context, AppLocalizations l, FamilyProvider family) {
    showAppBottomSheet<void>(
      context: context,
      builder: (_) => FamilyNameSheet(
        title: l.familyRename,
        label: l.familyNameLabel,
        initial: family.family?.name ?? '',
        fieldKey: FamilyScreen.renameFieldKey,
        saveKey: FamilyScreen.renameSaveKey,
        onSave: family.renameFamily,
      ),
    );
  }

  void _addName(BuildContext context, AppLocalizations l, FamilyProvider family) {
    showAppBottomSheet<void>(
      context: context,
      builder: (_) => FamilyNameSheet(
        title: l.familyAddName,
        label: l.familyMemberNameLabel,
        hint: l.familyAddNameHint,
        fieldKey: FamilyScreen.addNameFieldKey,
        saveKey: FamilyScreen.addNameSaveKey,
        onSave: family.addPlaceholder,
      ),
    );
  }

  Future<void> _cancelInvite(BuildContext context, FamilyProvider family, FamilyInvite invite) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final error = await family.cancelInvite(invite.id);
    if (!context.mounted) return;
    if (error == null) {
      messenger.showSnackBar(SnackBar(content: Text(l.familyInviteCancelled)));
    } else {
      showFamilyError(context, error);
    }
  }

  void _leave(BuildContext context, AppLocalizations l, FamilyProvider family) {
    final messenger = ScaffoldMessenger.of(context);
    showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) => FamilyConfirmSheet(
        icon: Icons.logout_rounded,
        title: l.familyLeave,
        message: l.familyLeaveConfirm,
        actionLabel: l.familyLeave,
        actionKey: FamilyScreen.leaveConfirmKey,
        onConfirm: () async {
          Navigator.pop(sheetContext);
          final error = await family.leave();
          if (error == null) {
            messenger.showSnackBar(SnackBar(content: Text(l.familyLeft)));
          } else if (context.mounted) {
            showFamilyError(context, error);
          }
        },
      ),
    );
  }

  void _handOver(BuildContext context, AppLocalizations l, FamilyProvider family) {
    final messenger = ScaffoldMessenger.of(context);
    showAppBottomSheet<void>(
      context: context,
      builder: (_) => _HandOverSheet(
        onDone: (name) => messenger.showSnackBar(SnackBar(content: Text(l.familyHandOverDone(name)))),
      ),
    );
  }

  void _delete(BuildContext context, AppLocalizations l, FamilyProvider family) {
    final messenger = ScaffoldMessenger.of(context);
    showAppBottomSheet<void>(
      context: context,
      builder: (_) => _DeleteSheet(
        familyName: family.family?.name ?? '',
        onDeleted: () => messenger.showSnackBar(SnackBar(content: Text(l.familyDeleted))),
      ),
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
      child: Icon(icon, size: 24, color: scheme.primary),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(l.tryAgain)),
          ],
        ),
      ),
    );
  }
}

/// A pending invitation (admins): the address, who it joins as, when it
/// expires, and a Cancel button.
class _InviteRow extends StatelessWidget {
  const _InviteRow({required this.invite, required this.linkedName, required this.onCancel});

  final FamilyInvite invite;
  final String? linkedName;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final expires = invite.expiresAt;
    final details = [
      if (linkedName != null) l.familyInviteAs(linkedName!),
      if (expires != null) l.familyInviteExpires(AppDates.full(context, expires)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
            child: Icon(Icons.schedule_send_rounded, size: 22, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invite.email ?? '',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
                ),
                for (final line in details) ...[
                  const SizedBox(height: 2),
                  Text(line, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.4)),
                ],
              ],
            ),
          ),
          IconButton(
            key: FamilyScreen.cancelInviteKey(invite.id),
            tooltip: l.familyCancelInvite,
            icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

/// The owner picks the account member who takes over, then confirms.
class _HandOverSheet extends StatefulWidget {
  const _HandOverSheet({required this.onDone});

  final void Function(String name) onDone;

  @override
  State<_HandOverSheet> createState() => _HandOverSheetState();
}

class _HandOverSheetState extends State<_HandOverSheet> {
  FamilyMember? _to;
  bool _busy = false;
  String? _error;

  Future<void> _confirm(FamilyMember to) async {
    final family = Provider.of<FamilyProvider>(context, listen: false);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await family.transferOwnership(to.id);
    if (!mounted) return;
    if (error == null || family.lastErrorReported) {
      navigator.pop();
      if (error == null) widget.onDone(to.displayName);
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
    final candidates = family.members.where((m) => m.isAccount && m.isActive && !m.isMe && !m.isOwner).toList();
    final to = _to;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.familyHandOver, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (candidates.isEmpty)
          Text(l.familyHandOverNone, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.5))
        else if (to == null)
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final m in candidates)
                    FamilyMemberRow(
                      key: FamilyScreen.handOverToKey(m.id),
                      member: m,
                      onTap: () => setState(() => _to = m),
                    ),
                ],
              ),
            ),
          )
        else ...[
          Text(
            l.familyHandOverConfirm(to.displayName),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: FamilyScreen.handOverConfirmKey,
            onPressed: _busy ? null : () => _confirm(to),
            child: Text(l.familyHandOver, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _to = null),
            child: Text(l.dialogCancel),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(fontSize: 13, color: scheme.error, height: 1.4)),
        ],
      ],
    );
  }
}

/// Deleting the family: only with its name typed exactly.
class _DeleteSheet extends StatefulWidget {
  const _DeleteSheet({required this.familyName, required this.onDeleted});

  final String familyName;
  final VoidCallback onDeleted;

  @override
  State<_DeleteSheet> createState() => _DeleteSheetState();
}

class _DeleteSheetState extends State<_DeleteSheet> {
  final TextEditingController _typed = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _matches => _typed.text.trim() == widget.familyName.trim() && widget.familyName.trim().isNotEmpty;

  Future<void> _delete() async {
    final family = Provider.of<FamilyProvider>(context, listen: false);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await family.deleteFamily(_typed.text.trim());
    if (!mounted) {
      if (error == null) widget.onDeleted();
      return;
    }
    if (error == null || family.lastErrorReported) {
      navigator.pop();
      if (error == null) widget.onDeleted();
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
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: scheme.errorContainer, shape: BoxShape.circle),
            child: Icon(Icons.delete_forever_rounded, color: scheme.error, size: 26),
          ),
        ),
        const SizedBox(height: 14),
        Text(l.familyDelete, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          l.familyDeleteWarning,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant, height: 1.5),
        ),
        const SizedBox(height: 16),
        Text(
          l.familyDeleteTypeName(widget.familyName),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface, height: 1.5),
        ),
        const SizedBox(height: 8),
        TextField(
          key: FamilyScreen.deleteFieldKey,
          controller: _typed,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(hintText: widget.familyName),
          onChanged: (_) => setState(() => _error = null),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(fontSize: 13, color: scheme.error, height: 1.4)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          key: FamilyScreen.deleteConfirmKey,
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          onPressed: _matches && !_busy ? _delete : null,
          child: Text(l.familyDelete, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.dialogCancel),
        ),
      ],
    );
  }
}
