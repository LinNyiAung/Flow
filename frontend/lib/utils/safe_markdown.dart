/// The custom insight text is Markdown from an AI. The app renders only the
/// plain outline (headings, bullets, bold). Anything bigger (a table, a code
/// block, HTML, an image) is shown as plain text instead, never as a broken
/// or unsafe layout.
library;

final RegExp _separatorRow =
    RegExp(r'^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$');
final RegExp _fenceLine = RegExp(r'^\s*(```|~~~)');
final RegExp _htmlTag = RegExp(r'</?[A-Za-z][A-Za-z0-9-]*(\s[^<>\n]*)?/?>');

/// A table's `|---|` row. flutter_markdown accepts one or more dashes per
/// column (`|-|-|`), so this does too. A pipe is required, so a `---` rule is
/// not one.
bool _isSeparatorRow(String line) => line.contains('|') && _separatorRow.hasMatch(line);

final RegExp _listItem = RegExp(r'^\s*([-*+]|\d+[.)])\s');

/// True when line [i] starts an indented code block: indented 4+ spaces (or a
/// tab) right after a blank line, and not the continuation of a list item (the
/// last text line before the blank is neither a list item nor itself indented).
bool _startsIndentedCode(List<String> lines, int i) {
  final line = lines[i];
  if (!(line.startsWith('    ') || line.startsWith('\t')) || line.trim().isEmpty) return false;
  if (i == 0 || lines[i - 1].trim().isNotEmpty) return false;
  var j = i - 1;
  while (j >= 0 && lines[j].trim().isEmpty) {
    j--;
  }
  if (j < 0) return false;
  final before = lines[j];
  if (_listItem.hasMatch(before) || before.startsWith(' ') || before.startsWith('\t')) {
    return false;
  }
  return true;
}

/// True when [md] has a table (a pipe row followed by its `|---|` separator
/// row), a code fence, an indented code block, an HTML tag or an image. The
/// caller then shows [markdownToPlainText] instead of rendering Markdown.
bool hasDisallowedMarkdown(String md) {
  if (md.contains('![')) return true;
  if (_htmlTag.hasMatch(md)) return true;
  final lines = md.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (_fenceLine.hasMatch(lines[i])) return true;
    if (_startsIndentedCode(lines, i)) return true;
    if (i > 0 && lines[i - 1].contains('|') && _isSeparatorRow(lines[i])) return true;
  }
  return false;
}

/// [md] as readable plain text: heading `#`s, `**`/`__`/`*` emphasis, code
/// fences, HTML tags, table pipes and separator rows are removed, the text and
/// the line breaks stay. Table cells of a row are joined with " · ".
String markdownToPlainText(String md) {
  final lines = md.replaceAll('\r\n', '\n').split('\n');
  final out = <String>[];
  var inTable = false;
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (_fenceLine.hasMatch(line)) continue;

    final nextIsSeparator = i + 1 < lines.length && _isSeparatorRow(lines[i + 1]);
    if (_isSeparatorRow(line)) {
      inTable = true;
      continue;
    }
    if (line.contains('|') && (nextIsSeparator || inTable)) {
      inTable = true;
      line = line
          .split('|')
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty)
          .join(' · ');
    } else {
      inTable = false;
    }

    line = line
        .replaceFirst(RegExp(r'^\s{0,3}#{1,6}\s*'), '')
        .replaceFirst(RegExp(r'\s+#+\s*$'), '')
        .replaceFirstMapped(RegExp(r'^(\s*)[*+]\s+'), (m) => '${m[1]}- ')
        .replaceAllMapped(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), (m) => m[1] ?? '')
        .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1] ?? '')
        .replaceAll(_htmlTag, '')
        .replaceAll('**', '')
        .replaceAll('__', '')
        .replaceAll('*', '')
        .replaceAll('`', '');
    out.add(line.trimRight());
  }
  return out.join('\n').trim();
}
