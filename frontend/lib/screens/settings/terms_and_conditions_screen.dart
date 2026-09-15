import 'package:flutter/material.dart';
import 'package:frontend/services/localization_service.dart';

class TermsAndConditionsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(localizations.termsTitle)),
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
                  Icon(Icons.description_rounded, color: scheme.onPrimaryContainer, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          localizations.termsTitle,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          localizations.termsSubtitle,
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
              title: localizations.termsAcceptanceTitle,
              content: localizations.termsAcceptanceBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.termsUseOfServiceTitle,
              content: localizations.termsUseOfServiceBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.termsAccountRegTitle,
              content: localizations.termsAccountRegBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.termsUserResponsibilitiesTitle,
              content: localizations.termsUserResponsibilitiesBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.termsAiFeaturesTitle,
              content: localizations.termsAiFeaturesBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.termsPremiumSubTitle,
              content: localizations.termsPremiumSubBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.termsDataProcessingTitle,
              content: localizations.termsDataProcessingBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.termsIntellectualPropertyTitle,
              content: localizations.termsIntellectualPropertyBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.termsLimitationLiabilityTitle,
              content: localizations.termsLimitationLiabilityBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.termsTerminationTitle,
              content: localizations.termsTerminationBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.termsChangesTitle,
              content: localizations.termsChangesBody,
            ),

            _buildSection(
              scheme: scheme,
              title: localizations.termsContactInfoTitle,
              content: localizations.termsContactInfoBody,
            ),

            const SizedBox(height: 12),

            // Acceptance Notice
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, color: scheme.primary, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      localizations.termsAcceptanceNotice,
                      style: TextStyle(fontSize: 13, color: scheme.primary, fontWeight: FontWeight.w600),
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
