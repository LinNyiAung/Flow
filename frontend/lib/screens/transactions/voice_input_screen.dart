import 'dart:io';
import 'package:flutter/material.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:google_fonts/google_fonts.dart';
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
  String? _audioPath;
  String? _error;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.microphone.request();
  }

  Future<void> _startRecording() async {
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
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to start recording: ${e.toString()}';
      });
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      
      setState(() {
        _isRecording = false;
        _audioPath = path;
      });

      if (path != null) {
        await _processAudio(path);
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to stop recording: ${e.toString()}';
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
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isProcessing = false;
      });
    }
  }

  Future<void> _saveAllTransactions() async {
    if (_extractedData == null || _isSaving) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      // Use batch create endpoint
      await ApiService.batchCreateTransactions(
        transactions: _extractedData!.transactions,
      );

      // Refresh transaction list and balance
      final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
      await transactionProvider.fetchTransactions();
      await transactionProvider.fetchBalance();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully saved ${_extractedData!.totalCount} transaction(s)'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
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

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF667eea).withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(20),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      icon: Container(
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
                        child: Icon(Icons.arrow_back, color: Color(0xFF333333)),
                      ),
                    ),
                    SizedBox(width: 16),
                    Row(
                      children: [
                        Text(
                          'Voice Input',
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF333333),
                          ),
                        ),
                        SizedBox(width: 8),
                        if (!authProvider.isPremium)
                          Icon(Icons.lock, size: 16, color: Color(0xFFFFD700)),
                          SizedBox(width: 8),
                        if (!authProvider.isPremium)
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Color(0xFFFFD700).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Color(0xFFFFD700), width: 1),
                            ),
                            child: Text(
                              'PREMIUM',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFFD700),
                              ),
                            ),
                          )
                      ],
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Recording Button
                      SizedBox(height: 40),
                      GestureDetector(
                        onTap: _isSaving ? null : (_isRecording ? _stopRecording : _startRecording),
                        child: AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _isRecording ? _pulseAnimation.value : 1.0,
                              child: Container(
                                width: 150,
                                height: 150,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: _isRecording
                                        ? [Colors.red, Colors.red.shade700]
                                        : [Color(0xFF667eea), Color(0xFF764ba2)],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (_isRecording ? Colors.red : Color(0xFF667eea))
                                          .withOpacity(0.4),
                                      spreadRadius: 5,
                                      blurRadius: 20,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _isRecording ? Icons.stop : Icons.mic,
                                  size: 60,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: 24),
                      Text(
                        _isRecording
                            ? 'Recording... Tap to stop'
                            : 'Tap to start recording\nYou can describe multiple transactions',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 40),

                      // Transcribed Text
                      if (_transcribedText != null) ...[
                        Container(
                          width: double.infinity,
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.transcribe, color: Color(0xFF667eea)),
                                  SizedBox(width: 8),
                                  Text(
                                    'Transcription',
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
                                _transcribedText!,
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 20),
                      ],

                      // Processing Indicator
                      if (_isProcessing)
                        Container(
                          padding: EdgeInsets.all(20),
                          child: Column(
                            children: [
                              CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFF667eea),
                                ),
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Analyzing transactions...',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Extracted Data Preview
                      if (_extractedData != null) ...[
                        // Summary Card
                        Container(
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
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.check_circle, color: Colors.white, size: 48),
                              SizedBox(height: 12),
                              Text(
                                'Found ${_extractedData!.totalCount} Transaction${_extractedData!.totalCount > 1 ? 's' : ''}',
                                style: GoogleFonts.poppins(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Confidence: ${(_extractedData!.overallConfidence * 100).toStringAsFixed(0)}%',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.white70,
                                ),
                              ),
                              if (_extractedData!.analysis != null) ...[
                                SizedBox(height: 12),
                                Text(
                                  _extractedData!.analysis!,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: Colors.white70,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ],
                          ),
                        ),
                        SizedBox(height: 20),

                        // Individual Transaction Cards
                        ..._extractedData!.transactions.asMap().entries.map((entry) {
                          final index = entry.key;
                          final transaction = entry.value;
                          return Container(
                            width: double.infinity,
                            margin: EdgeInsets.only(bottom: 16),
                            padding: EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: transaction.type == TransactionType.inflow
                                    ? Colors.green.withOpacity(0.3)
                                    : Colors.red.withOpacity(0.3),
                                width: 2,
                              ),
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
                                Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: transaction.type == TransactionType.inflow
                                            ? Colors.green.withOpacity(0.1)
                                            : Colors.red.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            transaction.type == TransactionType.inflow
                                                ? Icons.arrow_upward
                                                : Icons.arrow_downward,
                                            size: 16,
                                            color: transaction.type == TransactionType.inflow
                                                ? Colors.green
                                                : Colors.red,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            transaction.type.name.toUpperCase(),
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: transaction.type == TransactionType.inflow
                                                  ? Colors.green
                                                  : Colors.red,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Spacer(),
                                    Text(
                                      'Transaction ${index + 1}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 16),
                                Text(
                                  '\$${transaction.amount.toStringAsFixed(2)}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: transaction.type == TransactionType.inflow
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                                SizedBox(height: 12),
                                _buildDetailRow(
                                  Icons.category,
                                  'Category',
                                  '${transaction.mainCategory} > ${transaction.subCategory}',
                                ),
                                _buildDetailRow(
                                  Icons.calendar_today,
                                  'Date',
                                  DateFormat('yyyy-MM-dd').format(transaction.date),
                                ),
                                if (transaction.description != null)
                                  _buildDetailRow(
                                    Icons.notes,
                                    'Description',
                                    transaction.description!,
                                  ),
                                SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.psychology, color: Colors.grey[400], size: 14),
                                    SizedBox(width: 4),
                                    Text(
                                      'Confidence: ${(transaction.confidence * 100).toStringAsFixed(0)}%',
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }).toList(),

                        SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _saveAllTransactions,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF4CAF50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              disabledBackgroundColor: Colors.grey[400],
                            ),
                            child: _isSaving
                                ? CircularProgressIndicator(color: Colors.white)
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle, color: Colors.white),
                                      SizedBox(width: 8),
                                      Text(
                                        'Save ${_extractedData!.totalCount} Transaction${_extractedData!.totalCount > 1 ? 's' : ''}',
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],

                      // Error Display
                      if (_error != null)
                        Container(
                          padding: EdgeInsets.all(16),
                          margin: EdgeInsets.only(top: 20),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: Colors.red[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Color(0xFF333333),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}