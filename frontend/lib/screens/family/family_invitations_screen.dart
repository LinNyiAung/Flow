import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/screens/family/family_ui.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/utils/date_format.dart';
import 'package:frontend/widgets/app_bar_title.dart';
import 'package:provider/provider.dart';

/// The family invitations the signed-in person received, each with Join and
/// Decline. Someone already in a family is told to leave it first (one
/// family per person), and nothing is sent.
class FamilyInvitationsScreen extends StatefulWidget {
  const FamilyInvitationsScreen({super.key});

  static Key joinKey(String inviteId) => ValueKey('invitation-join-$inviteId');
  static Key declineKey(String inviteId) => ValueKey('invitation-decline-$inviteId');

  @override
  State<FamilyInvitationsScreen> createState() => _FamilyInvitationsScreenState();
}

class _FamilyInvitationsScreenState extends State<FamilyInvitationsScreen> {
  /// The invite being answered (its buttons show progress).
  String? _busy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final family = Provider.of<FamilyProvider>(context, listen: false);
      unawaited(family.loadMyInvites());
      if (!family.loaded && !family.isLoading) unawaited(family.refresh());
    });
  }

  Future<void> _join(FamilyInvite invite) async {
    final l = AppLocalizations.of(context);
    final family = Provider.of<FamilyProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    if (family.inFamily) {
      messenger.showSnackBar(SnackBar(content: Text(l.familyLeaveFirst)));
      return;
    }
    final navigator = Navigator.of(context);
    setState(() => _busy = invite.id);
    final error = await family.acceptInvite(invite.id);
    if (!mounted) return;
    setState(() => _busy = null);
    if (error != null) {
      showFamilyError(context, error);
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(l.familyJoined(invite.familyName ?? ''))));
    // Back to where the invitation was opened from (the family screen now
    // shows the family).
    if (navigator.canPop()) navigator.pop();
  }

  Future<void> _decline(FamilyInvite invite) async {
    final l = AppLocalizations.of(context);
    final family = Provider.of<FamilyProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = invite.id);
    final error = await family.declineInvite(invite.id);
    if (!mounted) return;
    setState(() => _busy = null);
    if (error != null) {
      showFamilyError(context, error);
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(l.familyDeclined)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final family = Provider.of<FamilyProvider>(context);
    final invites = family.myInvites;

    return Scaffold(
      appBar: AppBar(title: AppBarTitle(l.familyInvitationsTitle)),
      body: RefreshIndicator(
        onRefresh: family.loadMyInvites,
        child: invites.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(32),
                children: [
                  const SizedBox(height: 40),
                  Icon(Icons.mail_outline_rounded, size: 40, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text(
                    l.familyInvitationsNone,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant, height: 1.5),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: invites.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _InvitationCard(
                  invite: invites[i],
                  busy: _busy == invites[i].id,
                  enabled: _busy == null,
                  onJoin: () => _join(invites[i]),
                  onDecline: () => _decline(invites[i]),
                ),
              ),
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.invite,
    required this.busy,
    required this.enabled,
    required this.onJoin,
    required this.onDecline,
  });

  final FamilyInvite invite;
  final bool busy;
  final bool enabled;
  final VoidCallback onJoin;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final by = invite.invitedBy;
    final expires = invite.expiresAt;
    final secondary = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.45);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
                  child: Icon(Icons.family_restroom_rounded, size: 24, color: scheme.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(invite.familyName ?? '', style: Theme.of(context).textTheme.titleMedium),
                      if (by != null && by.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(l.familyInvitedBy(by), style: secondary),
                      ],
                      if (expires != null) ...[
                        const SizedBox(height: 2),
                        Text(l.familyInviteExpires(AppDates.full(context, expires)), style: secondary),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: FamilyInvitationsScreen.declineKey(invite.id),
                    onPressed: enabled ? onDecline : null,
                    child: Text(l.familyDecline, textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: FamilyInvitationsScreen.joinKey(invite.id),
                    onPressed: enabled ? onJoin : null,
                    child: busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(l.familyJoin, textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
