import 'package:flutter/material.dart';
import 'package:frontend/models/user.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import '../../models/report.dart';
import '../../services/api_service.dart';
import '../../widgets/app_drawer.dart';
import 'package:frontend/services/responsive_helper.dart';

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

  @override
  void initState() {
    super.initState();
    _selectedCurrency = null;
    _generateReport();
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
      // Generate multi-currency report
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
      // Generate single currency report
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
    if (_selectedPeriod == ReportPeriod.custom &&
        (_customStartDate == null || _customEndDate == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select both start and end dates'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isDownloading = true);

    try {
    final filePath = await ApiService.downloadReportPdf(
      period: _selectedPeriod,
      startDate: _customStartDate,
      endDate: _customEndDate,
      currency: _selectedCurrency,  // NEW - Add this
    );

      setState(() => _isDownloading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report downloaded successfully!'),
          backgroundColor: Color(0xFF4CAF50),
          action: SnackBarAction(
            label: 'Open',
            textColor: Colors.white,
            onPressed: () => OpenFilex.open(filePath),
          ),
        ),
      );
    } catch (e) {
      setState(() => _isDownloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to download report: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final responsive = ResponsiveHelper(context);
    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        title: Text(
          'Financial Reports',
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
          if (_report != null)
            Padding(
              padding: responsive.padding(right: 16),
              child: _isDownloading
                  ? Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
                  ),
                ),
              )
                  : IconButton(
                icon: Icon(Icons.download),
                color: Color(0xFF667eea),
                tooltip: 'Download PDF',
                onPressed: _downloadReport,
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
          onRefresh: _generateReport,
          color: Color(0xFF667eea),
          child: SingleChildScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: responsive.padding(all: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Period Selector
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
                      children: [
                        _buildPeriodButton('Week', ReportPeriod.week),
                        _buildPeriodButton('Month', ReportPeriod.month),
                        _buildPeriodButton('Year', ReportPeriod.year),
                        _buildPeriodButton('Custom', ReportPeriod.custom),
                      ],
                    ),
                  ),


                  SizedBox(height: responsive.sp16),

                  // Currency Selector
                  Container(
                    padding: responsive.padding(horizontal: 16, vertical: 12),
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
                        Icon(Icons.attach_money, color: Color(0xFF667eea), size: responsive.icon20),
                        SizedBox(width: responsive.sp12),
                        Text(
                          'Currency:',
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF333333),
                          ),
                        ),
                        SizedBox(width: responsive.sp12),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<Currency?>(
                              value: _selectedCurrency,
                              isExpanded: true,
                              items: [
                                DropdownMenuItem<Currency?>(
                                  value: null,
                                  child: Text(
                                    'All Currencies',
                                    style: GoogleFonts.poppins(
                                      fontSize: responsive.fs14,
                                      fontWeight: FontWeight.w600,
                                      
                                    ),
                                  ),
                                ),
                                ...Currency.values.map((currency) {
                                  return DropdownMenuItem<Currency?>(
                                    value: currency,
                                    child: Text(
                                      '${currency.displayName} (${currency.symbol})',
                                      style: GoogleFonts.poppins(fontSize: responsive.fs14, fontWeight: FontWeight.w600,),
                                    ),
                                  );
                                }).toList(),
                              ],
                              onChanged: (Currency? newValue) {
                                setState(() {
                                  _selectedCurrency = newValue;
                                });
                                _generateReport();
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Custom Date Selector (removed Generate Report button)
                  if (_selectedPeriod == ReportPeriod.custom) ...[
                    SizedBox(height: responsive.sp16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDateSelector(
                            'Start Date',
                            _customStartDate,
                                (date) {
                              setState(() => _customStartDate = date);
                              // Auto-generate if both dates are selected
                              if (_customEndDate != null) {
                                _generateReport();
                              }
                            },
                          ),
                        ),
                        SizedBox(width: responsive.sp12),
                        Expanded(
                          child: _buildDateSelector(
                            'End Date',
                            _customEndDate,
                                (date) {
                              setState(() => _customEndDate = date);
                              // Auto-generate if both dates are selected
                              if (_customStartDate != null) {
                                _generateReport();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],

                  SizedBox(height: responsive.sp24),

                  // Loading or Error State
                  if (_isLoading)
                    Center(
                      child: Column(
                        children: [
                          SizedBox(height: 60),
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
                          ),
                          SizedBox(height: responsive.sp16),
                          Text(
                            'Generating report...',
                            style: GoogleFonts.poppins(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  else if (_error != null)
                    Center(
                      child: Column(
                        children: [
                          SizedBox(height: 40),
                          Icon(Icons.error_outline, size: responsive.icon64, color: Colors.red),
                          SizedBox(height: responsive.sp16),
                          Text(
                            'Error',
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs18,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                          SizedBox(height: responsive.sp8),
                          Text(
                            _error!,
                            style: GoogleFonts.poppins(color: Colors.grey[600]),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else if (_report != null)
                    _buildReportContent(_report!)
                else if (_multiCurrencyReport != null)
                    _buildMultiCurrencyReportContent(_multiCurrencyReport!)
                else if (_selectedPeriod == ReportPeriod.custom)
                        Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 60),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.date_range,
                                  size: responsive.icon64,
                                  color: Colors.grey[300],
                                ),
                                SizedBox(height: responsive.sp16),
                                Text(
                                  'Select both dates to generate report',
                                  style: GoogleFonts.poppins(
                                    color: Colors.grey[600],
                                    fontSize: responsive.fs16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                  SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodButton(String label, ReportPeriod period) {
    final responsive = ResponsiveHelper(context);
    bool isSelected = _selectedPeriod == period;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedPeriod = period;
            if (period == ReportPeriod.custom) {
              // Clear custom dates when switching to custom
              _customStartDate = null;
              _customEndDate = null;
              _report = null;
            }
          });
          if (period != ReportPeriod.custom) {
            _generateReport();
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
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.05),
              spreadRadius: 1,
              blurRadius: 2,
            ),
          ],
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
              date != null ? DateFormat('MMM d, yyyy').format(date) : 'Select',
              style: GoogleFonts.poppins(fontSize: responsive.fs14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportContent(FinancialReport report) {
    final responsive = ResponsiveHelper(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Report Period Info
        Container(
          width: double.infinity,
          padding: responsive.padding(all: 16),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Report Period',
                style: GoogleFonts.poppins(
                  fontSize: responsive.fs12,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: responsive.sp4),
              Text(
                '${DateFormat('MMM d, yyyy').format(report.startDate.toUtc())} - ${DateFormat('MMM d, yyyy').format(report.endDate.toUtc())}',
                style: GoogleFonts.poppins(
                  fontSize: responsive.fs16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF333333),
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: responsive.sp20),

        // Summary Cards
        _buildSummaryCard(
          'Net Balance',
          report.netBalance,
          report.netBalance >= 0 ? Color(0xFF4CAF50) : Color(0xFFFF5722),
          Icons.account_balance_wallet,
          report,
        ),

        SizedBox(height: responsive.sp12),

        Row(
          children: [
            Expanded(
              child: _buildSmallSummaryCard(
                'Income',
                report.totalInflow,
                Color(0xFF4CAF50),
                Icons.arrow_upward,
                report,
              ),
            ),
            SizedBox(width: responsive.sp12),
            Expanded(
              child: _buildSmallSummaryCard(
                'Expenses',
                report.totalOutflow,
                Color(0xFFFF5722),
                Icons.arrow_downward,
                report,
              ),
            ),
          ],
        ),

        SizedBox(height: responsive.sp12),

        Row(
          children: [
            Expanded(
              child: _buildInfoCard(
                'Transactions',
                report.totalTransactions.toString(),
                Icons.receipt_long,
              ),
            ),
            SizedBox(width: responsive.sp12),
            Expanded(
              child: _buildInfoCard(
                'Goals Allocated',
                '${report.currency.symbol}${report.totalAllocatedToGoals.toStringAsFixed(0)}',
                Icons.flag,
              ),
            ),
          ],
        ),

        SizedBox(height: responsive.sp24),

        // Daily Averages
        Text(
          'Daily Averages',
          style: GoogleFonts.poppins(
            fontSize: responsive.fs18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),

        SizedBox(height: responsive.sp12),

        Container(
          padding: responsive.padding(all: 16),
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
          child: Column(
            children: [
              _buildAverageRow(
                'Average Daily Income',
                report.averageDailyInflow,
                Color(0xFF4CAF50),
                report,
              ),
              Divider(height: 24),
              _buildAverageRow(
                'Average Daily Expenses',
                report.averageDailyOutflow,
                Color(0xFFFF5722),
                report,
              ),
            ],
          ),
        ),

        SizedBox(height: responsive.sp24),

        // Income Breakdown
        if (report.inflowByCategory.isNotEmpty) ...[
          Text(
            'Income by Category',
            style: GoogleFonts.poppins(
              fontSize: responsive.fs18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF333333),
            ),
          ),
          SizedBox(height: responsive.sp12),
          ...report.inflowByCategory.take(5).map((cat) => _buildCategoryCard(
            cat.category,
            cat.amount,
            cat.percentage,
            Color(0xFF4CAF50),
            report,
          )),
          SizedBox(height: responsive.sp24),
        ],

        // Expense Breakdown
        if (report.outflowByCategory.isNotEmpty) ...[
          Text(
            'Expenses by Category',
            style: GoogleFonts.poppins(
              fontSize: responsive.fs18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF333333),
            ),
          ),
          SizedBox(height: responsive.sp12),
          ...report.outflowByCategory.take(5).map((cat) => _buildCategoryCard(
            cat.category,
            cat.amount,
            cat.percentage,
            Color(0xFFFF5722),
            report,
          )),
          SizedBox(height: responsive.sp24),
        ],

        // Goals Progress
        if (report.goals.isNotEmpty) ...[
          Text(
            'Goals Progress',
            style: GoogleFonts.poppins(
              fontSize: responsive.fs18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF333333),
            ),
          ),
          SizedBox(height: responsive.sp12),
          ...report.goals.map((goal) => _buildGoalCard(goal)),
        ],
      ],
    );
  }

  Widget _buildSummaryCard(String label, double amount, Color color, IconData icon, FinancialReport report) {
    final responsive = ResponsiveHelper(context);
    return Container(
      width: double.infinity,
      padding: responsive.padding(all: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: responsive.padding(all: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
            ),
            child: Icon(icon, color: Colors.white, size: responsive.icon28),
          ),
          SizedBox(width: responsive.sp16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                SizedBox(height: responsive.sp4),
                Text(
                  '${report.currency.symbol}${amount.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallSummaryCard(String label, double amount, Color color, IconData icon, FinancialReport report) {
    final responsive = ResponsiveHelper(context);
    return Container(
      padding: responsive.padding(all: 16),
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
        border: Border(
          left: BorderSide(color: color, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: responsive.icon24),
          SizedBox(height: responsive.sp8),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: responsive.fs12,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: responsive.sp4),
          Text(
            '${report.currency.symbol}${amount.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
              fontSize: responsive.fs18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildMultiCurrencyReportContent(MultiCurrencyFinancialReport report) {
    final responsive = ResponsiveHelper(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Report Period Info
      Container(
        width: double.infinity,
        padding: responsive.padding(all: 16),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.public, color: Color(0xFF667eea), size: responsive.icon20),
                SizedBox(width: responsive.sp8),
                Text(
                  'Multi-Currency Report',
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF667eea),
                  ),
                ),
              ],
            ),
            SizedBox(height: responsive.sp8),
            Text(
              '${DateFormat('MMM d, yyyy').format(report.startDate.toUtc())} - ${DateFormat('MMM d, yyyy').format(report.endDate.toUtc())}',
              style: GoogleFonts.poppins(
                fontSize: responsive.fs16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333),
              ),
            ),
          ],
        ),
      ),

      SizedBox(height: responsive.sp20),

      // Overview Card
      Container(
        width: double.infinity,
        padding: responsive.padding(all: 16),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Overview',
              style: GoogleFonts.poppins(
                fontSize: responsive.fs16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: responsive.sp12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Transactions',
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                Text(
                  '${report.totalTransactions}',
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            SizedBox(height: responsive.sp8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Currencies',
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                Text(
                  '${report.currencyReports.length}',
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),

      SizedBox(height: responsive.sp24),

      // Currency Reports
      Text(
        'By Currency',
        style: GoogleFonts.poppins(
          fontSize: responsive.fs18,
          fontWeight: FontWeight.bold,
          color: Color(0xFF333333),
        ),
      ),

      SizedBox(height: responsive.sp12),

      ...report.currencyReports.map((currencyReport) => 
        _buildCurrencyReportCard(currencyReport)
      ),

      SizedBox(height: responsive.sp24),

      // All Goals
      if (report.goals.isNotEmpty) ...[
        Text(
          'All Goals',
          style: GoogleFonts.poppins(
            fontSize: responsive.fs18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        SizedBox(height: responsive.sp12),
        ...report.goals.map((goal) => _buildGoalCard(goal)),
      ],

      SizedBox(height: 100),
    ],
  );
}

Widget _buildCurrencyReportCard(CurrencyReport currencyReport) {
  final currency = currencyReport.currency;
  final netBalance = currencyReport.netBalance;
  final balanceColor = netBalance >= 0 ? Color(0xFF4CAF50) : Color(0xFFFF5722);
  final responsive = ResponsiveHelper(context);

  return Container(
    margin: responsive.padding(bottom: 16),
    padding: responsive.padding(all: 20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.1),
          spreadRadius: 2,
          blurRadius: 6,
        ),
      ],
      border: Border(
        left: BorderSide(color: balanceColor, width: 4),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Currency Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: responsive.padding(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: balanceColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
                  ),
                  child: Text(
                    currency.displayName,
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs16,
                      fontWeight: FontWeight.bold,
                      color: balanceColor,
                    ),
                  ),
                ),
                SizedBox(width: responsive.sp8),
                Text(
                  '(${currency.symbol})',
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            Text(
              '${currencyReport.totalTransactions} txns',
              style: GoogleFonts.poppins(
                fontSize: responsive.fs12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),

        Divider(height: 24),

        // Net Balance
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Net Balance',
              style: GoogleFonts.poppins(
                fontSize: responsive.fs14,
                color: Colors.grey[600],
              ),
            ),
            Text(
              '${currency.symbol}${netBalance.toStringAsFixed(2)}',
              style: GoogleFonts.poppins(
                fontSize: responsive.fs20,
                fontWeight: FontWeight.bold,
                color: balanceColor,
              ),
            ),
          ],
        ),

        SizedBox(height: responsive.sp16),

        // Income and Expenses
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.arrow_upward, color: Color(0xFF4CAF50), size: responsive.icon16),
                      SizedBox(width: responsive.sp4),
                      Text(
                        'Income',
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: responsive.sp4),
                  Text(
                    '${currency.symbol}${currencyReport.totalInflow.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4CAF50),
                    ),
                  ),
                  Text(
                    '${currencyReport.inflowCount} transactions',
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs10,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: Colors.grey[300],
            ),
            SizedBox(width: responsive.sp16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.arrow_downward, color: Color(0xFFFF5722), size: responsive.icon16),
                      SizedBox(width: responsive.sp4),
                      Text(
                        'Expenses',
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: responsive.sp4),
                  Text(
                    '${currency.symbol}${currencyReport.totalOutflow.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF5722),
                    ),
                  ),
                  Text(
                    '${currencyReport.outflowCount} transactions',
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs10,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        SizedBox(height: responsive.sp16),

        // Daily Averages
        Container(
          padding: responsive.padding(all: 12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Avg. Daily Income',
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs12,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    '${currency.symbol}${currencyReport.averageDailyInflow.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4CAF50),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Avg. Daily Expenses',
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs12,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    '${currency.symbol}${currencyReport.averageDailyOutflow.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF5722),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Top Categories (expandable)
        if (currencyReport.inflowByCategory.isNotEmpty || currencyReport.outflowByCategory.isNotEmpty) ...[
          SizedBox(height: responsive.sp12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'View Categories',
              style: GoogleFonts.poppins(
                fontSize: responsive.fs13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF667eea),
              ),
            ),
            children: [
              if (currencyReport.inflowByCategory.isNotEmpty) ...[
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Top Income Categories',
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
                ...currencyReport.inflowByCategory.take(3).map((cat) => 
                  Padding(
                    padding: responsive.padding(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            cat.category,
                            style: GoogleFonts.poppins(fontSize: responsive.fs11),
                          ),
                        ),
                        Text(
                          '${currency.symbol}${cat.amount.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF4CAF50),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (currencyReport.outflowByCategory.isNotEmpty) ...[
                Padding(
                  padding: responsive.padding(top: 12),
                  child: Text(
                    'Top Expense Categories',
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
                ...currencyReport.outflowByCategory.take(3).map((cat) => 
                  Padding(
                    padding: responsive.padding(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            cat.category,
                            style: GoogleFonts.poppins(fontSize: responsive.fs11),
                          ),
                        ),
                        Text(
                          '${currency.symbol}${cat.amount.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFFF5722),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    ),
  );
}

  Widget _buildInfoCard(String label, String value, IconData icon) {
    final responsive = ResponsiveHelper(context);
    return Container(
      padding: responsive.padding(all: 16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Color(0xFF667eea), size: responsive.icon24),
          SizedBox(height: responsive.sp8),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: responsive.fs12,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: responsive.sp4),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: responsive.fs18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF333333),
            ),
          ),
        ],
      ),
    );
  }

  
  Widget _buildAverageRow(String label, double amount, Color color, FinancialReport report) {
    final responsive = ResponsiveHelper(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: responsive.fs14,
            color: Color(0xFF333333),
          ),
        ),
        Text(
          '${report.currency.symbol}${amount.toStringAsFixed(2)}',
          style: GoogleFonts.poppins(
            fontSize: responsive.fs16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

Widget _buildCategoryCard(String category, double amount, double percentage, Color color, FinancialReport report) {
    final responsive = ResponsiveHelper(context);
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: responsive.padding(all: 16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  category,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
              ),
              Text(
                '${report.currency.symbol}${amount.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                  fontSize: responsive.fs16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.sp8),
          LinearProgressIndicator(
            value: percentage / 100,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
          SizedBox(height: responsive.sp4),
          Text(
            '${percentage.toStringAsFixed(1)}% of total',
            style: GoogleFonts.poppins(
              fontSize: responsive.fs11,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalCard(GoalProgressReport goal) {
    final responsive = ResponsiveHelper(context);
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: responsive.padding(all: 16),
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
        border: Border(
          left: BorderSide(
            color: goal.status == 'achieved' ? Color(0xFF4CAF50) : Color(0xFF667eea),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  goal.name,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
              ),
              if (goal.status == 'achieved')
                Container(
                  padding: responsive.padding(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Color(0xFF4CAF50).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
                  ),
                  child: Text(
                    'ACHIEVED',
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4CAF50),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: responsive.sp8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${goal.currency.symbol}${goal.currentAmount.toStringAsFixed(2)}',  // Use goal.currency instead
                style: GoogleFonts.poppins(
                  fontSize: responsive.fs16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF667eea),
                ),
              ),
              Text(
                '${goal.currency.symbol}${goal.targetAmount.toStringAsFixed(2)}',  // Use goal.currency instead
                style: GoogleFonts.poppins(
                  fontSize: responsive.fs14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.sp8),
          LinearProgressIndicator(
            value: goal.progressPercentage / 100,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(
              goal.status == 'achieved' ? Color(0xFF4CAF50) : Color(0xFF667eea),
            ),
            minHeight: 6,
          ),
          SizedBox(height: responsive.sp4),
          Text(
            '${goal.progressPercentage.toStringAsFixed(1)}% Complete',
            style: GoogleFonts.poppins(
              fontSize: responsive.fs11,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}