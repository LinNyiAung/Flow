import 'package:flutter/material.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/transaction_provider.dart';
import '../../models/transaction.dart';
import '../../services/localization_service.dart';
import '../../widgets/app_drawer.dart';
import 'package:frontend/services/responsive_helper.dart';

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

  Currency? _selectedCurrency;

@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // Set default currency from user's preference
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    setState(() {
      _selectedCurrency = authProvider.defaultCurrency;
    });
    _loadTransactions();
  });
}

Future<void> _loadBalance() async {
  final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
  await transactionProvider.fetchBalance(currency: _selectedCurrency);
}

  Future<void> _loadTransactions() async {
    setState(() => _isLoading = true);

    final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);

    DateTime startDate;
    DateTime endDate = DateTime.now();

    switch (_selectedPeriod) {
      case TimePeriod.daily:
      // Get all transactions from the beginning to analyze by day of week
        startDate = DateTime(2020, 1, 1);
        break;
      case TimePeriod.monthly:
      // Get all transactions to analyze by month
        startDate = DateTime(2020, 1, 1);
        break;
      case TimePeriod.yearly:
      // Get all transactions to analyze by year
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

    // Ensure dates are in UTC to match backend expectations
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
        _filteredTransactions = transactionProvider.transactions
            .where((t) {
          // Additional filtering for custom period to ensure transactions are within range
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
        })
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading transactions: $e');
      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading transactions: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Map<String, double> _getCategoryData() {
    Map<String, double> categoryTotals = {};

    for (var transaction in _filteredTransactions) {
      if (categoryTotals.containsKey(transaction.mainCategory)) {
        categoryTotals[transaction.mainCategory] =
            categoryTotals[transaction.mainCategory]! + transaction.amount;
      } else {
        categoryTotals[transaction.mainCategory] = transaction.amount;
      }
    }

    return categoryTotals;
  }

  Map<String, double> _getTimeSeriesData() {
    Map<String, double> timeSeries = {};

    for (var transaction in _filteredTransactions) {
      String key = '';

      switch (_selectedPeriod) {
        case TimePeriod.daily:
        // Group by day of week with date (e.g., "Monday (Oct 7)")
          DateTime localDate = transaction.date.toLocal();
          String dayName = DateFormat('EEEE').format(localDate);
          String dateStr = DateFormat('MMM d').format(localDate);
          key = '$dayName ($dateStr)';
          break;
        case TimePeriod.monthly:
        // Group by month (January, February, etc.)
          key = DateFormat('MMMM').format(transaction.date.toLocal());
          break;
        case TimePeriod.yearly:
        // Group by year (2024, 2025, etc.)
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
        if (timeSeries.containsKey(key)) {
          timeSeries[key] = timeSeries[key]! + transaction.amount;
        } else {
          timeSeries[key] = transaction.amount;
        }
      }
    }

    // Sort the data appropriately
    return _sortTimeSeriesData(timeSeries);
  }

  Map<String, double> _sortTimeSeriesData(Map<String, double> data) {
    List<MapEntry<String, double>> entries = data.entries.toList();

    switch (_selectedPeriod) {
      case TimePeriod.daily:
      // Sort by actual date for daily view (since we now have dates in the key)
        entries.sort((a, b) {
          // Extract dates from keys like "Monday (Oct 7)"
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
      // Sort by month (January to December)
        final monthOrder = ['January', 'February', 'March', 'April', 'May', 'June',
          'July', 'August', 'September', 'October', 'November', 'December'];
        entries.sort((a, b) => monthOrder.indexOf(a.key).compareTo(monthOrder.indexOf(b.key)));
        break;
      case TimePeriod.yearly:
      // Sort by year (ascending)
        entries.sort((a, b) => a.key.compareTo(b.key));
        break;
      case TimePeriod.custom:
      // Keep original order for custom
        break;
    }

    return Map.fromEntries(entries);
  }

  Color _getColorForIndex(int index) {
    List<Color> colors = [
      Color(0xFF667eea),
      Color(0xFF764ba2),
      Color(0xFF4CAF50),
      Color(0xFFFF5722),
      Color(0xFF2196F3),
      Color(0xFFFFC107),
      Color(0xFF9C27B0),
      Color(0xFFFF9800),
      Color(0xFF00BCD4),
      Color(0xFFE91E63),
    ];
    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final categoryData = _getCategoryData();
    final timeSeriesData = _getTimeSeriesData();
    final totalSpending = categoryData.values.fold(0.0, (sum, amount) => sum + amount);
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      drawerEnableOpenDragGesture: true,  
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        title: Text(
          localizations.outflowAnalytics,
          style: GoogleFonts.poppins(
            fontSize: responsive.fs20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.menu),
          color: Color(0xFF333333),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          // Notification Icon with Badge
          Padding(
            padding: responsive.padding(right: 16),
            child: Consumer<NotificationProvider>(
              builder: (context, notificationProvider, child) {
                return Stack(
                  children: [
                    Container(
                      padding: responsive.padding(all: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            spreadRadius: 1,
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.notifications_outlined,
                          color: Color(0xFF667eea),
                        ),
                        onPressed: () {
                          Navigator.pushNamed(context, '/notifications').then((
                            _,
                          ) {
                            // Refresh data when returning from notifications
                            notificationProvider.fetchUnreadCount();
                          });
                        },
                      ),
                    ),
                    if (notificationProvider.unreadCount > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: responsive.padding(all: 4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: BoxConstraints(
                            minWidth: 20,
                            minHeight: 20,
                          ),
                          child: Text(
                            '${notificationProvider.unreadCount > 9 ? '9+' : notificationProvider.unreadCount}',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: responsive.fs10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF667eea).withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _loadTransactions,
          color: Color(0xFF667eea),
          child: SingleChildScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                SizedBox(height: responsive.sp20),

                // Period Selector
                Padding(
                  padding: responsive.padding(horizontal: 20),
                  child: Container(
                    padding: responsive.padding(all: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        _buildPeriodButton(localizations.daily, TimePeriod.daily),
                        _buildPeriodButton(localizations.monthly, TimePeriod.monthly),
                        _buildPeriodButton(localizations.yearly, TimePeriod.yearly),
                        _buildPeriodButton(localizations.custom, TimePeriod.custom),
                      ],
                    ),
                  ),
                ),

                if (_selectedPeriod == TimePeriod.custom)
                  Padding(
                    padding: responsive.padding(all: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildDateSelector(
                            localizations.startDate,
                            _customStartDate,
                                (date) {
                              setState(() => _customStartDate = date);
                              if (_customEndDate != null) _loadTransactions();
                            },
                          ),
                        ),
                        SizedBox(width: responsive.sp12),
                        Expanded(
                          child: _buildDateSelector(
                            localizations.endDateNoOp,
                            _customEndDate,
                                (date) {
                              setState(() => _customEndDate = date);
                              if (_customStartDate != null) _loadTransactions();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: responsive.sp20),

                  // ADD THIS CURRENCY FILTER SECTION HERE
              Padding(
                padding: responsive.padding(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.currency,
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF333333),
                      ),
                    ),
                    SizedBox(height: responsive.sp12),
                    Container(
                      padding: responsive.padding(all: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            spreadRadius: 1,
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Row(
                        children: Currency.values.map((currency) {
                          return _buildCurrencyFilterButton(
                            currency.symbol,
                            currency,
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),

                SizedBox(height: responsive.sp20),

                // Loading Indicator
                if (_isLoading)
                  Container(
                    height: 300,
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
                      ),
                    ),
                  )
                else ...[
                  // Total Spending Card
                  Padding(
                    padding: responsive.padding(horizontal: 20),
                    child: Container(
                      width: double.infinity,
                      padding: responsive.padding(all: 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                        ),
                        borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFF667eea).withOpacity(0.3),
                            spreadRadius: 2,
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            localizations.totalSpending,
                            style: GoogleFonts.poppins(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: responsive.fs14,
                            ),
                          ),
                          SizedBox(height: responsive.sp8),
                          Text(
                            '${_selectedCurrency?.symbol ?? '\$'}${totalSpending.toStringAsFixed(2)}',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: responsive.fs32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _getPeriodLabel(),
                            style: GoogleFonts.poppins(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: responsive.fs12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: responsive.sp30),

                  // Pie Chart Section
                  if (categoryData.isNotEmpty) ...[
                    Padding(
                      padding: responsive.padding(horizontal: 20),
                      child: Row(
                        children: [
                          Icon(Icons.pie_chart, color: Color(0xFF667eea), size: responsive.icon24),
                          SizedBox(width: responsive.sp8),
                          Text(
                            localizations.spendingByCategory,
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF333333),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: responsive.sp16),
                    Container(
                      margin: responsive.padding(horizontal: 20),
                      padding: responsive.padding(all: 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            spreadRadius: 2,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 300,
                            child: PieChart(
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
                                      _touchedPieIndex = pieTouchResponse
                                          .touchedSection!.touchedSectionIndex;
                                    });
                                  },
                                ),
                                sectionsSpace: 2,
                                centerSpaceRadius: 50,
                                sections: _buildPieChartSections(categoryData, totalSpending),
                              ),
                            ),
                          ),
                          SizedBox(height: responsive.sp20),
                          _buildLegend(categoryData, totalSpending),
                        ],
                      ),
                    ),
                    SizedBox(height: responsive.sp30),
                  ],

                  // Bar Chart Section
                  if (timeSeriesData.isNotEmpty) ...[
                    Padding(
                      padding: responsive.padding(horizontal: 20),
                      child: Row(
                        children: [
                          Icon(Icons.bar_chart, color: Color(0xFF667eea), size: responsive.icon24),
                          SizedBox(width: responsive.sp8),
                          Expanded(
                            child: Text(
                              _getBarChartTitle(),
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF333333),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: responsive.sp16),
                    Container(
                      margin: responsive.padding(horizontal: 20),
                      padding: responsive.padding(all: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            spreadRadius: 2,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: SizedBox(
                        height: 300,
                        child: BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            maxY: timeSeriesData.values.reduce((a, b) => a > b ? a : b) * 1.2,
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
                                getTooltipColor: (group) => Color(0xFF667eea),
                                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                  String label = timeSeriesData.keys.toList()[group.x.toInt()];
                                  return BarTooltipItem(
                                    '$label\n${_selectedCurrency?.symbol ?? '\$'}${rod.toY.toStringAsFixed(2)}',
                                    GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: responsive.fs12,
                                    ),
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
                                      // Shorten labels for better fit
                                      if (_selectedPeriod == TimePeriod.daily) {
                                        // For daily, extract day name and show only first 3 letters
                                        // e.g., "Monday (Oct 7)" -> "Mon\nOct 7"
                                        RegExp pattern = RegExp(r'(\w+)\s+\(([^)]+)\)');
                                        Match? match = pattern.firstMatch(label);
                                        if (match != null) {
                                          String dayName = match.group(1)!.substring(0, 3);
                                          String date = match.group(2)!;
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 8.0),
                                            child: Text(
                                              '$dayName\n$date',
                                              style: GoogleFonts.poppins(
                                                fontSize: responsive.fs10,
                                                color: Colors.grey[600],
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          );
                                        }
                                      } else if (_selectedPeriod == TimePeriod.monthly) {
                                        label = label.substring(0, 3); // Jan, Feb, etc.
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 8.0),
                                        child: Text(
                                          label,
                                          style: GoogleFonts.poppins(
                                            fontSize: responsive.fs10,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      );
                                    }
                                    return Text('');
                                  },
                                  reservedSize: _selectedPeriod == TimePeriod.daily ? 40 : 30,
                                ),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    return Text(
                                      '${_selectedCurrency?.symbol ?? '\$'}${value.toInt()}',
                                      style: GoogleFonts.poppins(
                                        fontSize: responsive.fs10,
                                        color: Colors.grey[600],
                                      ),
                                    );
                                  },
                                  reservedSize: 40,
                                ),
                              ),
                              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: 50,
                              getDrawingHorizontalLine: (value) {
                                return FlLine(
                                  color: Colors.grey.withOpacity(0.1),
                                  strokeWidth: 1,
                                );
                              },
                            ),
                            borderData: FlBorderData(show: false),
                            barGroups: _buildBarChartGroups(timeSeriesData),
                          ),
                        ),
                      ),
                    ),
                  ],

                  // Empty State
                  if (categoryData.isEmpty && timeSeriesData.isEmpty)
                    Container(
                      padding: EdgeInsets.all(40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: responsive.padding(all: 24),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                              ),
                              borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
                            ),
                            child: Icon(Icons.analytics, size: 48, color: Colors.white),
                          ),
                          SizedBox(height: responsive.sp24),
                          Text(
                            localizations.noDataAvailable,
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs18,
                              color: Color(0xFF333333),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: responsive.sp8),
                          Text(
                            localizations.addTransactionsSeeSpendingAnalytics,
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs14,
                              color: Colors.grey[500],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                ],

                SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildCurrencyFilterButton(String label, Currency currency) {
  bool isSelected = _selectedCurrency == currency;
  final responsive = ResponsiveHelper(context);
  return Expanded(
    child: GestureDetector(
      onTap: () {
        setState(() => _selectedCurrency = currency);
        _loadTransactions();
      },
      child: Container(
        padding: responsive.padding(vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(colors: [Color(0xFF667eea), Color(0xFF764ba2)])
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: responsive.fs12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.grey[600],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildPeriodButton(String label, TimePeriod period) {
    bool isSelected = _selectedPeriod == period;
    final responsive = ResponsiveHelper(context);
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedPeriod = period);
          if (period != TimePeriod.custom) {
            _loadTransactions();
          }
        },
        child: Container(
          padding: responsive.padding(vertical: 10),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(colors: [Color(0xFF667eea), Color(0xFF764ba2)])
                : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: responsive.fs12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? Colors.white : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelector(String label, DateTime? date, Function(DateTime) onDateSelected) {
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.light(primary: Color(0xFF667eea)),
              ),
              child: child!,
            );
          },
        );
        if (picked != null) onDateSelected(picked);
      },
      child: Container(
        padding: responsive.padding(all: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(fontSize: responsive.fs10, color: Colors.grey[600]),
            ),
            SizedBox(height: responsive.sp4),
            Text(
              date != null ? DateFormat('MMM d, yyyy').format(date) : localizations.select,
              style: GoogleFonts.poppins(fontSize: responsive.fs14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  List<PieChartSectionData> _buildPieChartSections(Map<String, double> data, double total) {
    List<String> categories = data.keys.toList();

    return List.generate(categories.length, (i) {
      final isTouched = i == _touchedPieIndex;
      final double radius = isTouched ? 110.0 : 100.0;
      final double fontSize = isTouched ? 14.0 : 12.0;

      double percentage = (data[categories[i]]! / total) * 100;

      return PieChartSectionData(
        color: _getColorForIndex(i),
        value: data[categories[i]],
        title: '${percentage.toStringAsFixed(1)}%',
        radius: radius,
        titleStyle: GoogleFonts.poppins(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    });
  }

  Widget _buildLegend(Map<String, double> data, double total) {
    List<String> categories = data.keys.toList();
    final responsive = ResponsiveHelper(context);

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: List.generate(categories.length, (i) {
        double percentage = (data[categories[i]]! / total) * 100;
        return Container(
          padding: responsive.padding(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _getColorForIndex(i).withOpacity(0.1),
            borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _getColorForIndex(i),
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 6),
              Text(
                '${categories[i]} (${percentage.toStringAsFixed(1)}%)',
                style: GoogleFonts.poppins(
                  fontSize: responsive.fs11,
                  color: Color(0xFF333333),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  List<BarChartGroupData> _buildBarChartGroups(Map<String, double> data) {
    List<String> keys = data.keys.toList();
    final responsive = ResponsiveHelper(context);

    return List.generate(keys.length, (i) {
      final isTouched = i == _touchedBarIndex;

      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: data[keys[i]]!,
            gradient: LinearGradient(
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
            ),
            width: isTouched ? 18 : 16,
            borderRadius: BorderRadius.circular(responsive.borderRadius(4)),
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