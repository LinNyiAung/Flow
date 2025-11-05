import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
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
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  FinancialReport? _report;
  bool _isLoading = false;
  bool _isDownloading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generateReport();
  }
  
  Future<void> _generateReport() async {
    if (_selectedPeriod == ReportPeriod.custom &&
        (_customStartDate == null || _customEndDate == null)) {
      setState(() {
        _report = null;
        _error = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final report = await ApiService.generateReport(
        period: _selectedPeriod,
        startDate: _customStartDate,
        endDate: _customEndDate,
      );

      setState(() {
        _report = report;
        _isLoading = false;
      });
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
    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        title: Text(
          'Financial Reports',
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
          if (_report != null)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
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
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Period Selector
                  Container(
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
                        _buildPeriodButton('Week', ReportPeriod.week),
                        _buildPeriodButton('Month', ReportPeriod.month),
                        _buildPeriodButton('Year', ReportPeriod.year),
                        _buildPeriodButton('Custom', ReportPeriod.custom),
                      ],
                    ),
                  ),

                  // Custom Date Selector (removed Generate Report button)
                  if (_selectedPeriod == ReportPeriod.custom) ...[
                    SizedBox(height: 16),
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
                        SizedBox(width: 12),
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

                  SizedBox(height: 24),

                  // Loading or Error State
                  if (_isLoading)
                    Center(
                      child: Column(
                        children: [
                          SizedBox(height: 60),
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
                          ),
                          SizedBox(height: 16),
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
                          Icon(Icons.error_outline, size: 64, color: Colors.red),
                          SizedBox(height: 16),
                          Text(
                            'Error',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                          SizedBox(height: 8),
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
                    else if (_selectedPeriod == ReportPeriod.custom)
                        Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 60),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.date_range,
                                  size: 64,
                                  color: Colors.grey[300],
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Select both dates to generate report',
                                  style: GoogleFonts.poppins(
                                    color: Colors.grey[600],
                                    fontSize: 16,
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

  Widget _buildReportContent(FinancialReport report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Report Period Info
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(16),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Report Period',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: 4),
              Text(
                '${DateFormat('MMM d, yyyy').format(report.startDate.toUtc())} - ${DateFormat('MMM d, yyyy').format(report.endDate.toUtc())}',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF333333),
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: 20),

        // Summary Cards
        _buildSummaryCard(
          'Net Balance',
          report.netBalance,
          report.netBalance >= 0 ? Color(0xFF4CAF50) : Color(0xFFFF5722),
          Icons.account_balance_wallet,
        ),

        SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _buildSmallSummaryCard(
                'Income',
                report.totalInflow,
                Color(0xFF4CAF50),
                Icons.arrow_upward,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildSmallSummaryCard(
                'Expenses',
                report.totalOutflow,
                Color(0xFFFF5722),
                Icons.arrow_downward,
              ),
            ),
          ],
        ),

        SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _buildInfoCard(
                'Transactions',
                report.totalTransactions.toString(),
                Icons.receipt_long,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildInfoCard(
                'Goals Allocated',
                '\$${report.totalAllocatedToGoals.toStringAsFixed(0)}',
                Icons.flag,
              ),
            ),
          ],
        ),

        SizedBox(height: 24),

        // Daily Averages
        Text(
          'Daily Averages',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),

        SizedBox(height: 12),

        Container(
          padding: EdgeInsets.all(16),
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
          child: Column(
            children: [
              _buildAverageRow(
                'Average Daily Income',
                report.averageDailyInflow,
                Color(0xFF4CAF50),
              ),
              Divider(height: 24),
              _buildAverageRow(
                'Average Daily Expenses',
                report.averageDailyOutflow,
                Color(0xFFFF5722),
              ),
            ],
          ),
        ),

        SizedBox(height: 24),

        // Income Breakdown
        if (report.inflowByCategory.isNotEmpty) ...[
          Text(
            'Income by Category',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF333333),
            ),
          ),
          SizedBox(height: 12),
          ...report.inflowByCategory.take(5).map((cat) => _buildCategoryCard(
            cat.category,
            cat.amount,
            cat.percentage,
            Color(0xFF4CAF50),
          )),
          SizedBox(height: 24),
        ],

        // Expense Breakdown
        if (report.outflowByCategory.isNotEmpty) ...[
          Text(
            'Expenses by Category',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF333333),
            ),
          ),
          SizedBox(height: 12),
          ...report.outflowByCategory.take(5).map((cat) => _buildCategoryCard(
            cat.category,
            cat.amount,
            cat.percentage,
            Color(0xFFFF5722),
          )),
          SizedBox(height: 24),
        ],

        // Goals Progress
        if (report.goals.isNotEmpty) ...[
          Text(
            'Goals Progress',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF333333),
            ),
          ),
          SizedBox(height: 12),
          ...report.goals.map((goal) => _buildGoalCard(goal)),
        ],
      ],
    );
  }

  Widget _buildSummaryCard(String label, double amount, Color color, IconData icon) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(16),
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
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '\$${amount.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                    fontSize: 28,
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

  Widget _buildSmallSummaryCard(String label, double amount, Color color, IconData icon) {
    return Container(
      padding: EdgeInsets.all(16),
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
        border: Border(
          left: BorderSide(color: color, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 4),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String label, String value, IconData icon) {
    return Container(
      padding: EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Color(0xFF667eea), size: 24),
          SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF333333),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAverageRow(String label, double amount, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: Color(0xFF333333),
          ),
        ),
        Text(
          '\$${amount.toStringAsFixed(2)}',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryCard(String category, double amount, double percentage, Color color) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(16),
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
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
              ),
              Text(
                '\$${amount.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          LinearProgressIndicator(
            value: percentage / 100,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
          SizedBox(height: 4),
          Text(
            '${percentage.toStringAsFixed(1)}% of total',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalCard(GoalProgressReport goal) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(16),
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
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
              ),
              if (goal.status == 'achieved')
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Color(0xFF4CAF50).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'ACHIEVED',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4CAF50),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '\$${goal.currentAmount.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF667eea),
                ),
              ),
              Text(
                '\$${goal.targetAmount.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          LinearProgressIndicator(
            value: goal.progressPercentage / 100,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(
              goal.status == 'achieved' ? Color(0xFF4CAF50) : Color(0xFF667eea),
            ),
            minHeight: 6,
          ),
          SizedBox(height: 4),
          Text(
            '${goal.progressPercentage.toStringAsFixed(1)}% Complete',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}