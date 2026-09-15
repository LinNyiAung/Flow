import 'dart:io';
import 'package:flutter/material.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/status_pill.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/api_service.dart';
import '../../providers/transaction_provider.dart';
import '../../models/voice_image_models.dart';
import 'package:intl/intl.dart';

class VoiceInputScreen extends StatefulWidget {
  @override
  _VoiceInputScreenState createState() => _VoiceInputScreenState();
}

class _VoiceInputScreenState extends State<VoiceInputScreen>
    with TickerProviderStateMixin {
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isSaving = false;
  String? _transcribedText;
  MultipleExtractedTransactions? _extractedData;
  List<bool> _selected = [];
  String? _error;
  final formatter = NumberFormat("#,##0.00", "en_US");

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.microphone.request();
  }

  Future<void> _startRecording() async {
    final localizations = AppLocalizations.of(context);
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        final path = '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: path,
        );

        setState(() {
          _isRecording = true;
          _error = null;
          _transcribedText = null;
          _extractedData = null;
          _selected = [];
        });
      }
    } catch (e) {
      setState(() {
        _error = '${localizations.errorStartRecording} ${e.toString()}';
      });
    }
  }

  Future<void> _stopRecording() async {
    final localizations = AppLocalizations.of(context);
    try {
      final path = await _audioRecorder.stop();

      setState(() {
        _isRecording = false;
      });

      if (path != null) {
        await _processAudio(path);
      }
    } catch (e) {
      setState(() {
        _error = '${localizations.errorStopRecording} ${e.toString()}';
        _isRecording = false;
      });
    }
  }

  Future<void> _processAudio(String path) async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      // Step 1: Transcribe audio
      final transcription = await ApiService.transcribeAudio(File(path));

      setState(() {
        _transcribedText = transcription;
      });

      // Step 2: Extract multiple transaction data
      final extractedData = await ApiService.extractMultipleTransactionsFromText(transcription);

      setState(() {
        _extractedData = extractedData;
        _selected = List<bool>.filled(extractedData.transactions.length, true);
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isProcessing = false;
      });
    }
  }

  List<ExtractedTransactionData> get _selectedTransactions {
    if (_extractedData == null) return [];
    final list = <ExtractedTransactionData>[];
    for (var i = 0; i < _extractedData!.transactions.length; i++) {
      if (i < _selected.length && _selected[i]) list.add(_extractedData!.transactions[i]);
    }
    return list;
  }

  Future<void> _saveAllTransactions() async {
    if (_extractedData == null || _isSaving) return;
    final selected = _selectedTransactions;
    if (selected.isEmpty) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      // Use batch create endpoint - currencies are already in the extracted data
      await ApiService.batchCreateTransactions(transactions: selected);

      // Refresh transaction list and balance
      final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
      await transactionProvider.fetchTransactions();
      await transactionProvider.fetchBalance();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully saved ${selected.length} transaction(s)')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _resetVoice() {
    setState(() {
      _transcribedText = null;
      _extractedData = null;
      _selected = [];
      _error = null;
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded),
          onPressed: _isSaving ? null : () => Navigator.pop(context),
        ),
        title: Text(localizations.voiceInputTitle, style: TextStyle(fontSize: 18)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            children: [
              if (!authProvider.isPremium) _buildPremiumUpsell(localizations),

              if (authProvider.isPremium) ...[
                SizedBox(height: 24),
                if (_extractedData == null) _buildRecordingArea(localizations),
                if (_extractedData != null) _buildExtractedResults(localizations),
              ],

              if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(top: 20),
                  decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: scheme.error),
                      SizedBox(width: 12),
                      Expanded(child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumUpsell(AppLocalizations localizations) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Icon(Icons.star_rounded, color: scheme.tertiary, size: 32),
          SizedBox(height: 12),
          Text(
            localizations.premiumFeatureTitle,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: scheme.onTertiaryContainer),
          ),
          SizedBox(height: 8),
          Text(
            localizations.premiumFeatureUpgradeDescVoice,
            style: TextStyle(fontSize: 14, color: scheme.onTertiaryContainer),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/subscription'),
            style: FilledButton.styleFrom(backgroundColor: scheme.tertiary),
            icon: Icon(Icons.upgrade_rounded),
            label: Text(localizations.upgradeNowButton),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingArea(AppLocalizations localizations) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        GestureDetector(
          onTap: _isSaving ? null : (_isRecording ? _stopRecording : (_isProcessing ? null : _startRecording)),
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _isRecording ? _pulseAnimation.value : 1.0,
                child: Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording ? scheme.error : scheme.primary,
                    boxShadow: [
                      BoxShadow(
                        color: (_isRecording ? scheme.error : scheme.primary).withValues(alpha: 0.35),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isProcessing ? Icons.graphic_eq_rounded : (_isRecording ? Icons.stop_rounded : Icons.mic_rounded),
                    size: 52,
                    color: Colors.white,
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: 20),
        Text(
          _isProcessing
              ? localizations.analyzingTransactions
              : (_isRecording ? localizations.recordingStatus : localizations.tapToRecordStatus),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 32),

        if (_isProcessing) Padding(padding: const EdgeInsets.only(top: 8), child: CircularProgressIndicator(color: scheme.primary)),

        if (_transcribedText != null) ...[
          SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: const Color(0x14101815), blurRadius: 3, offset: Offset(0, 1))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.graphic_eq_rounded, color: scheme.primary, size: 18),
                    SizedBox(width: 8),
                    Text(
                      localizations.transcriptionTitle,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text('"$_transcribedText"', style: TextStyle(fontSize: 14, height: 1.5)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildExtractedResults(AppLocalizations localizations) {
    final scheme = Theme.of(context).colorScheme;
    final data = _extractedData!;
    final selectedCount = _selected.where((s) => s).length;
    double selectedTotal = 0;
    for (var i = 0; i < data.transactions.length; i++) {
      if (i < _selected.length && _selected[i]) {
        final t = data.transactions[i];
        selectedTotal += t.type == TransactionType.inflow ? t.amount : -t.amount;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_transcribedText != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: const Color(0x14101815), blurRadius: 3, offset: Offset(0, 1))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.graphic_eq_rounded, color: scheme.primary, size: 16),
                    SizedBox(width: 8),
                    Text('WHAT YOU SAID', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
                  ],
                ),
                SizedBox(height: 6),
                Text('"$_transcribedText"', style: TextStyle(fontSize: 13, height: 1.5)),
              ],
            ),
          ),

        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                'Found ${data.totalCount} Transaction${data.totalCount > 1 ? 's' : ''}',
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: 8),
            Text('from one recording', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
          ],
        ),
        SizedBox(height: 6),
        Text(
          '${localizations.confidenceLabel} ${(data.overallConfidence * 100).toStringAsFixed(0)}%',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        if (data.analysis != null) ...[
          SizedBox(height: 6),
          Text(data.analysis!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
        SizedBox(height: 10),

        if (data.transactions.length > 1)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(14)),
            child: Text(
              'Your sentence held multiple separate spends, so they are logged separately — untick anything you did not mean.',
              style: TextStyle(fontSize: 12, color: scheme.onTertiaryContainer, height: 1.5),
            ),
          ),

        Column(
          children: List.generate(data.transactions.length, (index) {
            final t = data.transactions[index];
            final isOn = index < _selected.length ? _selected[index] : true;
            final isInflow = t.type == TransactionType.inflow;
            final amountColor = isInflow ? scheme.primary : scheme.error;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isOn ? Theme.of(context).cardTheme.color : AppTheme.trackFor(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isOn ? amountColor.withValues(alpha: 0.3) : scheme.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => setState(() => _selected[index] = !isOn),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isInflow ? scheme.primaryContainer : scheme.errorContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(isInflow ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, color: amountColor, size: 20),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.subCategory,
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: 2),
                                Text(
                                  t.mainCategory,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${t.currency.symbol}${formatter.format(t.amount)}',
                                style: AppTheme.money(15, weight: FontWeight.w800, color: amountColor),
                              ),
                              SizedBox(height: 4),
                              StatusPill(
                                label: '${(t.confidence * 100).toStringAsFixed(0)}%',
                                background: _confidenceBg(context, t.confidence),
                                foreground: _confidenceInk(context, t.confidence),
                                dense: true,
                              ),
                            ],
                          ),
                          SizedBox(width: 8),
                          Icon(
                            isOn ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            color: isOn ? amountColor : AppTheme.hintFor(context),
                          ),
                        ],
                      ),
                    ),
                    if (isOn) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(height: 1, color: scheme.outlineVariant),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          t.reasoning ?? DateFormat('yyyy-MM-dd').format(t.date),
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.4),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(16)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Selected total',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.jadeLabel2For(context)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: 8),
              Text(
                '${selectedTotal >= 0 ? '+' : '-'}${formatter.format(selectedTotal.abs())}',
                style: AppTheme.money(18, weight: FontWeight.w800, color: scheme.onPrimaryContainer),
              ),
            ],
          ),
        ),

        SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: (_isSaving || selectedCount == 0) ? null : _saveAllTransactions,
            child: _isSaving
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(localizations.saveTransactionButton),
          ),
        ),
        SizedBox(height: 8),
        TextButton(
          onPressed: _isSaving ? null : _resetVoice,
          child: Text('Record again'),
        ),
      ],
    );
  }

  Color _confidenceBg(BuildContext context, double confidence) {
    final scheme = Theme.of(context).colorScheme;
    if (confidence >= 0.8) return scheme.primaryContainer;
    if (confidence >= 0.5) return scheme.tertiaryContainer;
    return scheme.errorContainer;
  }

  Color _confidenceInk(BuildContext context, double confidence) {
    final scheme = Theme.of(context).colorScheme;
    if (confidence >= 0.8) return scheme.primary;
    if (confidence >= 0.5) return scheme.tertiary;
    return scheme.error;
  }
}
