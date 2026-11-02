import 'package:flutter/material.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/status_pill.dart';

/// The display name of [plan] in the app language ("Free", "Plus", "Pro").
extension PlanNames on AppLocalizations {
  String planName(Plan plan) {
    switch (plan) {
      case Plan.free:
        return planNameFree;
      case Plan.plus:
        return planNamePlus;
      case Plan.pro:
        return planNamePro;
    }
  }
}

/// Small pill with the plan's name, e.g. "PLUS" or "PRO" (or "PLUS · TRIAL"
/// while the Plus trial runs).
class PlanBadge extends StatelessWidget {
  const PlanBadge({
    super.key,
    required this.plan,
    this.isTrial = false,
    this.dense = false,
  });

  final Plan plan;
  final bool isTrial;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final name = l.planName(plan).toUpperCase();
    final isPro = plan == Plan.pro;
    return StatusPill(
      label: isTrial ? '$name · ${l.planTrialBadge}' : name,
      background: isPro ? scheme.primaryContainer : scheme.tertiaryContainer,
      foreground: isPro ? scheme.primary : scheme.tertiary,
      dense: dense,
    );
  }
}
