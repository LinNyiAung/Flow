import 'package:flutter/material.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/budget.dart';
import '../../providers/budget_provider.dart';
import 'package:frontend/services/responsive_helper.dart';

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
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(16))),
        title: Row(
          children: [
            Icon(Icons.analytics, color: Color(0xFF667eea)),
            SizedBox(width: responsive.sp12),
            Text(
              localizations.analysisSummary,
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
                localizations.transactionsAnalyzed,
                _suggestion!.analysisSummary['transaction_count'].toString(),
                Icons.receipt_long,
              ),
              _buildSummaryItem(
                localizations.analysisPeriod,
                '${_suggestion!.analysisSummary['analysis_months']} months',
                Icons.calendar_today,
              ),
              _buildSummaryItem(
                localizations.categoriesFound,
                _suggestion!.analysisSummary['categories_analyzed'].toString(),
                Icons.category,
              ),
              _buildSummaryItem(
                localizations.avgMonthlyIncome,
                '\$${_suggestion!.analysisSummary['average_monthly_income'].toStringAsFixed(2)}',
                Icons.trending_up,
              ),
              _buildSummaryItem(
                localizations.avgMonthlyExpenses,
                '\$${_suggestion!.analysisSummary['average_monthly_expenses'].toStringAsFixed(2)}',
                Icons.trending_down,
              ),
              _buildSummaryItem(
                localizations.activeGoals,
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
              localizations.close,
              style: GoogleFonts.poppins(color: Color(0xFF667eea)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    final responsive = ResponsiveHelper(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: responsive.padding(all: 8),
            decoration: BoxDecoration(
              color: Color(0xFF667eea).withOpacity(0.1),
              borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
            ),
            child: Icon(icon, color: Color(0xFF667eea), size: responsive.icon20),
          ),
          SizedBox(width: responsive.sp12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs12,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
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
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          localizations.aiBudgetSuggestion,
          style: GoogleFonts.poppins(
            fontSize: responsive.fs20,
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
              tooltip: localizations.analysisDetails,
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
                    SizedBox(height: responsive.sp16),
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
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: responsive.padding(all: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: responsive.iconSize(mobile: 64), color: Colors.red),
            SizedBox(height: responsive.sp16),
            Text(
              localizations.failedToGenerateSuggestion,
              style: GoogleFonts.poppins(
                fontSize: responsive.fs18,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            SizedBox(height: responsive.sp8),
            Text(
              _error ?? 'An error occurred',
              style: GoogleFonts.poppins(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: responsive.sp24),
            ElevatedButton.icon(
              onPressed: _generateSuggestion,
              icon: Icon(Icons.refresh),
              label: Text(localizations.tryAgain),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF667eea),
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionContent() {
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);
    return ListView(
      padding: responsive.padding(all: 20),
      children: [
        // Confidence Indicator
        Container(
          padding: responsive.padding(all: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _suggestion!.dataConfidence >= 0.7
                  ? [Color(0xFF4CAF50), Color(0xFF45a049)]
                  : _suggestion!.dataConfidence >= 0.5
                  ? [Color(0xFFFF9800), Color(0xFFF57C00)]
                  : [Color(0xFFFF5722), Color(0xFFE64A19)],
            ),
            borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
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
                size: responsive.iconSize(mobile: 32),
              ),
              SizedBox(width: responsive.sp16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.dataConfidence,
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs14,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    Text(
                      '${(_suggestion!.dataConfidence * 100).toStringAsFixed(0)}%',
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      _suggestion!.dataConfidence >= 0.7
                          ? localizations.highConfidence
                          : _suggestion!.dataConfidence >= 0.5
                          ? localizations.moderateConfidence
                          : localizations.lowConfidence,
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs11,
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
          SizedBox(height: responsive.sp16),
          Container(
            padding: responsive.padding(all: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF667eea).withOpacity(0.1),
                  Color(0xFF764ba2).withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
              border: Border.all(color: Color(0xFF667eea).withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.note_alt, color: Color(0xFF667eea), size: responsive.icon20),
                    SizedBox(width: responsive.sp8),
                    Text(
                      localizations.yourContext,
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF333333),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: responsive.sp8),
                Text(
                  widget.userContext!,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs13,
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
          SizedBox(height: responsive.sp16),
          Container(
            padding: responsive.padding(all: 16),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
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
                    SizedBox(width: responsive.sp8),
                    Text(
                      localizations.importantNotes,
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs14,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange[900],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: responsive.sp8),
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
                              fontSize: responsive.fs12,
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

        SizedBox(height: responsive.sp24),

        // Suggested Budget Info
        Container(
          padding: responsive.padding(all: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
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
                localizations.suggestedBudgetPlan,
                style: GoogleFonts.poppins(
                  fontSize: responsive.fs18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF333333),
                ),
              ),
              SizedBox(height: responsive.sp12),
              _buildInfoRow(Icons.label, localizations.name, _suggestion!.suggestedName),
              _buildInfoRow(
                Icons.calendar_today,
                localizations.period,
                widget.period.name.toUpperCase(),
              ),
              _buildInfoRow(
                Icons.date_range,
                localizations.duration,
                '${DateFormat('MMM d').format(_suggestion!.startDate)} - ${DateFormat('MMM d, yyyy').format(_suggestion!.endDate)}',
              ),
              _buildInfoRow(
                Icons.attach_money,
                localizations.currency,
                _suggestion!.currency.displayName,  // NEW
              ),
              _buildInfoRow(
                Icons.attach_money,
                localizations.totalBudget,
                '\$${_suggestion!.totalBudget.toStringAsFixed(2)}',
              ),
            ],
          ),
        ),

        SizedBox(height: responsive.sp24),

        // AI Reasoning
        Container(
          padding: responsive.padding(all: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF667eea).withOpacity(0.1),
                Color(0xFF764ba2).withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.psychology, color: Color(0xFF667eea)),
                  SizedBox(width: responsive.sp8),
                  Text(
                    localizations.aiAnalysis,
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333),
                    ),
                  ),
                ],
              ),
              SizedBox(height: responsive.sp12),
              Text(
                _suggestion!.reasoning,
                style: GoogleFonts.poppins(
                  fontSize: responsive.fs13,
                  color: Color(0xFF333333),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: responsive.sp24),

        // Category Budgets
        Text(
          localizations.categoryBudgets,
          style: GoogleFonts.poppins(
            fontSize: responsive.fs18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        SizedBox(height: responsive.sp12),

        ..._suggestion!.categoryBudgets.map((catBudget) {
          final percentage = (_suggestion!.totalBudget > 0
              ? (catBudget.allocatedAmount / _suggestion!.totalBudget * 100)
              : 0);

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
                        catBudget.mainCategory,
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF333333),
                        ),
                      ),
                    ),
                    Text(
                      '${_suggestion!.currency.symbol}${catBudget.allocatedAmount.toStringAsFixed(2)}',  // NEW: use currency symbol
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF667eea),
                      ),
                    ),
                  
                  ],
                ),
                SizedBox(height: responsive.sp8),
                LinearProgressIndicator(
                  value: percentage / 100,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
                  minHeight: responsive.spacing(mobile: 6),
                ),
                SizedBox(height: responsive.sp4),
                Text(
                  '${percentage.toStringAsFixed(1)}% of total budget',
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }).toList(),

        SizedBox(height: responsive.sp32),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: responsive.padding(vertical: 16),
                  side: BorderSide(color: Color(0xFF667eea)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                  ),
                ),
                child: Text(
                  localizations.dialogCancel,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF667eea),
                  ),
                ),
              ),
            ),
            SizedBox(width: responsive.sp12),
            Expanded(
              child: ElevatedButton(
                onPressed: _acceptSuggestion,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF667eea),
                  padding: responsive.padding(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                  ),
                ),
                child: Text(
                  localizations.useThisBudget,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),

        SizedBox(height: responsive.sp16),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final responsive = ResponsiveHelper(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Color(0xFF667eea), size: responsive.icon20),
          SizedBox(width: responsive.sp12),
          Text(
            '$label:',
            style: GoogleFonts.poppins(fontSize: responsive.fs13, color: Colors.grey[600]),
          ),
          SizedBox(width: responsive.sp8),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: responsive.fs13,
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
