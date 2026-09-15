import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/services/localization_service.dart';
import '../../models/insight.dart';
import '../../providers/insight_provider.dart';
import '../../widgets/app_drawer.dart';

class InsightsScreen extends StatefulWidget {
  @override
  _InsightsScreenState createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchInsights();
    });
  }

  Future<void> _fetchInsights() async {
    final locale = Localizations.localeOf(context);
    final language = locale.languageCode == 'my' ? 'mm' : 'en';

    await Provider.of<InsightProvider>(
      context,
      listen: false,
    ).fetchInsights(language: language);
  }

  Future<void> _regenerateInsights() async {
    final insightProvider = Provider.of<InsightProvider>(
      context,
      listen: false,
    );
    final locale = Localizations.localeOf(context);
    final language = locale.languageCode == 'my' ? 'mm' : 'en';
    final localizations = AppLocalizations.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  localizations.generatingInsights,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        );
      },
    );

    final success = await insightProvider.regenerateInsights(
      language: language,
    );

    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog

    final messenger = ScaffoldMessenger.of(context);
    if (success) {
      messenger.showSnackBar(
        SnackBar(content: Text(localizations.insightsRegeneratedSuccessfully)),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            insightProvider.error ?? localizations.failedToRegenerateInsights,
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final insightProvider = Provider.of<InsightProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(localizations.aiInsights),
        actions: [
          if (authProvider.isPremium)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: localizations.regenerate,
              onPressed: insightProvider.isLoading ? null : _regenerateInsights,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Consumer<NotificationProvider>(
              builder: (context, notificationProvider, child) {
                return IconButton(
                  icon: Badge(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    textColor: Colors.white,
                    isLabelVisible: notificationProvider.unreadCount > 0,
                    label: Text(
                      notificationProvider.unreadCount > 9
                          ? '9+'
                          : '${notificationProvider.unreadCount}',
                    ),
                    child: const Icon(Icons.notifications_rounded),
                  ),
                  onPressed: () {
                    Navigator.pushNamed(context, '/notifications').then((_) {
                      notificationProvider.fetchUnreadCount();
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchInsights,
        child: authProvider.isPremium
            ? _buildPremiumBody(insightProvider)
            : _buildLockedBody(insightProvider),
      ),
    );
  }

  // ── Premium ──────────────────────────────────────────────────────

  Widget _buildPremiumBody(InsightProvider insightProvider) {
    final localizations = AppLocalizations.of(context);

    if (insightProvider.isLoading ||
        (insightProvider.insight == null && insightProvider.error == null)) {
      return _buildLoading(localizations);
    }

    if (insightProvider.error != null && insightProvider.insight == null) {
      return _buildError(insightProvider, localizations);
    }

    if (insightProvider.insight == null) {
      return _buildEmpty(localizations);
    }

    final scheme = Theme.of(context).colorScheme;
    final insight = insightProvider.insight!;
    final periodLabel = insightProvider.insightType == 'monthly'
        ? localizations.monthly
        : localizations.weekly;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 130),
      children: [
        _periodToggle(insightProvider),
        const SizedBox(height: 12),
        _headerCard(insightProvider, periodLabel, scheme),
        const SizedBox(height: 12),
        ..._fullReportSectionCards(insightProvider, insight, scheme),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            DateFormat('MMM d, h:mm a').format(insight.generatedAt),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _headerCard(
    InsightProvider insightProvider,
    String periodLabel,
    ColorScheme scheme,
  ) {
    return Card(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(Icons.lightbulb_rounded, size: 20, color: scheme.tertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                periodLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.tertiary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _translateChip(insightProvider, scheme),
          ],
        ),
      ),
    );
  }

  // The full report comes back as one flat run of markdown, each of its
  // own sections marked only by a stand-alone bold line ("**📊 Last Week's
  // Summary**", the same weight as any other bold phrase in the body), so
  // showing it as-is reads as one dense wall of text. Splitting it at
  // those section titles and giving each its own collapsed card lets
  // people open just the section they care about — "Budget Performance"
  // or "Weekly Challenge" — instead of scrolling a single long report.
  // This also means the full report is useful on its own even when the
  // AI's separate structured-summary JSON fails to parse for a given run:
  // there's no dependency between the two.
  List<Widget> _fullReportSectionCards(InsightProvider insightProvider, Insight insight, ColorScheme scheme) {
    final content = _stripLeadingSummaryBlock(insightProvider.getContentForLanguage() ?? insight.content);
    final sections = _splitReportSections(content);

    final widgets = <Widget>[];
    for (var i = 0; i < sections.length; i++) {
      if (i > 0) widgets.add(const SizedBox(height: 12));
      widgets.add(_reportSectionCard(sections[i].$1, sections[i].$2, scheme));
    }
    return widgets;
  }

  Widget _reportSectionCard(String title, String body, ColorScheme scheme) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onSurface)),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        children: [
          MarkdownBody(
            data: body,
            styleSheet: _reportMarkdownStyle(scheme.onSurface, scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // Splits the report on section-title lines. The model isn't perfectly
  // consistent about how it marks those from one generation to the next —
  // sometimes a real markdown heading ("## 📊 Last Week's Summary"),
  // sometimes a stand-alone bold line ("**📊 Last Week's Summary**") — so
  // both are recognized here. A stand-alone bold line means nothing else
  // on that line: a detail bullet like "**Groceries:** Aim to..." has more
  // text after the closing ** on the same line, so it's left inside
  // whichever section it belongs to rather than being treated as a title.
  // Falls back to one "Full report" section covering everything if no
  // heading of either style is found, so an unexpected format still shows
  // the content instead of nothing.
  List<(String, String)> _splitReportSections(String content) {
    final headingLine = RegExp(
      r'^[ \t]*(?:#{1,6}[ \t]+(.+?)|(?:\d+\.[ \t]*)?\*\*(.{1,80}?)\*\*)[ \t]*$',
      multiLine: true,
    );
    final matches = headingLine.allMatches(content).toList();
    if (matches.isEmpty) return [('Full report', content)];

    final sections = <(String, String)>[];
    for (var i = 0; i < matches.length; i++) {
      final title = (matches[i].group(1) ?? matches[i].group(2))!.trim();
      final bodyStart = matches[i].end;
      final bodyEnd = i + 1 < matches.length ? matches[i + 1].start : content.length;
      final body = content.substring(bodyStart, bodyEnd).trim();
      if (body.isNotEmpty) sections.add((title, body));
    }
    return sections.isEmpty ? [('Full report', content)] : sections;
  }

  MarkdownStyleSheet _reportMarkdownStyle(Color headingColor, Color bodyColor) {
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

  // In the header, next to the period label, rather than below the full
  // report — buried under a long scroll of sections, it wasn't reachable
  // without scrolling all the way down.
  Widget _translateChip(InsightProvider insightProvider, ColorScheme scheme) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _toggleInsightLanguage(insightProvider),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.tertiary),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.translate_rounded, size: 15, color: scheme.tertiary),
            const SizedBox(width: 5),
            Text(
              // Shows the language a tap switches *to*, matching the
              // mockup's translate toggle.
              insightProvider.currentLanguage == 'mm' ? 'ENGLISH' : 'မြန်မာ',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.onTertiaryContainer,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mirrors the mockup's `toggleInsightLang` action: flips to the other
  /// language if the insight already carries that translation, otherwise
  /// fetches the Myanmar translation on demand.
  Future<void> _toggleInsightLanguage(InsightProvider insightProvider) async {
    final target = insightProvider.currentLanguage == 'mm' ? 'en' : 'mm';
    if (target == 'mm' && insightProvider.insight?.contentMm == null) {
      final success = await insightProvider.translateToMyanmar();
      if (!mounted || success) return;
      final localizations = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(insightProvider.error ?? localizations.failedToRegenerateInsights),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } else {
      insightProvider.setLanguage(target);
    }
  }

  Widget _periodToggle(InsightProvider insightProvider) {
    final scheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);

    Widget seg(String type, String label) {
      final selected = insightProvider.insightType == type;
      return Expanded(
        child: GestureDetector(
          onTap: selected
              ? null
              : () async {
                  insightProvider.setInsightType(type);
                  await _fetchInsights();
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? scheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          seg('weekly', localizations.weekly),
          const SizedBox(width: 4),
          seg('monthly', localizations.monthly),
        ],
      ),
    );
  }

  Widget _buildLoading(AppLocalizations localizations) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 120),
      children: [
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 24),
        Center(
          child: Text(
            localizations.analyzingYourFinancialData,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            localizations.thisMayTakeFewSeconds,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _buildError(InsightProvider insightProvider, AppLocalizations localizations) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 100, horizontal: 32),
      children: [
        Center(child: Icon(Icons.error_outline_rounded, size: 48, color: scheme.error)),
        const SizedBox(height: 20),
        Center(
          child: Text(
            localizations.failedToLoadInsights,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            insightProvider.error!,
            style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: FilledButton.icon(
            onPressed: _fetchInsights,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(localizations.tryAgain),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(AppLocalizations localizations) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 100, horizontal: 32),
      children: [
        Center(child: Icon(Icons.lightbulb_outline_rounded, size: 48, color: scheme.primary)),
        const SizedBox(height: 20),
        Center(
          child: Text(
            localizations.noInsightsAvailable,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            localizations.addTransactionsGoalsToGenerateInsights,
            style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  // ── Locked (free) ────────────────────────────────────────────────

  Widget _buildLockedBody(InsightProvider insightProvider) {
    final scheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);
    final realContent = insightProvider.getContentForLanguage() ?? insightProvider.insight?.content;
    final hasReal = realContent != null && realContent.trim().isNotEmpty;

    const fallbackTitle = 'Your Thursdays cost 2.4× a normal day.';
    const fallbackBody =
        'Four of the last five Thursdays paired a delivery with a late ride home — about K61,000 a month. '
        'Moving one of the two to a home-cooked night saves roughly K30,000 and puts Food & Daily Living back under its cap.';
    const healthTitle = 'Health score: 78 out of 100';
    const healthBody =
        'Saving 72% of inflow is well above your six-month average, while one breached cap costs you six points this month.';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 130),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb_rounded, size: 20, color: scheme.tertiary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        hasReal ? 'This week' : 'Ready for you',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.tertiary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  hasReal ? _firstLine(realContent) : fallbackTitle,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.35),
                ),
                const SizedBox(height: 8),
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                  child: Text(
                    hasReal ? _restOfContent(realContent) : fallbackBody,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                      height: 1.55,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  healthTitle,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.35),
                ),
                const SizedBox(height: 8),
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                  child: Text(
                    healthBody,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                      height: 1.55,
                    ),
                  ),
                ),
                const Divider(height: 33),
                Text(
                  localizations.threeInsightsWaiting,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.5),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/subscription'),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                  label: Text(localizations.tryOneMonthFree),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    localizations.noCardRequiredCancelAnyTime,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Safety net: `content` should already have the leading ```json summary
  // block stripped server-side (see insights_service.py's
  // _extract_insight_summary), but if that ever fails for a given
  // response — malformed JSON, a truncated generation, model drift — the
  // raw fenced block would otherwise render as one giant unbroken code
  // block covering the whole rest of the report (flutter_markdown treats
  // everything after an unclosed/unexpected fence as code), which is a
  // much worse failure than just not having the block stripped. This
  // mirrors the backend's own extraction (bounded search for the opening
  // fence, plain string search for the closing one) so the client can
  // recover on its own rather than depending on every future backend
  // response getting the stripping right.
  String _stripLeadingSummaryBlock(String content) {
    final windowEnd = content.length < 500 ? content.length : 500;
    final openMatch = RegExp(r'```(?:json)?\s*\n?', caseSensitive: false)
        .firstMatch(content.substring(0, windowEnd));
    if (openMatch == null) return content;

    final rest = content.substring(openMatch.end);
    final closeIdx = rest.indexOf('```');
    if (closeIdx == -1) return content;

    final remainder = rest.substring(closeIdx + 3).replaceFirst(RegExp(r'^\s*-{3,}\s*\n'), '');
    return remainder.trim();
  }

  String _stripHeadings(String content) =>
      content.replaceAll(RegExp(r'^#+\s*', multiLine: true), '').trim();

  String _firstLine(String content) {
    final clean = _stripHeadings(content);
    final idx = clean.indexOf('\n');
    final firstBlock = idx == -1 ? clean : clean.substring(0, idx);
    final sentenceEnd = firstBlock.indexOf('. ');
    if (sentenceEnd != -1 && sentenceEnd < 140) {
      return firstBlock.substring(0, sentenceEnd + 1);
    }
    return firstBlock.length > 140 ? '${firstBlock.substring(0, 140)}…' : firstBlock;
  }

  String _restOfContent(String content) {
    final clean = _stripHeadings(content);
    final first = _firstLine(content);
    final rest = clean.startsWith(first) ? clean.substring(first.length).trim() : clean;
    return rest.isEmpty ? content : rest;
  }
}
