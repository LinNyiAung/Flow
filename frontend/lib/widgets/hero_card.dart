import 'package:flutter/material.dart';
import 'package:frontend/theme/app_theme.dart';

/// The tonal hero used at the top of Dashboard, Budgets, Goals, Reports and
/// analytics screens. primaryContainer fill, radius 24, a label line, a big
/// tabular-figure amount, an optional supporting line, and optional nested
/// [StatTile]s below.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.label,
    required this.value,
    this.labelTrailing,
    this.supporting,
    this.stats,
    this.onLabelTap,
    this.footer,
  });

  final String label;
  final String value;
  final Widget? labelTrailing;
  final String? supporting;
  final List<Widget>? stats;
  final VoidCallback? onLabelTap;

  /// Optional content rendered inside the card below the stats (or below
  /// [supporting] if there are none) — e.g. a progress bar for the figure
  /// above. Kept inside the tonal card so it visibly belongs to it, rather
  /// than callers composing a separate element underneath that reads as
  /// disconnected from the card it's describing.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.82),
                  ),
                ),
              ),
              if (labelTrailing != null)
                GestureDetector(onTap: onLabelTap, child: labelTrailing),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: AppTheme.money(40, weight: FontWeight.w800, color: scheme.onPrimaryContainer),
          ),
          if (supporting != null) ...[
            const SizedBox(height: 6),
            Text(
              supporting!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: scheme.onPrimaryContainer.withValues(alpha: 0.82),
              ),
            ),
          ],
          if (stats != null && stats!.isNotEmpty) ...[
            const SizedBox(height: 18),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _withGaps(stats!, 10),
              ),
            ),
          ],
          if (footer != null) ...[
            const SizedBox(height: 16),
            footer!,
          ],
        ],
      ),
    );
  }

  static List<Widget> _withGaps(List<Widget> children, double gap) {
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) out.add(SizedBox(width: gap));
      out.add(Expanded(child: children[i]));
    }
    return out;
  }
}
