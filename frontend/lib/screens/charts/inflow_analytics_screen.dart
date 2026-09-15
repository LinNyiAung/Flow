import 'package:flutter/material.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/category_icons.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:frontend/widgets/hero_card.dart';
import 'package:frontend/widgets/progress_meter.dart';
import 'package:frontend/widgets/stat_tile.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/transaction_provider.dart';
import '../../models/transaction.dart';
import '../../services/localization_service.dart';
import '../../widgets/app_drawer.dart';

enum TimePeriod { daily, monthly, yearly, custom }

class InflowAnalyticsScreen extends StatefulWidget {
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
  double _totalIncome = 0;

  void _recomputeDerivedData() {
    _categoryData = _getCategoryData();
    _categoryCounts = _getCategoryCounts();
    _timeSeriesData = _getTimeSeriesData();
    _totalIncome = _categoryData.values.fold(0.0, (sum, amount) => sum + amount);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      setState(() {
        _selectedCurrency = authProvider.defaultCurrency;
      });
      _loadTransactions();
    });
  }

  Future<void> _loadTransactions() async {
    setState(() => _isLoading = true);

    final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);

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
      await transactionProvider.fetchTransactions(
        type: TransactionType.inflow,
        startDate: startDate,
        endDate: endDate,
        currency: _selectedCurrency,
        limit: 10000,
      );

      setState(() {
        _filteredTransactions = transactionProvider.transactions.where((t) {
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
      setState(() => _isLoading = false);

      if (mounted) {
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

  Map<String, double> _getTimeSeriesData() {
    Map<String, double> timeSeries = {};

    for (var transaction in _filteredTransactions) {
      String key = '';

      switch (_selectedPeriod) {
        case TimePeriod.daily:
          DateTime localDate = transaction.date.toLocal();
          String dayName = DateFormat('EEEE').format(localDate);
          String dateStr = DateFormat('MMM d').format(localDate);
          key = '$dayName ($dateStr)';
          break;
        case TimePeriod.monthly:
          key = DateFormat('MMMM').format(transaction.date.toLocal());
          break;
        case TimePeriod.yearly:
          key = DateFormat('yyyy').format(transaction.date.toLocal());
          break;
        case TimePeriod.custom:
          if (_customStartDate == null || _customEndDate == null) {
            key = DateFormat('MMM d, yyyy').format(transaction.date.toLocal());
            break;
          }
          int daysDiff = _customEndDate!.difference(_customStartDate!).inDays;
          if (daysDiff <= 7) {
            key = DateFormat('EEE, MMM d').format(transaction.date.toLocal());
          } else if (daysDiff <= 31) {
            key = DateFormat('MMM d').format(transaction.date.toLocal());
          } else if (daysDiff <= 365) {
            key = DateFormat('MMM yyyy').format(transaction.date.toLocal());
          } else {
            key = DateFormat('yyyy').format(transaction.date.toLocal());
          }
          break;
      }

      if (key.isNotEmpty) {
        timeSeries[key] = (timeSeries[key] ?? 0) + transaction.amount;
      }
    }

    return _sortTimeSeriesData(timeSeries);
  }

  Map<String, double> _sortTimeSeriesData(Map<String, double> data) {
    List<MapEntry<String, double>> entries = data.entries.toList();
    final localizations = AppLocalizations.of(context);

    switch (_selectedPeriod) {
      case TimePeriod.daily:
        entries.sort((a, b) {
          RegExp datePattern = RegExp(r'\(([^)]+)\)');
          String? dateStrA = datePattern.firstMatch(a.key)?.group(1);
          String? dateStrB = datePattern.firstMatch(b.key)?.group(1);

          if (dateStrA != null && dateStrB != null) {
            try {
              DateTime dateA = DateFormat('MMM d').parse('$dateStrA, ${DateTime.now().year}');
              DateTime dateB = DateFormat('MMM d').parse('$dateStrB, ${DateTime.now().year}');
              return dateA.compareTo(dateB);
            } catch (e) {
              return 0;
            }
          }
          return 0;
        });
        break;
      case TimePeriod.monthly:
        final monthOrder = [
          localizations.monthJanuary, localizations.monthFebruary, localizations.monthMarch,
          localizations.monthApril, localizations.monthMay, localizations.monthJune,
          localizations.monthJuly, localizations.monthAugust, localizations.monthSeptember,
          localizations.monthOctober, localizations.monthNovember, localizations.monthDecember,
        ];
        entries.sort((a, b) => monthOrder.indexOf(a.key).compareTo(monthOrder.indexOf(b.key)));
        break;
      case TimePeriod.yearly:
        entries.sort((a, b) => a.key.compareTo(b.key));
        break;
      case TimePeriod.custom:
        break;
    }

    return Map.fromEntries(entries);
  }

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
        title: Text(localizations.inflowAnalytics),
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
                                maxY: _chartMaxY(timeSeriesData),
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
                                      String label = timeSeriesData.keys.toList()[group.x.toInt()];
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
                                        List<String> keys = timeSeriesData.keys.toList();
                                        if (value.toInt() >= 0 && value.toInt() < keys.length) {
                                          String label = keys[value.toInt()];
                                          if (_selectedPeriod == TimePeriod.daily) {
                                            RegExp pattern = RegExp(r'(\w+)\s+\(([^)]+)\)');
                                            Match? match = pattern.firstMatch(label);
                                            if (match != null) {
                                              String dayName = match.group(1)!.substring(0, 3);
                                              String date = match.group(2)!;
                                              return Padding(
                                                padding: const EdgeInsets.only(top: 8.0),
                                                child: Text(
                                                  '$dayName\n$date',
                                                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                                                  textAlign: TextAlign.center,
                                                ),
                                              );
                                            }
                                          } else if (_selectedPeriod == TimePeriod.monthly) {
                                            label = label.substring(0, 3);
                                          }
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 8.0),
                                            child: Text(label, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                                          );
                                        }
                                        return const Text('');
                                      },
                                      reservedSize: _selectedPeriod == TimePeriod.daily ? 40 : 30,
                                    ),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
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
                                  horizontalInterval: _chartMaxY(timeSeriesData) / 5,
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
                        category,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        count == 1 ? '1 entry' : '$count entries',
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
    return Row(
      children: [
        Expanded(
          child: _segmentedRow([
            _Segment(localizations.daily, TimePeriod.daily == _selectedPeriod, () => _selectPeriod(TimePeriod.daily)),
            _Segment(localizations.monthly, TimePeriod.monthly == _selectedPeriod, () => _selectPeriod(TimePeriod.monthly)),
            _Segment(localizations.yearly, TimePeriod.yearly == _selectedPeriod, () => _selectPeriod(TimePeriod.yearly)),
            _Segment(localizations.custom, TimePeriod.custom == _selectedPeriod, () => _selectPeriod(TimePeriod.custom)),
          ]),
        ),
        const SizedBox(width: 8),
        _currencyFilterChip(),
      ],
    );
  }

  // One dropdown chip for currency, rather than a whole separate labeled row
  // of per-currency choice chips underneath the period selector.
  Widget _currencyFilterChip() {
    final scheme = Theme.of(context).colorScheme;
    final label = _selectedCurrency?.symbol ?? Currency.usd.symbol;

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
  // grouped, equal-width segmented track. Wrap (rather than Row) keeps
  // longer localized labels from overflowing on narrow screens.
  Widget _segmentedRow(List<_Segment> segments) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: segments.map((s) {
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
      }).toList(),
    );
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

  double _chartMaxY(Map<String, double> data) {
    if (data.isEmpty) return 100;
    final peak = data.values.reduce((a, b) => a > b ? a : b);
    return peak <= 0 ? 100 : peak * 1.2;
  }

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
          return '${DateFormat('MMM d').format(_customStartDate!)} - ${DateFormat('MMM d, yyyy').format(_customEndDate!)}';
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
