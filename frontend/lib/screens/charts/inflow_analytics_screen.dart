import 'package:flutter/material.dart';
import 'package:frontend/utils/chart_buckets.dart';
import 'package:frontend/utils/date_format.dart';
import 'package:frontend/utils/date_locale.dart';
import 'package:frontend/widgets/app_bar_title.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/category_icons.dart';
import 'package:frontend/utils/chart_scale.dart';
import 'package:frontend/utils/date_picker_bounds.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:frontend/widgets/hero_card.dart';
import 'package:frontend/widgets/progress_meter.dart';
import 'package:frontend/widgets/stat_tile.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/transaction.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';
import '../../widgets/app_drawer.dart';

enum TimePeriod { daily, monthly, yearly, custom }

class InflowAnalyticsScreen extends StatefulWidget {
  const InflowAnalyticsScreen({super.key, this.transactionLoader = ApiService.getTransactions});

  /// Where the transactions come from; replaceable in tests.
  final TransactionLoader transactionLoader;

  @override
  _InflowAnalyticsScreenState createState() => _InflowAnalyticsScreenState();
}

class _InflowAnalyticsScreenState extends State<InflowAnalyticsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  TimePeriod _selectedPeriod = TimePeriod.monthly;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  List<Transaction> _filteredTransactions = [];
  int _touchedBarIndex = -1;
  bool _isLoading = false;
  final formatter = NumberFormat("#,##0.00", "en_US");

  Currency? _selectedCurrency;

  // Derived from _filteredTransactions, but only recomputed when that list
  // actually changes (see _recomputeDerivedData) rather than on every
  // build() — build() used to call _getCategoryData/_getCategoryCounts/
  // _getTimeSeriesData directly, which re-walks every fetched transaction
  // (up to 10,000) on every rebuild, including the ones triggered just by
  // tapping a bar to show its tooltip. That's what made the screen feel
  // slow while interacting with the chart.
  Map<String, double> _categoryData = {};
  Map<String, int> _categoryCounts = {};
  Map<String, double> _timeSeriesData = {};
  ChartBucket _timeSeriesBucket = ChartBucket.monthOfYear;
  double _totalIncome = 0;

  void _recomputeDerivedData() {
    _categoryData = _getCategoryData();
    _categoryCounts = _getCategoryCounts();
    _timeSeriesBucket = _bucketForPeriod;
    _timeSeriesData = _getTimeSeriesData();
    _totalIncome = _categoryData.values.fold(0.0, (sum, amount) => sum + amount);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      setState(() {
        _selectedCurrency = authProvider.defaultCurrency;
      });
      _loadTransactions();
    });
  }

  Future<void> _loadTransactions() async {
    setState(() => _isLoading = true);

    DateTime startDate;
    DateTime endDate = DateTime.now();

    switch (_selectedPeriod) {
      case TimePeriod.daily:
        startDate = DateTime(2020, 1, 1);
        break;
      case TimePeriod.monthly:
        startDate = DateTime(2020, 1, 1);
        break;
      case TimePeriod.yearly:
        startDate = DateTime(2020, 1, 1);
        break;
      case TimePeriod.custom:
        if (_customStartDate == null || _customEndDate == null) {
          setState(() => _isLoading = false);
          return;
        }
        startDate = _customStartDate!;
        endDate = _customEndDate!;
        break;
    }

    startDate = DateTime.utc(startDate.year, startDate.month, startDate.day);
    endDate = DateTime.utc(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    try {
      // Fetched locally (not via TransactionProvider) so this 10k-row,
      // inflow-only list never replaces the shared list Home renders.
      final transactions = await widget.transactionLoader(
        type: TransactionType.inflow,
        startDate: startDate,
        endDate: endDate,
        currency: _selectedCurrency,
        limit: 10000,
      );
      if (!mounted) return;

      setState(() {
        _filteredTransactions = transactions.where((t) {
          if (_selectedPeriod == TimePeriod.custom &&
              _customStartDate != null &&
              _customEndDate != null) {
            DateTime transDate = t.date.toLocal();
            DateTime customStart = DateTime(_customStartDate!.year, _customStartDate!.month, _customStartDate!.day);
            DateTime customEnd = DateTime(_customEndDate!.year, _customEndDate!.month, _customEndDate!.day, 23, 59, 59);
            return t.type == TransactionType.inflow &&
                transDate.isAfter(customStart.subtract(Duration(seconds: 1))) &&
                transDate.isBefore(customEnd.add(Duration(seconds: 1)));
          }
          return t.type == TransactionType.inflow;
        }).toList();
        _recomputeDerivedData();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);

      {
        final localizations = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${localizations.errorLoadingTransactions} ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Maps to the mockup's `var(--accent)` token — a lighter mint in dark
  /// mode, distinct from `--primary` (used for filled buttons). Neither
  /// light nor dark [ColorScheme] exposes this role directly, so it's
  /// derived from the theme's own accent constants.
  Color _accentColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? AppTheme.darkAccent : AppTheme.jade;

  Map<String, double> _getCategoryData() {
    Map<String, double> categoryTotals = {};

    for (var transaction in _filteredTransactions) {
      categoryTotals[transaction.mainCategory] =
          (categoryTotals[transaction.mainCategory] ?? 0) + transaction.amount;
    }

    return categoryTotals;
  }

  Map<String, int> _getCategoryCounts() {
    Map<String, int> counts = {};
    for (var transaction in _filteredTransactions) {
      counts[transaction.mainCategory] = (counts[transaction.mainCategory] ?? 0) + 1;
    }
    return counts;
  }

  /// How the bar chart groups transactions for the selected period.
  ChartBucket get _bucketForPeriod {
    switch (_selectedPeriod) {
      case TimePeriod.daily:
        return ChartBucket.dayWithWeekday;
      case TimePeriod.monthly:
        return ChartBucket.monthOfYear;
      case TimePeriod.yearly:
        return ChartBucket.year;
      case TimePeriod.custom:
        if (_customStartDate == null || _customEndDate == null) return ChartBucket.day;
        final daysDiff = _customEndDate!.difference(_customStartDate!).inDays;
        if (daysDiff <= 7) return ChartBucket.dayWithWeekday;
        if (daysDiff <= 31) return ChartBucket.day;
        if (daysDiff <= 365) return ChartBucket.month;
        return ChartBucket.year;
    }
  }

  /// Keys are [ChartBuckets] keys (in time order); labels are made from them
  /// at display time, in the app's language.
  Map<String, double> _getTimeSeriesData() => ChartBuckets.group(
        _filteredTransactions,
        _timeSeriesBucket,
        dateOfItem: (t) => t.date.toLocal(),
        amountOf: (t) => t.amount,
      );

  @override
  Widget build(BuildContext context) {
    final categoryData = _categoryData;
    final categoryCounts = _categoryCounts;
    final timeSeriesData = _timeSeriesData;
    final totalIncome = _totalIncome;
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        title: AppBarTitle(localizations.inflowAnalytics),
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Consumer<NotificationProvider>(
              builder: (context, notificationProvider, child) {
                return IconButton(
                  icon: Badge(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    textColor: Colors.white,
                    isLabelVisible: notificationProvider.unreadCount > 0,
                    label: Text(notificationProvider.unreadCount > 9 ? '9+' : '${notificationProvider.unreadCount}'),
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
        onRefresh: _loadTransactions,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 130),
          // Isolates this screen's content (the chart's custom painting in
          // particular) into its own cached GPU layer. Without this, opening
          // the drawer — which animates a scrim/slide-in as an overlay on
          // top of this same body — forces the renderer to keep re-rastering
          // everything behind it every frame, even though nothing here
          // actually changed. That's the "even opening the sidebar is slow"
          // symptom: zero extra build() calls (confirmed via logging), pure
          // raster-thread cost.
          child: RepaintBoundary(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPeriodSelector(),
              if (_selectedPeriod == TimePeriod.custom) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildDateSelector(localizations.startDate, _customStartDate, (date) {
                        setState(() => _customStartDate = date);
                        if (_customEndDate != null) _loadTransactions();
                      }),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDateSelector(localizations.endDateNoOp, _customEndDate, (date) {
                        setState(() => _customEndDate = date);
                        if (_customStartDate != null) _loadTransactions();
                      }),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                HeroCard(
                  label: '${localizations.moneyInLabel} ${_getPeriodLabel()}',
                  value: '${_selectedCurrency?.symbol ?? '\$'}${formatter.format(totalIncome)}',
                  stats: [
                    StatTile(
                      icon: Icons.receipt_long_rounded,
                      label: localizations.transactions,
                      value: '${_filteredTransactions.length}',
                    ),
                    StatTile(
                      icon: Icons.calculate_rounded,
                      label: localizations.avgPerEntry,
                      value:
                          '${_selectedCurrency?.symbol ?? '\$'}${formatter.format(_filteredTransactions.isEmpty ? 0 : totalIncome / _filteredTransactions.length)}',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (categoryData.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(localizations.incomeByCategory, style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 16),
                          ..._buildCategoryRows(categoryData, categoryCounts, totalIncome),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildCompositionInsight(categoryData, totalIncome),
                  const SizedBox(height: 16),
                ],
                if (timeSeriesData.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_getBarChartTitle(), style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 220,
                            child: BarChart(
                              // BarChartData is a plain object rebuilt fresh
                              // on every build() (no custom == ), so
                              // fl_chart's default implicit animation treats
                              // every rebuild — including the ones from just
                              // touching a bar — as "new data" and re-runs a
                              // 150ms tween. That's animation work on every
                              // interaction for a chart that never actually
                              // needs to animate between states.
                              swapAnimationDuration: Duration.zero,
                              BarChartData(
                                alignment: BarChartAlignment.spaceAround,
                                maxY: _chartAxis(timeSeriesData).maxY,
                                barTouchData: BarTouchData(
                                  touchCallback: (FlTouchEvent event, barTouchResponse) {
                                    setState(() {
                                      if (!event.isInterestedForInteractions ||
                                          barTouchResponse == null ||
                                          barTouchResponse.spot == null) {
                                        _touchedBarIndex = -1;
                                        return;
                                      }
                                      _touchedBarIndex = barTouchResponse.spot!.touchedBarGroupIndex;
                                    });
                                  },
                                  touchTooltipData: BarTouchTooltipData(
                                    getTooltipColor: (group) => scheme.primary,
                                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                      final label = ChartBuckets.tooltipLabel(timeSeriesData.keys.toList()[group.x.toInt()], _timeSeriesBucket, locale: dateLocaleOf(context));
                                      return BarTooltipItem(
                                        '$label\n${_selectedCurrency?.symbol ?? '\$'}${formatter.format(rod.toY)}',
                                        AppTheme.money(12, weight: FontWeight.w700, color: scheme.onPrimary),
                                      );
                                    },
                                  ),
                                ),
                                titlesData: FlTitlesData(
                                  show: true,
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (value, meta) {
                                        final keys = timeSeriesData.keys.toList();
                                        if (value.toInt() >= 0 && value.toInt() < keys.length) {
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 8.0),
                                            child: Text(
                                              ChartBuckets.axisLabel(keys[value.toInt()], _timeSeriesBucket, locale: dateLocaleOf(context)),
                                              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                                              textAlign: TextAlign.center,
                                            ),
                                          );
                                        }
                                        return const Text('');
                                      },
                                      reservedSize: _timeSeriesBucket == ChartBucket.dayWithWeekday ? 40 : 30,
                                    ),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      // One label per gridline, up to a round top
                                      // (see niceAxis), so labels never crowd.
                                      interval: _chartAxis(timeSeriesData).interval,
                                      getTitlesWidget: (value, meta) {
                                        // Full "K936,000.00" doesn't fit the
                                        // reserved width and wraps mid-number
                                        // ("K936,00" / "0.00"). A compact,
                                        // symbol-free label ("936K") is both
                                        // narrower and the normal convention
                                        // for repeated axis gridlines.
                                        return Text(
                                          _compactAxisLabel(value),
                                          maxLines: 1,
                                          overflow: TextOverflow.visible,
                                          style: AppTheme.money(10, weight: FontWeight.w600, color: scheme.onSurfaceVariant),
                                        );
                                      },
                                      reservedSize: 40,
                                    ),
                                  ),
                                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                ),
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  // Was a flat `50` — fine for values in the
                                  // tens/hundreds, catastrophic for money
                                  // values in the hundreds of thousands
                                  // (fl_chart tried to draw one gridline
                                  // every 50 units across a range like
                                  // 0–1,100,000: tens of thousands of
                                  // gridlines, every frame). Scaled to the
                                  // actual axis range instead, targeting
                                  // ~5 gridlines regardless of magnitude.
                                  horizontalInterval: _chartAxis(timeSeriesData).interval,
                                  getDrawingHorizontalLine: (value) {
                                    return FlLine(color: scheme.outlineVariant, strokeWidth: 1);
                                  },
                                ),
                                borderData: FlBorderData(show: false),
                                barGroups: _buildBarChartGroups(timeSeriesData),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (categoryData.isEmpty && timeSeriesData.isEmpty) _buildEmptyState(),
              ],
            ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCategoryRows(Map<String, double> data, Map<String, int> counts, double total) {
    final scheme = Theme.of(context).colorScheme;
    final categories = data.keys.toList()..sort((a, b) => data[b]!.compareTo(data[a]!));

    final accent = _accentColor(context);

    return categories.map((category) {
      final amount = data[category]!;
      final pct = total <= 0 ? 0.0 : amount / total;
      final count = counts[category] ?? 0;

      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
                  child: Icon(iconForCategoryName(category), size: 18, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // Wraps (no line limit): category names are short, and
                        // "Food & Daily Liv..." told nobody anything.
                        category,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppLocalizations.of(context).entriesCount(count),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${_selectedCurrency?.symbol ?? '\$'}${formatter.format(amount)}',
                      style: AppTheme.money(14, weight: FontWeight.w700, color: scheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(pct * 100).toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ProgressMeter(value: pct, overrideColor: accent),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildCompositionInsight(Map<String, double> data, double total) {
    if (data.isEmpty || total <= 0) return const SizedBox.shrink();
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final sorted = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.first;
    final pct = (top.value / total) * 100;

    return Card(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.lightbulb_rounded, size: 20, color: scheme.tertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${top.key} ${localizations.biggestIncomeSourceMiddle} ${pct.toStringAsFixed(0)}% ${localizations.biggestIncomeSourceSuffix}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onTertiaryContainer, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(Icons.analytics_rounded, size: 40, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 20),
            Text(
              localizations.noDataAvailable,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              localizations.addIncomeSeeAnalytics,
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    final localizations = AppLocalizations.of(context);
    // The period buttons stay one row (scrolling sideways when a language's
    // labels don't fit); the currency menu has its own line below, rather
    // than sharing the row and pushing "Custom" onto a second line.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _segmentedRow([
            _Segment(localizations.daily, TimePeriod.daily == _selectedPeriod, () => _selectPeriod(TimePeriod.daily)),
            _Segment(localizations.monthly, TimePeriod.monthly == _selectedPeriod, () => _selectPeriod(TimePeriod.monthly)),
            _Segment(localizations.yearly, TimePeriod.yearly == _selectedPeriod, () => _selectPeriod(TimePeriod.yearly)),
            _Segment(localizations.custom, TimePeriod.custom == _selectedPeriod, () => _selectPeriod(TimePeriod.custom)),
        ]),
        const SizedBox(height: 10),
        _currencyFilterChip(),
      ],
    );
  }

  // One dropdown chip for currency, rather than a whole separate labeled row
  // of per-currency choice chips underneath the period selector.
  Widget _currencyFilterChip() {
    final scheme = Theme.of(context).colorScheme;
    final currency = _selectedCurrency ?? Currency.usd;
    final label = '${currency.symbol} ${currency.name.toUpperCase()}';

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
            Icon(Icons.currency_exchange_rounded, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface)),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  void _pickCurrencyFilter() {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(localizations.currency, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final currency in Currency.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${currency.symbol} ${currency.name.toUpperCase()} · ${currency.displayName}'),
              trailing: _selectedCurrency == currency
                  ? Icon(Icons.check_circle_rounded, color: scheme.primary)
                  : null,
              onTap: () {
                setState(() => _selectedCurrency = currency);
                Navigator.pop(sheetContext);
                _loadTransactions();
              },
            ),
        ],
      ),
    );
  }

  void _selectPeriod(TimePeriod period) {
    final previousPeriod = _selectedPeriod;
    setState(() => _selectedPeriod = period);
    if (period == TimePeriod.custom) return; // wait for a date range to be picked

    // Daily, Monthly and Yearly all fetch the exact same 2020-to-now range
    // (see _loadTransactions), so switching between them was re-fetching up
    // to 10,000 transactions from the network for data already sitting in
    // memory — that round trip on every tab tap is what made the screen
    // feel slow. Only Custom uses a different range, so only refetch when
    // there's no data yet or we're arriving from Custom; otherwise just
    // re-bucket the transactions already loaded.
    if (_filteredTransactions.isEmpty || previousPeriod == TimePeriod.custom) {
      _loadTransactions();
    } else {
      setState(_recomputeDerivedData);
    }
  }

  // Mockup renders period/currency filters as a row of discrete pills —
  // filled primary when selected, outlined otherwise (see "Inflow
  // analytics" markup, lines 602-606 of the prototype) — not a single
  // grouped, equal-width segmented track. One row that scrolls sideways
  // (with room after the last pill) when longer localized labels don't fit.
  Widget _segmentedRow(List<_Segment> segments) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Row(
        children: [
          for (final (i, s) in segments.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            GestureDetector(
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
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDateSelector(String label, DateTime? date, Function(DateTime) onDateSelected) {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () async {
        // A preset range can end after today (e.g. end of this month).
        final bounds = DatePickerBounds.clamped(
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        final picked = await showDatePicker(
          context: context,
          initialDate: bounds.initialDate,
          firstDate: bounds.firstDate,
          lastDate: bounds.lastDate,
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
                date != null ? AppDates.full(context, date) : localizations.select,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ChartAxis _chartAxis(Map<String, double> data) =>
      niceAxis(data.isEmpty ? 0 : data.values.reduce((a, b) => a > b ? a : b));

  String _compactAxisLabel(double value) {
    if (value == 0) return '0';
    return NumberFormat.compact().format(value);
  }

  List<BarChartGroupData> _buildBarChartGroups(Map<String, double> data) {
    final scheme = Theme.of(context).colorScheme;
    List<String> keys = data.keys.toList();
    // Mockup's "Six months in" bars are muted (var(--s-container)) except
    // the most recent/highest bar, which is highlighted in var(--accent).
    final peakValue = data.values.isEmpty ? 0.0 : data.values.reduce((a, b) => a > b ? a : b);

    return List.generate(keys.length, (i) {
      final isTouched = i == _touchedBarIndex;
      final isPeak = data[keys[i]] == peakValue;

      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: data[keys[i]]!,
            color: isPeak ? _accentColor(context) : scheme.secondaryContainer,
            width: isTouched ? 18 : 16,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      );
    });
  }

  String _getPeriodLabel() {
    final localizations = AppLocalizations.of(context);
    switch (_selectedPeriod) {
      case TimePeriod.daily:
        return localizations.byDayOfWeek;
      case TimePeriod.monthly:
        return localizations.byMonth;
      case TimePeriod.yearly:
        return localizations.byYear;
      case TimePeriod.custom:
        if (_customStartDate != null && _customEndDate != null) {
          return AppDates.range(context, _customStartDate!, _customEndDate!);
        }
        return localizations.customPeriod;
    }
  }

  String _getBarChartTitle() {
    final localizations = AppLocalizations.of(context);
    switch (_selectedPeriod) {
      case TimePeriod.daily:
        return localizations.incomeDayOfWeek;
      case TimePeriod.monthly:
        return localizations.incomeByMonth;
      case TimePeriod.yearly:
        return localizations.incomeByYear;
      case TimePeriod.custom:
        return localizations.incomeOverTime;
    }
  }
}

class _Segment {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  _Segment(this.label, this.selected, this.onTap);
}
