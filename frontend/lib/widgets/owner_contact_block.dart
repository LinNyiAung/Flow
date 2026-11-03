import 'package:flutter/material.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/utils/contact_details.dart';

/// "Contact us directly": the owner's email (tap: opens the email app) and
/// Viber number (tap: opens a Viber chat). When a link cannot be opened the
/// value is copied to the clipboard and a snackbar says so. Each line is hidden
/// when the owner has not set it, and the whole block when neither is set.
class OwnerContactBlock extends StatelessWidget {
  const OwnerContactBlock({
    super.key,
    required this.contact,
    this.centered = false,
  });

  final OwnerContact contact;

  /// Centre the lines (inside the Upgrade screen's contact box) instead of
  /// aligning them to the start (inside the dialog).
  final bool centered;

  @override
  Widget build(BuildContext context) {
    if (contact.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: const Key('owner-contact'),
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l.ownerContactTitle,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        if (contact.hasEmail)
          _ContactLine(
            key: const Key('owner-contact-email'),
            icon: Icons.mail_outline_rounded,
            label: l.ownerContactEmail,
            value: contact.email,
            centered: centered,
            onTap: () => _open(
              context,
              mailtoUri(contact.email),
              contact.email,
              l.ownerContactEmailFailed(contact.email),
            ),
          ),
        if (contact.hasViber)
          _ContactLine(
            key: const Key('owner-contact-viber'),
            icon: Icons.chat_rounded,
            label: l.ownerContactViber,
            value: contact.viber,
            centered: centered,
            onTap: () => _open(
              context,
              viberChatUri(contact.viber),
              contact.viber,
              l.ownerContactViberFailed(contact.viber),
            ),
          ),
      ],
    );
  }

  Future<void> _open(
    BuildContext context,
    Uri uri,
    String value,
    String failedMessage,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await openContactLink(uri, value);
    if (!opened) {
      messenger.showSnackBar(SnackBar(content: Text(failedMessage)));
    }
  }
}

class _ContactLine extends StatelessWidget {
  const _ContactLine({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.centered,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool centered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment:
              centered ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Text(
              '$label: ',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            Flexible(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: scheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
