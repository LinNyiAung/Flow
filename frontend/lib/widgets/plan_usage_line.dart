import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:provider/provider.dart';

/// "3 of 5 left this week" for a counted allowance; null for a locked or
/// included one (nothing to count) or while the numbers are unknown. The
/// remaining number is never negative or above the limit.
String? planUsageText(AppLocalizations localizations, FeatureAllowance? a) {
  if (a == null || !a.isCounted) return null;
  final limit = a.limit;
  if (limit == null) return null;
  final left = a.remaining ?? (limit - (a.used ?? 0));
  final remaining = math.min(math.max(left, 0), limit);
  return a.period == 'week'
      ? localizations.planUsageLeftWeek(remaining, limit)
      : localizations.planUsageLeftMonth(remaining, limit);
}

/// A small, unobtrusive line under an AI feature showing what is left of
/// its allowance, for example "3 of 5 left this week". Renders nothing for
/// features that are locked, included without a count, or not loaded yet.
class PlanUsageLine extends StatelessWidget {
  const PlanUsageLine({
    super.key,
    required this.feature,
    this.padding = const EdgeInsets.only(bottom: 8),
    this.alignment = Alignment.centerLeft,
  });

  /// A [PlanFeature] key, e.g. [PlanFeature.chat].
  final String feature;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final allowance =
        context.select<PlanProvider, FeatureAllowance?>((p) => p.feature(feature));
    final text = planUsageText(AppLocalizations.of(context), allowance);
    if (text == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final exhausted = allowance!.isExhausted;
    return Padding(
      padding: padding,
      child: Align(
        alignment: alignment,
        child: Text(
          text,
          key: Key('plan-usage-$feature'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: exhausted ? scheme.error : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
