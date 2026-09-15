import 'package:flutter/material.dart';

/// Small radius-8 badge — status labels ("EXCEEDED"), group headers, and the
/// drawer's "3 NEW" / "FREE MONTH" premium hints (a badge that invites a
/// look, not a padlock that says stop).
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.dense = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 2 : 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
      child: Text(
        label,
        style: TextStyle(
          fontSize: dense ? 10 : 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: foreground,
        ),
      ),
    );
  }
}
