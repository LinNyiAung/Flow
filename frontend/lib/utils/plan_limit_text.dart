import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';

/// The sentence that explains a plan limit, written from the error [code], the
/// quota [feature] and the reset date in the app's language and date format.
///
/// One place for every surface that shows a limit (the limit sheet, the
/// Insights translation note), so the wording cannot drift. The server's own
/// [fallbackMessage] (in the profile language, with its own date format) is
/// used only for a code the app does not know, or a feature it has no name for.
String planLimitText(
  AppLocalizations l, {
  required String code,
  String? feature,
  DateTime? resetsAt,
  String fallbackMessage = '',
}) {
  final fallback = fallbackMessage.trim();
  final featureName = feature == null ? null : l.knownPlanFeatureName(feature);
  final isLocked = code == PlanLimitException.codeLocked;
  final String what;
  if (code == PlanLimitException.codeCostCap) {
    what = l.planCostCapBody;
  } else if (isLocked) {
    if (feature != null && featureName == null) return fallback;
    what = featureName == null ? l.planPaidRequiredBody : l.planLimitLockedBody(featureName);
  } else if (code == PlanLimitException.codeLimitReached) {
    if (feature != null && featureName == null) return fallback;
    what = featureName == null ? '' : l.planLimitReachedBody(featureName);
  } else {
    return fallback;
  }
  final resets = resetsAt == null || isLocked ? '' : l.planLimitResetsOn(l.formatPlanDate(resetsAt));
  return [what, resets].where((s) => s.isNotEmpty).join(' ');
}
