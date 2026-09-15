import 'package:flutter/material.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:frontend/widgets/hero_card.dart';
import 'package:frontend/widgets/stat_tile.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/transaction_provider.dart';
import '../../models/transaction.dart';
import '../../services/localization_service.dart';
import '../../widgets/app_drawer.dart';

enum TimePeriod { daily, monthly, yearly, custom }

class OutflowAnalyticsScreen extends StatefulWidget {
  @override
  _OutflowAnalyticsScreenState createState() => _OutflowAnalyticsScreenState();
}

class _OutflowAnalyticsScreenState extends State<OutflowAnalyticsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  TimePeriod _selectedPeriod = TimePeriod.monthly;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  List<Transaction> _filteredTransactions = [];
  int _touchedPieIndex = -1;
  int _touchedBarIndex = -1;
  bool _isLoading = false;
  final formatter = NumberFormat("#,##0.00", "en_US");

  Currency? _selectedCurrency;

  // Derived from _filteredTransactions, but only recomputed when that list
  // actually changes (see _recomputeDerivedData) rather than on every
  // build() — build() used to call _getCategoryData/_getTimeSeriesData
  // directly, which re-walks every fetched transaction (up to 10,000) on
  // every rebuild, including the ones triggered just by tapping a donut
  // slice or bar to show its tooltip. That's what made the screen feel slow
  // while interacting with the charts.
  Map<String, double> _categoryData = {};
  Map<String, double> _timeSeriesData = {};
  double _totalSpending = 0;

  void _recomputeDerivedData() {
    _categoryData = _getCategoryData();
    _timeSeriesData = _getTimeSeriesData();
    _totalSpending = _categoryData.values.fold(0.0, (sum, amount) => sum + amount);
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
        type: TransactionType.outflow,
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
            return t.type == TransactionType.outflow &&
                transDate.isAfter(customStart.subtract(Duration(seconds: 1))) &&
                transDate.isBefore(customEnd.add(Duration(seconds: 1)));
          }
          return t.type == TransactionType.outflow;
        }).toList();
        _recomputeDerivedData();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading transactions: ${e.toString()}'),
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

  // Largest category first — donut slices, legend rows and the composition
  // insight all iterate this same map in insertion order, so sorting once
  // here keeps them all consistent with each other and with the mockup's
  // largest-first legend, instead of showing categories in whatever order
  // their first transaction happened to be fetched.
  Map<String, double> _getCategoryData() {
    Map<String, double> categoryTotals = {};

    for (var transaction in _filteredTransactions) {
      categoryTotals[transaction.mainCategory] =
          (categoryTotals[transaction.mainCategory] ?? 0) + transaction.amount;
    }

    final sortedEntries = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sortedEntries);
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
        final monthOrder = ['January', 'February', 'March', 'April', 'May', 'June',
          'July', 'August', 'September', 'October', 'November', 'December'];
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
    final timeSeriesData = _timeSeriesData;
    final totalSpending = _totalSpending;
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        title: Text(localizations.outflowAnalytics),
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
          // See inflow_analytics_screen.dart for why — isolates the chart's
          // custom painting into its own cached GPU layer so opening the
          // drawer (an overlay animation on top of this body) doesn't force
          // a re-raster of everything behind it every frame.
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
                  label: 'Money out · ${_getPeriodLabel()}',
                  value: '${_selectedCurrency?.symbol ?? '\$'}${formatter.format(totalSpending)}',
                  stats: [
                    StatTile(
                      icon: Icons.receipt_long_rounded,
                      label: localizations.transactions,
                      value: '${_filteredTransactions.length}',
                    ),
                    StatTile(
                      icon: Icons.calculate_rounded,
                      label: 'Avg / entry',
                      value:
                          '${_selectedCurrency?.symbol ?? '\$'}${formatter.format(_filteredTransactions.isEmpty ? 0 : totalSpending / _filteredTransactions.length)}',
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  localizations.spendingByCategory,
                                  style: Theme.of(context).textTheme.titleMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _getPeriodLabel(),
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _accentColor(context)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 130,
                                height: 130,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    PieChart(
                                      // See BarChart below — PieChartData is
                                      // rebuilt fresh every build(), so the
                                      // default implicit animation re-runs a
                                      // tween on every touch/rebuild for a
                                      // chart that never needs to animate.
                                      swapAnimationDuration: Duration.zero,
                                      PieChartData(
                                        pieTouchData: PieTouchData(
                                          touchCallback: (FlTouchEvent event, pieTouchResponse) {
                                            setState(() {
                                              if (!event.isInterestedForInteractions ||
                                                  pieTouchResponse == null ||
                                                  pieTouchResponse.touchedSection == null) {
                                                _touchedPieIndex = -1;
                                                return;
                                              }
                                              _touchedPieIndex =
                                                  pieTouchResponse.touchedSection!.touchedSectionIndex;
                                            });
                                          },
                                        ),
                                        sectionsSpace: 2,
                                        // centerSpaceRadius (40) + slice
                                        // radius (up to 58 touched) drew a
                                        // donut up to 196dp across inside a
                                        // 130x130 box — it overflowed the
                                        // box and bled into the title above.
                                        // Shrunk to fit: max outer radius 65
                                        // (touched) still fits the 130 box.
                                        centerSpaceRadius: 34,
                                        sections: _buildPieChartSections(categoryData, totalSpending),
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _compactAmount(totalSpending),
                                          style: AppTheme.money(15, weight: FontWeight.w800, color: scheme.onSurface),
                                        ),
                                        Text(
                                          'spent',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 18),
                              Expanded(child: _buildLegend(categoryData, totalSpending)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildCompositionInsight(categoryData, totalSpending),
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

  Widget _buildCompositionInsight(Map<String, double> data, double total) {
    if (data.isEmpty || total <= 0) return const SizedBox.shrink();
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
                '${top.key} is your biggest outflow category — ${pct.toStringAsFixed(0)}% of spending this period.',
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
              localizations.addTransactionsSeeSpendingAnalytics,
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
  // filled primary when selected, outlined otherwise (see "Outflow
  // analytics" markup, lines 407-411 of the prototype) — not a single
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

  List<PieChartSectionData> _buildPieChartSections(Map<String, double> data, double total) {
    final categories = data.keys.toList();
    final colors = AppTheme.chartRampFor(context);

    return List.generate(categories.length, (i) {
      final isTouched = i == _touchedPieIndex;
      // Paired with centerSpaceRadius: 34 above — outer radius tops out at
      // 65 (34+31) even touched, fitting the 130x130 box exactly.
      final double radius = isTouched ? 31.0 : 28.0;

      return PieChartSectionData(
        color: colors[i % colors.length],
        value: data[categories[i]],
        title: '',
        radius: radius,
      );
    });
  }

  Widget _buildLegend(Map<String, double> data, double total) {
    final categories = data.keys.toList();
    final colors = AppTheme.chartRampFor(context);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(categories.length, (i) {
        final percentage = total <= 0 ? 0.0 : (data[categories[i]]! / total) * 100;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.5),
          child: Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[i % colors.length], borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  categories[i],
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${percentage.toStringAsFixed(0)}%',
                style: AppTheme.money(13, weight: FontWeight.w700, color: scheme.onSurface),
              ),
            ],
          ),
        );
      }),
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
    // Mockup's "Daily spend" bars are muted (var(--s-container)) except the
    // single peak day, which is highlighted in var(--accent).
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

  String _compactAmount(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
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
        return localizations.spendingDayOfWeek;
      case TimePeriod.monthly:
        return localizations.spendingMonth;
      case TimePeriod.yearly:
        return localizations.spendingYear;
      case TimePeriod.custom:
        return localizations.spendingOverTime;
    }
  }
}

class _Segment {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  _Segment(this.label, this.selected, this.onTap);
}
