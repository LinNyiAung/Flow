import 'package:flutter/material.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/utils/plan_limit_text.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';

/// Shows the friendly "you've hit your plan's limit" sheet for [error]: what
/// ran out (or isn't in the plan), when it resets, and an Upgrade button when
/// a higher plan exists.
///
/// What it does depends on [PlanLimitException.code] only. The sheet writes
/// its own text from the code, the feature and the reset date, in the app's
/// language (the server's message follows the profile language and its date
/// format, so it is used only for a code or feature the app does not know).
Future<void> showPlanLimitSheet(BuildContext context, PlanLimitException error) {
  final navigator = Navigator.of(context);
  return showAppBottomSheet<void>(
    context: context,
    builder: (sheetContext) => PlanLimitSheet(
      error: error,
      onUpgrade: () {
        Navigator.pop(sheetContext);
        navigator.pushNamed('/subscription');
      },
      onClose: () => Navigator.pop(sheetContext),
    ),
  );
}

/// If [error] is a plan limit, shows [showPlanLimitSheet] and returns true;
/// otherwise returns false and does nothing, so callers keep their usual
/// error handling.
Future<bool> handlePlanLimitError(BuildContext context, Object error) async {
  if (error is! PlanLimitException) return false;
  if (!context.mounted) return true;
  await showPlanLimitSheet(context, error);
  return true;
}

/// The content of the limit sheet. Also used inline (without [onClose]) as a
/// full-page state when there is nothing else to show.
class PlanLimitSheet extends StatelessWidget {
  const PlanLimitSheet({
    super.key,
    required this.error,
    required this.onUpgrade,
    this.onClose,
  });

  final PlanLimitException error;
  final VoidCallback onUpgrade;

  /// Closes the sheet; null when shown inline, where there is no dismiss.
  final VoidCallback? onClose;

  String _title(AppLocalizations l) {
    if (error.isLocked) return l.planFeatureLockedTitle;
    if (error.isCostCap) return l.planCostCapTitle;
    return l.planLimitReachedTitle;
  }

  IconData get _icon {
    if (error.isLocked) return Icons.lock_rounded;
    if (error.isCostCap) return Icons.bolt_rounded;
    return Icons.hourglass_bottom_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final feature = error.feature;
    final featureName = feature == null ? null : l.knownPlanFeatureName(feature);
    // The explanation is built from the code, the feature and the reset date in
    // the app's language (see planLimitText for when the server's message is used).
    final body = planLimitText(
      l,
      code: error.code,
      feature: feature,
      resetsAt: error.resetsAt,
      fallbackMessage: error.message,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(_icon, color: scheme.tertiary, size: 26),
        ),
        const SizedBox(height: 14),
        Text(
          _title(l),
          key: const Key('plan-limit-title'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        if (featureName != null && !error.isCostCap) ...[
          const SizedBox(height: 4),
          Text(
            featureName,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: scheme.tertiary,
            ),
          ),
        ],
        if (body.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            body,
            key: const Key('plan-limit-body'),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
              height: 1.55,
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (error.upgradeAvailable) ...[
          FilledButton(
            key: const Key('plan-limit-upgrade'),
            onPressed: onUpgrade,
            child: Text(l.upgrade),
          ),
          if (onClose != null) ...[
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                key: const Key('plan-limit-dismiss'),
                onPressed: onClose,
                child: Text(l.planSheetNotNow),
              ),
            ),
          ],
        ] else if (onClose != null)
          FilledButton(
            key: const Key('plan-limit-dismiss'),
            onPressed: onClose,
            child: Text(l.close),
          ),
      ],
    );
  }
}
