import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:frontend/models/family_spending.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/screens/family/family_spending_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/date_format.dart';
import 'package:frontend/utils/money.dart';
import 'package:frontend/widgets/hero_card.dart';

/// One person's month on the Family spending screen ([memberId] null: Whole
/// family): what was spent on them by category, their last 6 months, their
/// biggest entries (their share of each) and who added them. Read only: the
/// entries don't open, since the app's entry screen follows the switched-on
/// book, which may be Personal here.
class FamilyPersonSpendingScreen extends StatefulWidget {
  const FamilyPersonSpendingScreen({
    super.key,
    required this.month,
    required this.currency,
    this.memberId,
    required this.displayName,
    required this.loader,
  });

  /// The 1st of the month.
  final DateTime month;
  final Currency currency;
  final String? memberId;

  /// Shown in the title while loading (the app's own string for Whole family).
  final String displayName;
  final PersonSpendingLoader loader;

  @override
  State<FamilyPersonSpendingScreen> createState() => _FamilyPersonSpendingScreenState();
}

class _FamilyPersonSpendingScreenState extends State<FamilyPersonSpendingScreen> {
  FamilyPersonSpending? _data;
  String? _error;
  bool _loading = true;
  final Set<String> _open = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.loader(widget.month, memberId: widget.memberId, currency: widget.currency);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  String _name(AppLocalizations l) {
    final data = _data;
    if (widget.memberId == null) return l.wholeFamily;
    if (data != null && data.isFormer) return l.familyFormerName(data.displayName);
    return data?.displayName ?? widget.displayName;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_name(l))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: _body(l)),
      ),
    );
  }

  List<Widget> _body(AppLocalizations l) {
    final data = _data;
    if (_loading && data == null) {
      return const [Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))];
    }
    if (_error != null) {
      return [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(key: const Key('family-person-retry'), onPressed: _load, child: Text(l.tryAgain)),
          ]),
        ),
      ];
    }
    if (data == null) return const [];
    final change = spendingChange(l, data.amount, data.previousAmount);
    final previous = DateTime(data.month.year, data.month.month - 1);
    return [
      HeroCard(
        label: '${_name(l)} · ${l.formatMonthYear(data.month)}',
        value: formatMoney(data.amount, data.currency),
        supporting: change == null ? null : '$change ${l.familySpendingVsLast(l.formatShortMonth(previous))}',
      ),
      if (data.addedBy.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          l.familySpendingAddedBy(data.addedBy.map((a) => '${a.displayName} (${a.count})').join(', ')),
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
      if (data.categories.isNotEmpty) ...[
        _heading(l.familySpendingByCategory),
        for (final c in data.categories) ..._category(c, data.currency),
      ],
      _heading(l.familySpendingTrend),
      _trend(l, data),
      if (data.topEntries.isNotEmpty) ...[
        _heading(l.familySpendingBiggest),
        for (final e in data.topEntries) _entry(l, e, data.currency),
      ],
    ];
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  List<Widget> _category(CategorySpending c, Currency currency) {
    final scheme = Theme.of(context).colorScheme;
    final open = _open.contains(c.mainCategory);
    return [
      InkWell(
        key: Key('family-person-category-${c.mainCategory}'),
        borderRadius: BorderRadius.circular(8),
        onTap: c.subCategories.isEmpty
            ? null
            : () => setState(() => open ? _open.remove(c.mainCategory) : _open.add(c.mainCategory)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Expanded(child: Text(c.mainCategory, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(formatMoney(c.amount, currency), style: AppTheme.money(13, weight: FontWeight.w700)),
            if (c.subCategories.isNotEmpty)
              Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: scheme.onSurfaceVariant),
          ]),
        ),
      ),
      if (open)
        for (final s in c.subCategories)
          Padding(
            key: Key('family-person-sub-${s.subCategory}'),
            padding: const EdgeInsets.only(left: 16, right: 18, bottom: 6),
            child: Row(children: [
              Expanded(child: Text(s.subCategory, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant))),
              Text(formatMoney(s.amount, currency), style: AppTheme.money(12, color: scheme.onSurfaceVariant)),
            ]),
          ),
    ];
  }

  Widget _trend(AppLocalizations l, FamilyPersonSpending data) {
    final scheme = Theme.of(context).colorScheme;
    final top = data.trend.fold<double>(0, (m, t) => t.amount > m ? t.amount : m);
    return SizedBox(
      height: 180,
      child: BarChart(
        swapAnimationDuration: Duration.zero,
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: top > 0 ? top * 1.15 : 1,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) => scheme.primary,
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                formatMoney(rod.toY, data.currency),
                AppTheme.money(12, weight: FontWeight.w700, color: scheme.onPrimary),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= data.trend.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(l.formatShortMonth(data.trend[i].month),
                        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < data.trend.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: data.trend[i].amount,
                  width: 18,
                  borderRadius: BorderRadius.circular(4),
                  color: i == data.trend.length - 1 ? scheme.primary : scheme.primary.withValues(alpha: 0.45),
                ),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _entry(AppLocalizations l, SpendingEntry e, Currency currency) {
    final scheme = Theme.of(context).colorScheme;
    final title = (e.description ?? '').trim().isEmpty ? e.subCategory : e.description!.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${AppDates.full(context, e.date)} · ${e.subCategory}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            if (e.splitBetween > 1)
              Text(l.familySpendingSharedWith(e.splitBetween - 1),
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(width: 8),
        Text(formatMoney(e.share, currency), style: AppTheme.money(13, weight: FontWeight.w700)),
      ]),
    );
  }
}
