import 'package:flutter/material.dart';
import 'package:frontend/models/app_config.dart';
import 'package:frontend/providers/app_control_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/screens/family/family_ui.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/app_bar_save_button.dart';
import 'package:frontend/widgets/app_bar_title.dart';
import 'package:frontend/widgets/paused_feature.dart';
import 'package:provider/provider.dart';

/// Admins invite someone by the email they signed up with. The invite can
/// say who they already are in the family ("This is …"): a name-only member
/// or a former member, whose entries then become theirs on joining.
class FamilyInviteScreen extends StatefulWidget {
  const FamilyInviteScreen({super.key});

  static const Key emailKey = ValueKey('invite-email');
  static const Key sendKey = ValueKey('invite-send');
  static const Key noLinkKey = ValueKey('invite-link-none');
  static Key linkKey(String memberId) => ValueKey('invite-link-$memberId');

  @override
  State<FamilyInviteScreen> createState() => _FamilyInviteScreenState();
}

class _FamilyInviteScreenState extends State<FamilyInviteScreen> {
  static final RegExp _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final TextEditingController _email = TextEditingController();
  String? _link;
  bool _sending = false;
  String? _emailError;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (showIfPaused(context, 'family_new')) return;
    final l = AppLocalizations.of(context);
    final email = _email.text.trim();
    if (!_emailShape.hasMatch(email)) {
      setState(() => _emailError = l.enterValidEmailError);
      return;
    }
    final family = Provider.of<FamilyProvider>(context, listen: false);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _sending = true;
      _emailError = null;
      _error = null;
    });
    final error = await family.invite(email, linkMemberId: _link);
    if (!mounted) return;
    if (error == null) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(l.familyInviteSent(email))));
      return;
    }
    setState(() {
      _sending = false;
      if (!family.lastErrorReported) _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final family = Provider.of<FamilyProvider>(context);
    // Who the invitee may already be: a name-only member, or a former member.
    final linkable = family.members.where((m) => m.isPlaceholder || m.isFormer).toList();

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(l.familyInviteAction),
        actions: [
          AppBarSaveButton(key: FamilyInviteScreen.sendKey, label: l.familyInviteSend, saving: _sending, onPressed: _send),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            l.familyInviteIntroDays(
              (AppControlProvider.maybeOf(context)?.config ?? AppConfig.open).inviteDays,
            ),
            style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 16),
          TextField(
            key: FamilyInviteScreen.emailKey,
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.send,
            decoration: InputDecoration(
              labelText: l.emailLabel,
              prefixIcon: const Icon(Icons.mail_outline_rounded),
              errorText: _emailError,
              errorMaxLines: 3,
            ),
            onChanged: (_) {
              if (_emailError != null || _error != null) {
                setState(() {
                  _emailError = null;
                  _error = null;
                });
              }
            },
            onSubmitted: (_) {
              if (!_sending) _send();
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(fontSize: 13, color: scheme.error, height: 1.45)),
          ],
          if (linkable.isNotEmpty) ...[
            const SizedBox(height: 28),
            FamilySectionHeader(l.familyInviteThisIs),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
              child: Text(
                l.familyInviteLinkHint,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.45),
              ),
            ),
            Card(
              child: Column(
                children: [
                  _LinkOption(
                    key: FamilyInviteScreen.noLinkKey,
                    title: l.familyInviteSomeoneNew,
                    selected: _link == null,
                    onTap: () => setState(() => _link = null),
                  ),
                  for (final m in linkable) ...[
                    const Divider(),
                    _LinkOption(
                      key: FamilyInviteScreen.linkKey(m.id),
                      title: m.displayName,
                      subtitle: m.isFormer ? l.familyFormer : l.familyNameOnly,
                      selected: _link == m.id,
                      onTap: () => setState(() => _link = m.id),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One choice of "This is …": a radio mark and a name that wraps.
class _LinkOption extends StatelessWidget {
  const _LinkOption({super.key, required this.title, required this.selected, required this.onTap, this.subtitle});

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
