import 'package:flutter/material.dart';

/// A top-bar title that is never cut off with "…".
///
/// One line at the bar's own size when it fits. Otherwise (long Myanmar
/// titles on a 360 px phone) two smaller lines; and if even that is too big
/// for the bar, the two-line block is scaled down to fit.
class AppBarTitle extends StatelessWidget {
  const AppBarTitle(this.text, {super.key, this.style});

  final String text;

  /// Merged over the bar's title style.
  final TextStyle? style;

  /// Size of the two-line form, relative to the bar's title size.
  static const double wrappedScale = 0.75;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final oneLine = Text(text, style: style, maxLines: 1, softWrap: false);
        if (!constraints.hasBoundedWidth) return oneLine;
        // AppBar lets its title be as tall as it likes; keep it to the bar.
        final maxHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : (AppBarTheme.of(context).toolbarHeight ?? kToolbarHeight);

        final base = DefaultTextStyle.of(context).style.merge(style);
        final direction = Directionality.of(context);
        final scaler = MediaQuery.textScalerOf(context);
        bool fits(TextStyle s, int maxLines) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: s),
            textDirection: direction,
            textScaler: scaler,
            maxLines: maxLines,
          )..layout(maxWidth: constraints.maxWidth);
          final ok = !painter.didExceedMaxLines && painter.height <= maxHeight;
          painter.dispose();
          return ok;
        }

        if (fits(base, 1)) return oneLine;

        final smaller = (style ?? const TextStyle()).copyWith(
          fontSize: (base.fontSize ?? 22) * wrappedScale,
          height: 1.25,
        );
        // softWrap / overflow: AppBar's DefaultTextStyle turns wrapping off and
        // asks for an ellipsis (which, with no maxLines, means one line).
        final twoLines = Text(text, style: smaller, maxLines: 2, softWrap: true);
        if (fits(base.merge(smaller), 2)) return twoLines;

        // Still too big: every line of it, scaled down to fit the bar.
        return SizedBox(
          height: maxHeight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: constraints.maxWidth,
              child: Text(text, style: smaller, softWrap: true, overflow: TextOverflow.visible),
            ),
          ),
        );
      },
    );
  }
}
