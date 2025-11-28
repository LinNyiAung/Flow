import 'package:flutter/material.dart';
import 'package:frontend/models/user.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/budget.dart';
import '../../providers/budget_provider.dart';

class AIBudgetSuggestionScreen extends StatefulWidget {
  final BudgetPeriod period;
  final DateTime startDate;
  final DateTime? endDate;
  final String? userContext; // NEW
  final Currency currency;

  AIBudgetSuggestionScreen({
    required this.period,
    required this.startDate,
    this.endDate,
    this.userContext, // NEW
    required this.currency,
  });

  @override
  _AIBudgetSuggestionScreenState createState() =>
      _AIBudgetSuggestionScreenState();
}

class _AIBudgetSuggestionScreenState extends State<AIBudgetSuggestionScreen> {
  AIBudgetSuggestion? _suggestion;
  bool _isLoading = false;
  String? _error;
  int _analysisMonths = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generateSuggestion();
    });
  }

  Future<void> _generateSuggestion() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final budgetProvider = Provider.of<BudgetProvider>(context, listen: false);

    final suggestion = await budgetProvider.getAISuggestions(
      period: widget.period,
      startDate: widget.startDate,
      endDate: widget.endDate,
      analysisMonths: _analysisMonths,
      userContext: widget.userContext,
      currency: widget.currency,
    );

    setState(() {
      _suggestion = suggestion;
      _isLoading = false;
      if (suggestion == null) {
        _error = budgetProvider.error;
      }
    });
  }

  void _acceptSuggestion() {
    if (_suggestion != null) {
      Navigator.pop(context, _suggestion);
    }
  }

  void _showAnalysisSummary() {
    if (_suggestion == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.analytics, color: Color(0xFF667eea)),
            SizedBox(width: 12),
            Text(
              'Analysis Summary',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSummaryItem(
                'Transactions Analyzed',
                _suggestion!.analysisSummary['transaction_count'].toString(),
                Icons.receipt_long,
              ),
              _buildSummaryItem(
                'Analysis Period',
                '${_suggestion!.analysisSummary['analysis_months']} months',
                Icons.calendar_today,
              ),
              _buildSummaryItem(
                'Categories Found',
                _suggestion!.analysisSummary['categories_analyzed'].toString(),
                Icons.category,
              ),
              _buildSummaryItem(
                'Avg Monthly Income',
                '\$${_suggestion!.analysisSummary['average_monthly_income'].toStringAsFixed(2)}',
                Icons.trending_up,
              ),
              _buildSummaryItem(
                'Avg Monthly Expenses',
                '\$${_suggestion!.analysisSummary['average_monthly_expenses'].toStringAsFixed(2)}',
                Icons.trending_down,
              ),
              _buildSummaryItem(
                'Active Goals',
                _suggestion!.analysisSummary['active_goals'].toString(),
                Icons.flag,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: GoogleFonts.poppins(color: Color(0xFF667eea)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Color(0xFF667eea).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Color(0xFF667eea), size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'AI Budget Suggestion',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Color(0xFF333333)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_suggestion != null)
            IconButton(
              icon: Icon(Icons.info_outline, color: Color(0xFF667eea)),
              tooltip: 'Analysis Details',
              onPressed: _showAnalysisSummary,
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF667eea).withOpacity(0.1), Colors.white],
          ),
        ),
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF667eea),
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Analyzing your ${widget.currency.displayName} spending patterns...',  // NEW
                      style: GoogleFonts.poppins(color: Colors.grey[600]),
                    ),
                  ],
                ),
              )
            : _error != null
            ? _buildErrorState()
            : _suggestion != null
            ? _buildSuggestionContent()
            : _buildErrorState(),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red),
            SizedBox(height: 16),
            Text(
              'Failed to Generate Suggestion',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            SizedBox(height: 8),
            Text(
              _error ?? 'An error occurred',
              style: GoogleFonts.poppins(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _generateSuggestion,
              icon: Icon(Icons.refresh),
              label: Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF667eea),
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionContent() {
    return ListView(
      padding: EdgeInsets.all(20),
      children: [
        // Confidence Indicator
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _suggestion!.dataConfidence >= 0.7
                  ? [Color(0xFF4CAF50), Color(0xFF45a049)]
                  : _suggestion!.dataConfidence >= 0.5
                  ? [Color(0xFFFF9800), Color(0xFFF57C00)]
                  : [Color(0xFFFF5722), Color(0xFFE64A19)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                _suggestion!.dataConfidence >= 0.7
                    ? Icons.check_circle
                    : _suggestion!.dataConfidence >= 0.5
                    ? Icons.warning
                    : Icons.info,
                color: Colors.white,
                size: 32,
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Data Confidence',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    Text(
                      '${(_suggestion!.dataConfidence * 100).toStringAsFixed(0)}%',
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      _suggestion!.dataConfidence >= 0.7
                          ? 'High confidence based on your data'
                          : _suggestion!.dataConfidence >= 0.5
                          ? 'Moderate confidence - limited data'
                          : 'Low confidence - very limited data',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (widget.userContext != null && widget.userContext!.isNotEmpty) ...[
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF667eea).withOpacity(0.1),
                  Color(0xFF764ba2).withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Color(0xFF667eea).withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.note_alt, color: Color(0xFF667eea), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Your Context',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF333333),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  widget.userContext!,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Color(0xFF333333),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],

        // Warnings
        if (_suggestion!.warnings.isNotEmpty) ...[
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange[700],
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Important Notes',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange[900],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                ..._suggestion!.warnings.map(
                  (warning) => Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ', style: TextStyle(color: Colors.orange[700])),
                        Expanded(
                          child: Text(
                            warning,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.orange[900],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        SizedBox(height: 24),

        // Suggested Budget Info
        Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 2,
                blurRadius: 8,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Suggested Budget Plan',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF333333),
                ),
              ),
              SizedBox(height: 12),
              _buildInfoRow(Icons.label, 'Name', _suggestion!.suggestedName),
              _buildInfoRow(
                Icons.calendar_today,
                'Period',
                widget.period.name.toUpperCase(),
              ),
              _buildInfoRow(
                Icons.date_range,
                'Duration',
                '${DateFormat('MMM d').format(_suggestion!.startDate)} - ${DateFormat('MMM d, yyyy').format(_suggestion!.endDate)}',
              ),
              _buildInfoRow(
                Icons.attach_money,
                'Currency',
                _suggestion!.currency.displayName,  // NEW
              ),
              _buildInfoRow(
                Icons.attach_money,
                'Total Budget',
                '\$${_suggestion!.totalBudget.toStringAsFixed(2)}',
              ),
            ],
          ),
        ),

        SizedBox(height: 24),

        // AI Reasoning
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF667eea).withOpacity(0.1),
                Color(0xFF764ba2).withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.psychology, color: Color(0xFF667eea)),
                  SizedBox(width: 8),
                  Text(
                    'AI Analysis',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                _suggestion!.reasoning,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Color(0xFF333333),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: 24),

        // Category Budgets
        Text(
          'Category Budgets',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        SizedBox(height: 12),

        ..._suggestion!.categoryBudgets.map((catBudget) {
          final percentage = (_suggestion!.totalBudget > 0
              ? (catBudget.allocatedAmount / _suggestion!.totalBudget * 100)
              : 0);

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
                        catBudget.mainCategory,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF333333),
                        ),
                      ),
                    ),
                    Text(
                      '${_suggestion!.currency.symbol}${catBudget.allocatedAmount.toStringAsFixed(2)}',  // NEW: use currency symbol
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF667eea),
                      ),
                    ),
                  
                  ],
                ),
                SizedBox(height: 8),
                LinearProgressIndicator(
                  value: percentage / 100,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
                  minHeight: 6,
                ),
                SizedBox(height: 4),
                Text(
                  '${percentage.toStringAsFixed(1)}% of total budget',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }).toList(),

        SizedBox(height: 32),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: Color(0xFF667eea)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF667eea),
                  ),
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _acceptSuggestion,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF667eea),
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Use This Budget',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),

        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Color(0xFF667eea), size: 20),
          SizedBox(width: 12),
          Text(
            '$label:',
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600]),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
