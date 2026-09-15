import 'package:flutter/material.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/services/localization_service.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(localizations.privacyPolicyTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.privacy_tip_rounded, color: scheme.onPrimaryContainer, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          localizations.privacyPolicyTitle,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          localizations.privacyPolicySubtitle,
                          style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer.withValues(alpha: 0.85)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Content Sections
            _buildSection(
              scheme: scheme,
              title: localizations.privacyIntroTitle,
              content: localizations.privacyIntroBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.privacyInfoCollectTitle,
              content: localizations.privacyInfoCollectBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.privacyUseInfoTitle,
              content: localizations.privacyUseInfoBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.privacyDataSecurityTitle,
              content: localizations.privacyDataSecurityBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.privacyDataSharingTitle,
              content: localizations.privacyDataSharingBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.privacyAiProcessingTitle,
              content: localizations.privacyAiProcessingBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.privacyYourRightsTitle,
              content: localizations.privacyYourRightsBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.privacyDataRetentionTitle,
              content: localizations.privacyDataRetentionBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.privacyChildrensTitle,
              content: localizations.privacyChildrensBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.privacyIntlTransfersTitle,
              content: localizations.privacyIntlTransfersBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.privacyChangesTitle,
              content: localizations.privacyChangesBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.privacyContactTitle,
              content: localizations.privacyContactBody,
            ),

            const SizedBox(height: 12),

            // Security Notice
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.infoContainerFor(context),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.security_rounded, color: AppTheme.infoFor(context), size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      localizations.privacySecurityNotice,
                      style: TextStyle(fontSize: 13, color: AppTheme.infoFor(context), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required ColorScheme scheme, required String title, required String content}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(
                content,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
