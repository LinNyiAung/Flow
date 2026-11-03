import 'package:flutter/material.dart';
import 'package:frontend/services/localization_service.dart';

/// The note under the Insights header saying why Myanmar is not shown (the
/// server refused to translate: a limit). The close button hides it for this
/// insight only.
class InsightTranslationNote extends StatelessWidget {
  const InsightTranslationNote({
    super.key,
    required this.message,
    required this.onClose,
  });

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              message,
              key: const ValueKey('insight-translation-note'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onTertiaryContainer,
              ),
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('insight-translation-note-close'),
          onPressed: onClose,
          tooltip: AppLocalizations.of(context).close,
          icon: Icon(Icons.close_rounded, size: 18, color: scheme.onTertiaryContainer),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

/// "Next insight: Monday, 10 November": when the next insight of the shown
/// type arrives. Renders nothing when the server sent no date (the type is not
/// available to the user).
class NextInsightLine extends StatelessWidget {
  const NextInsightLine({super.key, required this.nextAt});

  final DateTime? nextAt;

  @override
  Widget build(BuildContext context) {
    final at = nextAt;
    if (at == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        l.insightNextOn(l.formatPlanDay(at)),
        key: const ValueKey('insight-next'),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: scheme.onTertiaryContainer,
        ),
      ),
    );
  }
}
