import 'package:flutter/material.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:frontend/widgets/hero_card.dart';
import 'package:frontend/widgets/progress_meter.dart';
import 'package:frontend/widgets/stat_tile.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import '../../models/report.dart';
import '../../services/api_service.dart';
import '../../widgets/app_drawer.dart';

class ReportsScreen extends StatefulWidget {
  @override
  _ReportsScreenState createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  ReportPeriod _selectedPeriod = ReportPeriod.month;
  Currency? _selectedCurrency;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  FinancialReport? _report;
  MultiCurrencyFinancialReport? _multiCurrencyReport;
  bool _isLoading = false;
  bool _isDownloading = false;
  String? _error;
  final formatter = NumberFormat("#,##0.00", "en_US");
  final formatterWhole = NumberFormat("#,##0", "en_US");

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      setState(() {
        _selectedCurrency = authProvider.defaultCurrency;
      });
      _generateReport();
    });
  }

  Future<void> _generateReport() async {
    if (_selectedPeriod == ReportPeriod.custom &&
        (_customStartDate == null || _customEndDate == null)) {
      setState(() {
        _report = null;
        _multiCurrencyReport = null;
        _error = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_selectedCurrency == null) {
        final multiReport = await ApiService.generateMultiCurrencyReport(
          period: _selectedPeriod,
          startDate: _customStartDate,
          endDate: _customEndDate,
        );

        setState(() {
          _multiCurrencyReport = multiReport;
          _report = null;
          _isLoading = false;
        });
      } else {
        final report = await ApiService.generateReport(
          period: _selectedPeriod,
          startDate: _customStartDate,
          endDate: _customEndDate,
          currency: _selectedCurrency,
        );

        setState(() {
          _report = report;
          _multiCurrencyReport = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadReport() async {
    final localizations = AppLocalizations.of(context);
    if (_selectedPeriod == ReportPeriod.custom &&
        (_customStartDate == null || _customEndDate == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.selectStartEndDates)),
      );
      return;
    }

    setState(() => _isDownloading = true);

    try {
      final filePath = await ApiService.downloadReportPdf(
        period: _selectedPeriod,
        startDate: _customStartDate,
        endDate: _customEndDate,
        currency: _selectedCurrency,
      );

      if (!mounted) return;
      setState(() => _isDownloading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.reportDownloadedSuccessfully),
          action: SnackBarAction(
            label: localizations.open,
            onPressed: () => OpenFilex.open(filePath),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDownloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to download report: ${e.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        title: Text(localizations.financialReports),
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          if (_report != null)
            _isDownloading
                ? const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.ios_share_rounded),
                    tooltip: localizations.downloadPDF,
                    onPressed: _showExportSheet,
                  ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _generateReport,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 130),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPeriodSelector(),
              if (_selectedPeriod == ReportPeriod.custom) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildDateSelector(localizations.startDate, _customStartDate, (date) {
                        setState(() => _customStartDate = date);
                        if (_customEndDate != null) _generateReport();
                      }),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDateSelector(localizations.endDateNoOp, _customEndDate, (date) {
                        setState(() => _customEndDate = date);
                        if (_customStartDate != null) _generateReport();
                      }),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              if (_isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(localizations.generatingReport, style: TextStyle(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: [
                        Icon(Icons.error_outline_rounded, size: 56, color: scheme.error),
                        const SizedBox(height: 16),
                        Text(
                          localizations.errorTitle,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.error),
                        ),
                        const SizedBox(height: 8),
                        Text(_error!, style: TextStyle(color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                )
              else if (_report != null)
                _buildReportContent(_report!)
              else if (_multiCurrencyReport != null)
                _buildMultiCurrencyReportContent(_multiCurrencyReport!)
              else if (_selectedPeriod == ReportPeriod.custom)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: [
                        Icon(Icons.date_range_rounded, size: 56, color: scheme.outline),
                        const SizedBox(height: 16),
                        Text(
                          localizations.selectDatesToGenerateReport,
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Export sheet ─────────────────────────────────────────────────

  /// Maps to the mockup's `var(--accent)` token — a lighter mint in dark
  /// mode, distinct from `--primary` (used for filled buttons). Neither
  /// light nor dark [ColorScheme] exposes this role directly, so it's
  /// derived from the theme's own accent constants.
  Color _accentColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? AppTheme.darkAccent : AppTheme.jade;

  Future<void> _showExportSheet() async {
    final scheme = Theme.of(context).colorScheme;
    final accent = _accentColor(context);
    final report = _report;

    await showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Export this report', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            if (report != null)
              Text(
                '${DateFormat('MMM d').format(report.startDate.toUtc())} – ${DateFormat('MMM d, yyyy').format(report.endDate.toUtc())} · '
                '${report.currency.name.toUpperCase()} · ${report.totalTransactions} entries',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
              ),
            const SizedBox(height: 18),
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  InkWell(
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _downloadReport();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: scheme.errorContainer, shape: BoxShape.circle),
                            child: Icon(Icons.picture_as_pdf_rounded, color: scheme.error, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('PDF', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  'Charts, category tables and daily averages',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.download_rounded, size: 20, color: scheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 1, indent: 70, color: Theme.of(context).dividerTheme.color),
                  InkWell(
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _downloadReport();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
                            child: Icon(Icons.share_rounded, color: accent, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Send it on', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  'Same PDF, straight to Viber or email',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, size: 20, color: scheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Selectors ────────────────────────────────────────────────────

  // Horizontally scrollable rather than Wrap — on narrow screens the four
  // period pills can run wider than the row, and wrapping them produces the
  // "two rows of filters" look this layout was meant to get away from. The
  // currency picker now lives inside the hero card itself (or, in the "All
  // Currencies" view where there's no single hero, the summary line above
  // the per-currency cards) rather than in this row.
  Widget _buildPeriodSelector() {
    final localizations = AppLocalizations.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _segments([
          _Segment(localizations.week, _selectedPeriod == ReportPeriod.week, () => _selectPeriod(ReportPeriod.week)),
          _Segment(localizations.month, _selectedPeriod == ReportPeriod.month, () => _selectPeriod(ReportPeriod.month)),
          _Segment(localizations.year, _selectedPeriod == ReportPeriod.year, () => _selectPeriod(ReportPeriod.year)),
          _Segment(localizations.custom, _selectedPeriod == ReportPeriod.custom, () => _selectPeriod(ReportPeriod.custom)),
        ]),
      ),
    );
  }

  void _selectPeriod(ReportPeriod period) {
    setState(() {
      _selectedPeriod = period;
      if (period == ReportPeriod.custom) {
        _customStartDate = null;
        _customEndDate = null;
        _report = null;
        _multiCurrencyReport = null;
      }
    });
    if (period != ReportPeriod.custom) {
      _generateReport();
    }
  }

  // One dropdown chip for currency, rather than a whole separate labeled row
  // of per-currency choice chips underneath the period selector.
  Widget _currencyFilterChip() {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final label = _selectedCurrency == null
        ? localizations.allCurrencies
        : '${_selectedCurrency!.symbol} ${_selectedCurrency!.name.toUpperCase()}';

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _pickCurrencyFilter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface)),
            Icon(Icons.expand_more_rounded, size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  // Same currency picker, styled to sit on the hero card's tonal fill —
  // matches the currency pill on the Dashboard's "Available to spend" card.
  Widget _currencyHeroChip() {
    final scheme = Theme.of(context).colorScheme;
    final label = _selectedCurrency == null ? '' : _selectedCurrency!.name.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
          Icon(Icons.expand_more_rounded, size: 16, color: scheme.onSurface),
        ],
      ),
    );
  }

  void _pickCurrencyFilter() {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final options = <Currency?>[null, ...Currency.values];

    showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(localizations.currencyR, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final currency in options)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                currency == null
                    ? localizations.allCurrencies
                    : '${currency.symbol} ${currency.name.toUpperCase()} · ${currency.displayName}',
              ),
              trailing: _selectedCurrency == currency
                  ? Icon(Icons.check_circle_rounded, color: scheme.primary)
                  : null,
              onTap: () {
                setState(() => _selectedCurrency = currency);
                Navigator.pop(sheetContext);
                _generateReport();
              },
            ),
        ],
      ),
    );
  }

  // Mockup renders period filters as a row of discrete pills — filled
  // primary when selected, outlined otherwise (see "Reports" markup, lines
  // 449-452 of the prototype). Returned as a list (with gaps already
  // interspersed) so the caller can lay them out in a non-wrapping,
  // horizontally scrollable Row alongside the currency chip.
  List<Widget> _segments(List<_Segment> segments) {
    final scheme = Theme.of(context).colorScheme;
    final chips = segments.map((s) {
        return GestureDetector(
          onTap: s.selected ? null : s.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: s.selected ? scheme.primary : Colors.transparent,
              border: s.selected ? null : Border.all(color: scheme.outline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              s.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: s.selected ? FontWeight.w600 : FontWeight.w500,
                color: s.selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }).toList();
    final out = <Widget>[];
    for (var i = 0; i < chips.length; i++) {
      if (i > 0) out.add(const SizedBox(width: 8));
      out.add(chips[i]);
    }
    return out;
  }

  Widget _buildDateSelector(String label, DateTime? date, Function(DateTime) onDateSelected) {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (picked != null) onDateSelected(picked);
      },
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(
                date != null ? DateFormat('MMM d, yyyy').format(date) : localizations.select,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Single currency report ───────────────────────────────────────

  Widget _buildReportContent(FinancialReport report) {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final days = report.endDate.difference(report.startDate).inDays.clamp(1, 1 << 30);
    final savedPct = report.totalInflow > 0
        ? ((report.totalInflow - report.totalOutflow) / report.totalInflow * 100)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HeroCard(
          label:
              'Net · ${DateFormat('MMM d').format(report.startDate.toUtc())} – ${DateFormat('MMM d, yyyy').format(report.endDate.toUtc())}',
          value: '${report.netBalance >= 0 ? '+' : ''}${report.currency.symbol}${formatter.format(report.netBalance)}',
          labelTrailing: _currencyHeroChip(),
          onLabelTap: _pickCurrencyFilter,
          stats: [
            StatTile(icon: Icons.savings_rounded, label: 'Saved', value: '${savedPct.toStringAsFixed(0)}%'),
            StatTile(icon: Icons.receipt_long_rounded, label: 'Entries', value: '${report.totalTransactions}'),
            StatTile(
              icon: Icons.calendar_today_rounded,
              label: 'Per day',
              value: '${report.currency.symbol}${formatterWhole.format(report.averageDailyOutflow)}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _smallSummaryCard(localizations.income, report.totalInflow, scheme.primary, Icons.arrow_upward_rounded, report.currency),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _smallSummaryCard(localizations.expenses, report.totalOutflow, scheme.error, Icons.arrow_downward_rounded, report.currency),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _infoCard(localizations.goalsAllocated, '${report.currency.symbol}${formatter.format(report.totalAllocatedToGoals)}', Icons.flag_rounded)),
            const SizedBox(width: 12),
            Expanded(child: _infoCard('Days covered', '$days', Icons.event_note_rounded)),
          ],
        ),
        const SizedBox(height: 20),
        Text(localizations.dailyAverages, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _averageRow(localizations.averageDailyIncome, report.averageDailyInflow, scheme.primary, report.currency),
                const Divider(height: 24),
                _averageRow(localizations.averageDailyExpenses, report.averageDailyOutflow, scheme.error, report.currency),
              ],
            ),
          ),
        ),
        if (report.inflowByCategory.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(localizations.incomeByCategory, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: report.inflowByCategory
                    .take(5)
                    .map((cat) => _categoryRow(cat, scheme.primary, report.currency))
                    .toList(),
              ),
            ),
          ),
        ],
        if (report.outflowByCategory.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(localizations.expensesByCategory, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: report.outflowByCategory
                    .take(5)
                    .map((cat) => _categoryRow(cat, scheme.error, report.currency))
                    .toList(),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _smallSummaryCard(String label, double amount, Color color, IconData icon, Currency currency) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '${currency.symbol}${formatter.format(amount)}',
              style: AppTheme.money(17, weight: FontWeight.w700, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(String label, String value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: scheme.primary, size: 22),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTheme.money(16, weight: FontWeight.w700, color: scheme.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _averageRow(String label, double amount, Color color, Currency currency) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        Text(
          '${currency.symbol}${formatter.format(amount)}',
          style: AppTheme.money(15, weight: FontWeight.w700, color: color),
        ),
      ],
    );
  }

  Widget _categoryRow(CategoryBreakdown cat, Color color, Currency currency) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  cat.category,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${currency.symbol}${formatter.format(cat.amount)}',
                style: AppTheme.money(13, weight: FontWeight.w700, color: color),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ProgressMeter(value: cat.percentage / 100, overrideColor: color),
          const SizedBox(height: 5),
          Text(
            '${cat.percentage.toStringAsFixed(1)}% of total',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // ── Multi-currency report ────────────────────────────────────────

  Widget _buildMultiCurrencyReportContent(MultiCurrencyFinancialReport report) {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.public_rounded, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${DateFormat('MMM d').format(report.startDate.toUtc())} – ${DateFormat('MMM d, yyyy').format(report.endDate.toUtc())} · '
                '${report.totalTransactions} ${localizations.transactions.toLowerCase()} · '
                '${report.currencyReports.length} ${localizations.currencies.toLowerCase()}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _currencyFilterChip(),
          ],
        ),
        const SizedBox(height: 16),
        ...report.currencyReports.map(_currencyReportCard),
      ],
    );
  }

  Widget _currencyReportCard(CurrencyReport currencyReport) {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final currency = currencyReport.currency;
    final netBalance = currencyReport.netBalance;
    final balanceColor = netBalance >= 0 ? scheme.primary : scheme.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        currency.displayName,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.primary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${currencyReport.totalTransactions} txns',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      localizations.netBalance,
                      style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${currency.symbol}${formatter.format(netBalance)}',
                    style: AppTheme.money(19, weight: FontWeight.w700, color: balanceColor),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _miniStat(localizations.income, currencyReport.totalInflow, currencyReport.inflowCount, scheme.primary, currency),
                  ),
                  Container(width: 1, height: 40, color: scheme.outlineVariant),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _miniStat(localizations.expenses, currencyReport.totalOutflow, currencyReport.outflowCount, scheme.error, currency),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(8)),
                child: Column(
                  children: [
                    _multiAverageRow(localizations.avgDailyIncome, currencyReport.averageDailyInflow, scheme.primary, currency),
                    const SizedBox(height: 6),
                    _multiAverageRow(localizations.avgDailyExpenses, currencyReport.averageDailyOutflow, scheme.error, currency),
                  ],
                ),
              ),
              if (currencyReport.inflowByCategory.isNotEmpty || currencyReport.outflowByCategory.isNotEmpty) ...[
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    localizations.viewCategories,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.primary),
                  ),
                  children: [
                    if (currencyReport.inflowByCategory.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          localizations.topIncomeCategories,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                        ),
                      ),
                      ...currencyReport.inflowByCategory.take(3).map(
                            (cat) => _miniCategoryRow(cat, scheme.primary, currency),
                          ),
                    ],
                    if (currencyReport.outflowByCategory.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          localizations.topExpenseCategories,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                        ),
                      ),
                      ...currencyReport.outflowByCategory.take(3).map(
                            (cat) => _miniCategoryRow(cat, scheme.error, currency),
                          ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String label, double amount, int count, Color color, Currency currency) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(
          '${currency.symbol}${formatter.format(amount)}',
          style: AppTheme.money(16, weight: FontWeight.w700, color: color),
        ),
        Text('$count transactions', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _multiAverageRow(String label, double amount, Color color, Currency currency) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${currency.symbol}${formatter.format(amount)}',
          style: AppTheme.money(13, weight: FontWeight.w600, color: color),
        ),
      ],
    );
  }

  Widget _miniCategoryRow(CategoryBreakdown cat, Color color, Currency currency) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              cat.category,
              style: const TextStyle(fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${currency.symbol}${formatter.format(cat.amount)}',
            style: AppTheme.money(13, weight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

class _Segment {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  _Segment(this.label, this.selected, this.onTap);
}
