import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// The look of an insight report written in Markdown (headings, bullets, bold):
/// shared by the weekly / monthly insight and the custom insight report.
MarkdownStyleSheet insightMarkdownStyle(Color headingColor, Color bodyColor) {
  return MarkdownStyleSheet(
    blockSpacing: 14,
    h1: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: headingColor),
    h2: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: headingColor),
    h3: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: headingColor),
    p: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: bodyColor, height: 1.55),
    strong: TextStyle(fontWeight: FontWeight.w800, color: headingColor),
    listBullet: TextStyle(fontSize: 14, color: bodyColor),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: bodyColor.withValues(alpha: 0.15))),
    ),
  );
}
