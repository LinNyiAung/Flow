// NOTE: You need to add fl_chart to pubspec.yaml:
// dependencies:
//   fl_chart: ^0.68.0

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/transaction_provider.dart';
import '../../models/transaction.dart';
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
  int _touchedPieIndex = -1;
  int _touchedBarIndex = -1;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
        type: TransactionType.inflow,
        startDate: startDate,
        endDate: endDate,
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
            return t.type == TransactionType.inflow &&
                transDate.isAfter(customStart.subtract(Duration(seconds: 1))) &&
                transDate.isBefore(customEnd.add(Duration(seconds: 1)));
          }
          return t.type == TransactionType.inflow;
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
    final totalIncome = categoryData.values.fold(0.0, (sum, amount) => sum + amount);

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      appBar: AppBar(
        title: Text(
          'Inflow Analytics',
          style: GoogleFonts.poppins(
            fontSize: 20,
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
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Icon(Icons.bar_chart, color: Color(0xFF667eea)),
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
                SizedBox(height: 20),

                // Period Selector
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
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
                        _buildPeriodButton('Daily', TimePeriod.daily),
                        _buildPeriodButton('Monthly', TimePeriod.monthly),
                        _buildPeriodButton('Yearly', TimePeriod.yearly),
                        _buildPeriodButton('Custom', TimePeriod.custom),
                      ],
                    ),
                  ),
                ),

                if (_selectedPeriod == TimePeriod.custom)
                  Padding(
                    padding: EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildDateSelector(
                            'Start Date',
                            _customStartDate,
                                (date) {
                              setState(() => _customStartDate = date);
                              if (_customEndDate != null) _loadTransactions();
                            },
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: _buildDateSelector(
                            'End Date',
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

                SizedBox(height: 20),

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
                  // Total Income Card
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                        ),
                        borderRadius: BorderRadius.circular(16),
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
                            'Total Income',
                            style: GoogleFonts.poppins(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '\$${totalIncome.toStringAsFixed(2)}',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _getPeriodLabel(),
                            style: GoogleFonts.poppins(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 30),

                  // Pie Chart Section
                  if (categoryData.isNotEmpty) ...[
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Icon(Icons.pie_chart, color: Color(0xFF667eea), size: 24),
                          SizedBox(width: 8),
                          Text(
                            'Income by Category',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF333333),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    Container(
                      margin: EdgeInsets.symmetric(horizontal: 20),
                      padding: EdgeInsets.all(25),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
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
                                sections: _buildPieChartSections(categoryData, totalIncome),
                              ),
                            ),
                          ),
                          SizedBox(height: 20),
                          _buildLegend(categoryData, totalIncome),
                        ],
                      ),
                    ),
                    SizedBox(height: 30),
                  ],

                  // Bar Chart Section
                  if (timeSeriesData.isNotEmpty) ...[
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Icon(Icons.bar_chart, color: Color(0xFF667eea), size: 24),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _getBarChartTitle(),
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF333333),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    Container(
                      margin: EdgeInsets.symmetric(horizontal: 20),
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
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
                                    '$label\n\$${rod.toY.toStringAsFixed(2)}',
                                    GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
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
                                                fontSize: 9,
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
                                            fontSize: 10,
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
                                      '\$${value.toInt()}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 10,
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
                            padding: EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(Icons.analytics, size: 48, color: Colors.white),
                          ),
                          SizedBox(height: 24),
                          Text(
                            'No data available',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              color: Color(0xFF333333),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Add some income transactions to see your analytics',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
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

  Widget _buildPeriodButton(String label, TimePeriod period) {
    bool isSelected = _selectedPeriod == period;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedPeriod = period);
          if (period != TimePeriod.custom) {
            _loadTransactions();
          }
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(colors: [Color(0xFF667eea), Color(0xFF764ba2)])
                : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? Colors.white : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelector(String label, DateTime? date, Function(DateTime) onDateSelected) {
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
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey[600]),
            ),
            SizedBox(height: 4),
            Text(
              date != null ? DateFormat('MMM d, yyyy').format(date) : 'Select',
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
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

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: List.generate(categories.length, (i) {
        double percentage = (data[categories[i]]! / total) * 100;
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _getColorForIndex(i).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
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
                  fontSize: 11,
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
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      );
    });
  }

  String _getPeriodLabel() {
    switch (_selectedPeriod) {
      case TimePeriod.daily:
        return 'By Day of Week';
      case TimePeriod.monthly:
        return 'By Month';
      case TimePeriod.yearly:
        return 'By Year';
      case TimePeriod.custom:
        if (_customStartDate != null && _customEndDate != null) {
          return '${DateFormat('MMM d').format(_customStartDate!)} - ${DateFormat('MMM d, yyyy').format(_customEndDate!)}';
        }
        return 'Custom Period';
    }
  }

  String _getBarChartTitle() {
    switch (_selectedPeriod) {
      case TimePeriod.daily:
        return 'Income by Day of Week';
      case TimePeriod.monthly:
        return 'Income by Month';
      case TimePeriod.yearly:
        return 'Income by Year';
      case TimePeriod.custom:
        return 'Income Over Time';
    }
  }
}