import 'package:flutter/material.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/progress_meter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/budget.dart';
import '../../providers/budget_provider.dart';

class AIBudgetSuggestionScreen extends StatefulWidget {
  final BudgetPeriod period;
  final DateTime startDate;
  final DateTime? endDate;
  final String? userContext;
  final Currency currency;

  AIBudgetSuggestionScreen({
    required this.period,
    required this.startDate,
    this.endDate,
    this.userContext,
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

  /// Hands the reviewed suggestion back to the create-budget flow. This
  /// screen never saves a budget itself — the caller decides whether to
  /// create it.
  void _acceptSuggestion() {
    if (_suggestion != null) {
      Navigator.pop(context, _suggestion);
    }
  }

  void _showAnalysisSummary() {
    if (_suggestion == null) return;
    final localizations = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.analytics_rounded, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(localizations.analysisSummary)),
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
                Icons.receipt_long_rounded,
              ),
              _buildSummaryItem(
                localizations.analysisPeriod,
                '${_suggestion!.analysisSummary['analysis_months']} months',
                Icons.calendar_today_rounded,
              ),
              _buildSummaryItem(
                localizations.categoriesFound,
                _suggestion!.analysisSummary['categories_analyzed'].toString(),
                Icons.category_rounded,
              ),
              _buildSummaryItem(
                localizations.avgMonthlyIncome,
                '${_suggestion!.currency.symbol}${formatter.format(_suggestion!.analysisSummary['average_monthly_income'])}',
                Icons.trending_up_rounded,
              ),
              _buildSummaryItem(
                localizations.avgMonthlyExpenses,
                '${_suggestion!.currency.symbol}${formatter.format(_suggestion!.analysisSummary['average_monthly_expenses'])}',
                Icons.trending_down_rounded,
              ),
              _buildSummaryItem(
                localizations.activeGoals,
                _suggestion!.analysisSummary['active_goals'].toString(),
                Icons.flag_rounded,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.close),
          ),
        ],
      ),
    );
  }

  /// Mockup's `--tint-neutral` (F1F5F3 light / 1F2723 dark) — a plain
  /// neutral surface, distinct from the jade-tinted `secondaryContainer`.
  /// Not in [AppTheme] as a named token, so it's reproduced here directly,
  /// brightness-aware.
  Color _tintNeutral(BuildContext context) => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF1F2723)
      : const Color(0xFFF1F5F3);

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: scheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.aiBudgetSuggestion),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_suggestion != null)
            IconButton(
              icon: const Icon(Icons.info_outline_rounded),
              tooltip: localizations.analysisDetails,
              onPressed: _showAnalysisSummary,
            ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingState()
          : _error != null
          ? _buildErrorState()
          : _suggestion != null
          ? _buildSuggestionContent()
          : _buildErrorState(),
    );
  }

  Widget _buildLoadingState() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: scheme.tertiaryContainer, shape: BoxShape.circle),
              child: Icon(Icons.auto_awesome_rounded, color: scheme.tertiary, size: 34),
            ),
            const SizedBox(height: 20),
            Text(
              'Analyzing your ${widget.currency.displayName} spending patterns...',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 160,
              child: LinearProgressIndicator(
                minHeight: 4,
                backgroundColor: scheme.tertiaryContainer,
                valueColor: AlwaysStoppedAnimation<Color>(scheme.tertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: scheme.error),
            const SizedBox(height: 16),
            Text(
              localizations.failedToGenerateSuggestion,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: scheme.error),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'An error occurred',
              style: TextStyle(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _generateSuggestion,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(localizations.tryAgain),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionContent() {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final confidence = _suggestion!.dataConfidence;
    final Color confidenceBg;
    final Color confidenceFg;
    final IconData confidenceIcon;
    final String confidenceLabel;
    if (confidence >= 0.7) {
      confidenceBg = scheme.primaryContainer;
      confidenceFg = AppTheme.jadeLabel2For(context);
      confidenceIcon = Icons.verified_rounded;
      confidenceLabel = localizations.highConfidence;
    } else if (confidence >= 0.5) {
      confidenceBg = scheme.tertiaryContainer;
      confidenceFg = scheme.onTertiaryContainer;
      confidenceIcon = Icons.warning_amber_rounded;
      confidenceLabel = localizations.moderateConfidence;
    } else {
      confidenceBg = scheme.errorContainer;
      confidenceFg = scheme.onErrorContainer;
      confidenceIcon = Icons.info_rounded;
      confidenceLabel = localizations.lowConfidence;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        // Confidence banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: confidenceBg, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Icon(confidenceIcon, color: confidenceFg, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.dataConfidence,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: confidenceFg),
                    ),
                    Text(
                      '${(confidence * 100).toStringAsFixed(0)}%',
                      style: AppTheme.money(24, weight: FontWeight.w800, color: confidenceFg),
                    ),
                    Text(
                      confidenceLabel,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: confidenceFg),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (widget.userContext != null && widget.userContext!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.note_alt_rounded, color: scheme.tertiary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      localizations.yourContext,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onTertiaryContainer),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.userContext!,
                  style: TextStyle(fontSize: 13, color: scheme.onTertiaryContainer, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],

        if (_suggestion!.warnings.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: scheme.tertiary),
                    const SizedBox(width: 8),
                    Text(
                      localizations.importantNotes,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onTertiaryContainer),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._suggestion!.warnings.map(
                  (warning) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('•  ', style: TextStyle(color: scheme.tertiary)),
                        Expanded(
                          child: Text(
                            warning,
                            style: TextStyle(fontSize: 12, color: scheme.onTertiaryContainer),
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

        const SizedBox(height: 24),

        // Suggested plan
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Theme.of(context).cardTheme.shadowColor ?? const Color(0x14101815), blurRadius: 8, offset: Offset(0, 1)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(localizations.suggestedBudgetPlan, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _buildInfoRow(Icons.label_outline_rounded, localizations.name, _suggestion!.suggestedName),
              _buildInfoRow(Icons.calendar_today_rounded, localizations.period, widget.period.name.toUpperCase()),
              _buildInfoRow(
                Icons.date_range_rounded,
                localizations.duration,
                '${DateFormat('MMM d').format(_suggestion!.startDate)} - ${DateFormat('MMM d, yyyy').format(_suggestion!.endDate)}',
              ),
              _buildInfoRow(Icons.attach_money_rounded, localizations.currency, _suggestion!.currency.displayName),
              _buildInfoRow(
                Icons.attach_money_rounded,
                localizations.totalBudget,
                '${_suggestion!.currency.symbol}${formatter.format(_suggestion!.totalBudget)}',
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // AI reasoning — mockup's "HOW IT WAS SET" box, a plain neutral
        // surface (not the jade-tinted secondary container).
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: _tintNeutral(context), borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.psychology_rounded, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(localizations.aiAnalysis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _suggestion!.reasoning,
                style: TextStyle(fontSize: 13, color: scheme.onSurface, height: 1.5),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        Text(localizations.categoryBudgets, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),

        ..._suggestion!.categoryBudgets.map((catBudget) {
          final percentage = (_suggestion!.totalBudget > 0
              ? (catBudget.allocatedAmount / _suggestion!.totalBudget * 100)
              : 0.0);

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Theme.of(context).cardTheme.shadowColor ?? const Color(0x14101815), blurRadius: 8, offset: Offset(0, 1)),
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
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_suggestion!.currency.symbol}${formatter.format(catBudget.allocatedAmount)}',
                      style: AppTheme.money(16, weight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ProgressMeter(value: percentage / 100),
                const SizedBox(height: 6),
                Text(
                  '${percentage.toStringAsFixed(1)}% of total budget',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 28),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(localizations.dialogCancel),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _acceptSuggestion,
                child: Text(localizations.useThisBudget),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: scheme.onSurfaceVariant, size: 20),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              '$label:',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
