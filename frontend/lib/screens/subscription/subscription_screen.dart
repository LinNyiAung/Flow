import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:frontend/widgets/app_list_row.dart';

import '../../services/localization_service.dart';

class SubscriptionScreen extends StatefulWidget {
  @override
  _SubscriptionScreenState createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _isClaiming = false;

  Future<void> _claimFreeTrial(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    setState(() => _isClaiming = true);

    final success = await authProvider.claimFreeTrial();

    setState(() => _isClaiming = false);

    if (!mounted) return;

    if (success) {
      final scheme = Theme.of(context).colorScheme;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.star_rounded, color: scheme.tertiary, size: 36),
              ),
              const SizedBox(height: 20),
              Text(
                '🎉 Welcome to Premium!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.onSurface),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'You now have 1 month of free premium access. Enjoy all features!',
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(backgroundColor: scheme.tertiary),
                  child: const Text("Let's go!"),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authProvider.error ?? 'Could not claim free trial.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Consumer<AuthProvider>(
          builder: (context, authProvider, child) {
            final isPremium = authProvider.isPremium;
            final hasClaimedTrial = authProvider.hasClaimedFreeTrial;

            return Column(
              children: [
                // ── Header ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          isPremium ? localizations.premiumStatus : localizations.upgradeToPremium,
                          style: theme.textTheme.titleLarge?.copyWith(color: scheme.onSurface),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Active premium card ─────────────────────
                        if (isPremium) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: scheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.star_rounded, color: scheme.tertiary, size: 44),
                                const SizedBox(height: 14),
                                Text(
                                  localizations.premiumActive,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: scheme.onTertiaryContainer,
                                  ),
                                ),
                                if (authProvider.subscriptionExpiresAt != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    '${localizations.expiresOn}: ${DateFormat('MMM dd, yyyy').format(authProvider.subscriptionExpiresAt!)}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onTertiaryContainer),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                        ],

                        // ── Free-month offer (leads, per redesign) ──
                        if (!isPremium && !hasClaimedTrial) ...[
                          _buildOfferHero(context, scheme),
                          const SizedBox(height: 28),
                        ],

                        // ── Features — plain list ───────────────────
                        Text(
                          localizations.premiumFeatures,
                          style: theme.textTheme.titleMedium?.copyWith(color: scheme.onSurface),
                        ),
                        const SizedBox(height: 12),
                        _buildFeatureList(localizations, scheme),

                        // ── Contact admin (only path to upgrade) ────
                        if (!isPremium) ...[
                          const SizedBox(height: 24),
                          _buildContactAdminBox(localizations),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── "One month free" tonal hero ────────────────────────────────────────────
  Widget _buildOfferHero(BuildContext context, ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ONE MONTH FREE',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 8),
          Text(
            'Let the app read your money for you.',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer, height: 1.25),
          ),
          const SizedBox(height: 8),
          Text(
            'Weekly insights, receipt scanning, voice entry and AI budgets — on your own transactions.',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onPrimaryContainer, height: 1.4),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isClaiming ? null : () => _claimFreeTrial(context),
              icon: _isClaiming
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Icon(Icons.card_giftcard_rounded, size: 20),
              label: Text(_isClaiming ? 'Claiming…' : 'Claim 1 month free'),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'No card required · then contact us to continue',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  // ── Feature list — plain rows instead of gradient cards ─────────────────────
  Widget _buildFeatureList(AppLocalizations localizations, ColorScheme scheme) {
    final features = <Widget>[
      AppListRow(
        icon: Icons.auto_awesome_rounded,
        title: localizations.aiBudgetSuggestions,
        subtitle: localizations.aiBudgetSuggestionsDes,
      ),
      AppListRow(
        icon: Icons.mic_rounded,
        title: localizations.voiceInput,
        subtitle: localizations.voiceInputDes,
      ),
      AppListRow(
        icon: Icons.photo_camera_rounded,
        title: localizations.receiptScanning,
        subtitle: localizations.receiptScanningDes,
      ),
      AppListRow(
        icon: Icons.smart_toy_rounded,
        title: localizations.aiFinancialAssistant,
        subtitle: localizations.aiFinancialAssistantDes,
      ),
      AppListRow(
        icon: Icons.lightbulb_rounded,
        title: localizations.aiInsights,
        subtitle: localizations.aiInsightsDes,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Theme.of(context).cardTheme.shadowColor ?? Colors.black12, blurRadius: 3, offset: const Offset(0, 1)),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < features.length; i++) ...[
            if (i > 0) Divider(color: scheme.outlineVariant, height: 1, thickness: 1),
            features[i],
          ],
        ],
      ),
    );
  }

  // ── Contact admin info box ─────────────────────────────────────────────────
  Widget _buildContactAdminBox(AppLocalizations localizations) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: scheme.outlineVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.lock_outline_rounded, color: scheme.onSurfaceVariant, size: 26),
          const SizedBox(height: 8),
          Text(
            localizations.contactAdmin,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            localizations.contactSupport,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
