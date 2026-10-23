import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/platform/platform_info.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/amount_entry_dialog.dart';
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

  /// Name sent with the upload; the extension tells the backend the format.
  String _recordingFilename = 'recording.wav';

  /// Spoken language picked by the user: null = Auto (backend detects),
  /// 'en' or 'my'. Deliberately independent of the UI language.
  String? _spokenLanguage;
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
    // The browser prompts for the microphone itself when recording starts.
    if (PlatformInfo.isWeb) return;
    await Permission.microphone.request();
  }

  Future<void> _startRecording() async {
    final localizations = AppLocalizations.of(context);
    try {
      if (await _audioRecorder.hasPermission()) {
        final AudioEncoder encoder;
        final String path;
        if (PlatformInfo.isWeb) {
          // Records in the browser; stop() returns a blob URL.
          encoder = await _audioRecorder.isEncoderSupported(AudioEncoder.wav)
              ? AudioEncoder.wav
              : AudioEncoder.opus;
          path = '';
          _recordingFilename =
              encoder == AudioEncoder.wav ? 'recording.wav' : 'recording.webm';
        } else {
          final directory = await getTemporaryDirectory();
          encoder = AudioEncoder.wav;
          path = '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';
          _recordingFilename = 'recording.wav';
        }

        await _audioRecorder.start(
          RecordConfig(
            encoder: encoder,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: path,
        );
        if (!mounted) return;

        setState(() {
          _isRecording = true;
          _error = null;
          _transcribedText = null;
          _extractedData = null;
          _selected = [];
        });
      } else if (PlatformInfo.isWeb) {
        // The browser said no (blocked or dismissed): say so instead of
        // leaving the button looking dead.
        if (!mounted) return;
        setState(() => _error = localizations.microphoneAccessDenied);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${localizations.errorStartRecording} ${e.toString()}';
      });
    }
  }

  Future<void> _stopRecording() async {
    final localizations = AppLocalizations.of(context);
    try {
      final path = await _audioRecorder.stop();
      if (!mounted) return;

      setState(() {
        _isRecording = false;
      });

      if (path != null) {
        await _processAudio(path);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${localizations.errorStopRecording} ${e.toString()}';
        _isRecording = false;
      });
    }
  }

  Future<void> _processAudio(String path) async {
    // Only hint the speech-to-text model when the user explicitly chose the
    // spoken language; "Auto" (null) lets the backend detect it.
    final language = _spokenLanguage;
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      // Step 1: Transcribe audio
      // XFile reads both an Android file path and a web blob URL.
      final Uint8List bytes = await XFile(path).readAsBytes();
      final transcription = await ApiService.transcribeAudio(
        bytes,
        filename: _recordingFilename,
        language: language,
      );
      if (!mounted) return;

      setState(() {
        _transcribedText = transcription;
      });

      // Step 2: Extract multiple transaction data
      final extractedData = await ApiService.extractMultipleTransactionsFromText(transcription);
      if (!mounted) return;

      setState(() {
        _extractedData = extractedData;
        _selected = List<bool>.filled(extractedData.transactions.length, true);
        _isProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
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

  /// Enter or correct the amount of item [index] (required when the AI
  /// couldn't read it — the backend rejects amount <= 0).
  Future<void> _enterAmount(int index) async {
    final data = _extractedData;
    if (data == null || index >= data.transactions.length) return;
    final item = data.transactions[index];
    final amount = await showAmountEntryDialog(
      context,
      currency: item.currency,
      initialAmount: item.amount,
    );
    if (amount == null || !mounted || !identical(_extractedData, data)) return;
    final updated = List<ExtractedTransactionData>.of(data.transactions);
    updated[index] = item.copyWith(amount: amount);
    setState(() {
      _extractedData = data.copyWith(transactions: updated);
      if (index < _selected.length) _selected[index] = true;
    });
  }

  Future<void> _saveAllTransactions() async {
    if (_extractedData == null || _isSaving) return;
    final selected = _selectedTransactions;
    if (selected.isEmpty) return;
    if (selected.any((t) => t.needsAmount)) {
      setState(() => _error = AppLocalizations.of(context).amountNeededBeforeSaving);
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      // Use batch create endpoint - currencies are already in the extracted data
      await ApiService.batchCreateTransactions(transactions: selected);
      if (!mounted) return;

      // Refresh transaction list and balance
      final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
      final localizations = AppLocalizations.of(context);
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      await transactionProvider.fetchTransactions();
      await transactionProvider.fetchBalance();

      // Show success message
      messenger.showSnackBar(
        SnackBar(content: Text('${localizations.successfullySavedPrefix} ${selected.length} ${localizations.transactionsSuffix}')),
      );

      if (mounted) navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
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

    // Back is blocked while saving, like the app-bar button, so the batch
    // save can't finish on a screen that's already gone.
    return PopScope(
      canPop: !_isSaving,
      child: Scaffold(
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

  /// Optional spoken-language toggle (Auto / English / မြန်မာ), default Auto.
  Widget _buildSpokenLanguagePicker(AppLocalizations localizations) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = !_isRecording && !_isProcessing && !_isSaving;
    final options = <(String?, String)>[
      (null, localizations.voiceLanguageAuto),
      ('en', localizations.voiceLanguageEnglish),
      ('my', localizations.voiceLanguageMyanmar),
    ];
    return Column(
      children: [
        Text(
          localizations.voiceSpokenLanguageLabel,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
        ),
        SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: options.map((option) {
            final (code, label) = option;
            return ChoiceChip(
              // On the web the Myanmar glyphs come from a fallback font whose
              // line box is taller than the chip, so the label was cut off and
              // faded at the bottom. An explicit line height fixes the box.
              // Left alone on Android, which renders it fine.
              label: Text(
                label,
                style: PlatformInfo.isWeb ? const TextStyle(height: 1.2) : null,
              ),
              selected: _spokenLanguage == code,
              onSelected: enabled ? (_) => setState(() => _spokenLanguage = code) : null,
            );
          }).toList(),
        ),
      ],
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
        SizedBox(height: 20),
        _buildSpokenLanguagePicker(localizations),
        SizedBox(height: 24),

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
    final missingAmount = _selectedTransactions.any((t) => t.needsAmount);
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
                    Text(localizations.whatYouSaidLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
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
                '${localizations.foundLabel} ${data.transactions.length} ${data.transactions.length > 1 ? localizations.transactions : localizations.transactionSingularLabel}',
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: 8),
            Text(localizations.fromOneRecordingLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
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
              localizations.multipleSpendsWarning,
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
                              // Tap to enter / correct the amount.
                              GestureDetector(
                                onTap: _isSaving ? null : () => _enterAmount(index),
                                child: t.needsAmount
                                    ? StatusPill(
                                        label: localizations.amountNeededLabel,
                                        background: scheme.errorContainer,
                                        foreground: scheme.error,
                                        dense: true,
                                      )
                                    : Text(
                                        '${t.currency.symbol}${formatter.format(t.amount)}',
                                        style: AppTheme.money(15, weight: FontWeight.w800, color: amountColor),
                                      ),
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
                      if (t.needsAmount)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: InkWell(
                            onTap: _isSaving ? null : () => _enterAmount(index),
                            child: Text(
                              localizations.amountNeededHint,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.error),
                            ),
                          ),
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
                  localizations.selectedTotalLabel,
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
        if (missingAmount) ...[
          Text(
            localizations.amountNeededBeforeSaving,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.error),
          ),
          SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: (_isSaving || selectedCount == 0 || missingAmount) ? null : _saveAllTransactions,
            child: _isSaving
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(localizations.saveTransactionButton),
          ),
        ),
        SizedBox(height: 8),
        TextButton(
          onPressed: _isSaving ? null : _resetVoice,
          child: Text(localizations.recordAgainButton),
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
