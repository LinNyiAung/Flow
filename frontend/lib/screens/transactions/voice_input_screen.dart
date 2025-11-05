import 'dart:io';
import 'package:flutter/material.dart';
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
  bool _isSaving = false; // Add this flag
  String? _transcribedText;
  ExtractedTransactionData? _extractedData;
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

      // Step 2: Extract transaction data
      final extractedData = await ApiService.extractTransactionFromText(transcription);
      
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

  Future<void> _saveTransaction() async {
    if (_extractedData == null || _isSaving) return; // Prevent multiple calls

    setState(() {
      _isSaving = true; // Set saving flag
      _error = null;
    });

    final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
    
    final success = await transactionProvider.createTransaction(
      type: _extractedData!.type,
      mainCategory: _extractedData!.mainCategory,
      subCategory: _extractedData!.subCategory,
      date: _extractedData!.date,
      description: _extractedData!.description,
      amount: _extractedData!.amount,
      context: context,
    );

    if (success) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _isSaving = false; // Reset flag on error
        _error = transactionProvider.error ?? 'Failed to save transaction';
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
                      onPressed: _isSaving ? null : () => Navigator.pop(context), // Disable back button while saving
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
                    Text(
                      'Voice Input',
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF333333),
                      ),
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
                        onTap: _isSaving ? null : (_isRecording ? _stopRecording : _startRecording), // Disable while saving
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
                            : 'Tap to start recording',
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
                                'Analyzing transaction...',
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Extracted Transaction',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 16),
                              _buildDataRow('Type', _extractedData!.type.name.toUpperCase()),
                              _buildDataRow('Amount', '\$${_extractedData!.amount.toStringAsFixed(2)}'),
                              _buildDataRow('Category', '${_extractedData!.mainCategory} > ${_extractedData!.subCategory}'),
                              _buildDataRow('Date', DateFormat('yyyy-MM-dd').format(_extractedData!.date)),
                              if (_extractedData!.description != null)
                                _buildDataRow('Description', _extractedData!.description!),
                              SizedBox(height: 12),
                              Row(
                                children: [
                                  Icon(Icons.psychology, color: Colors.white70, size: 16),
                                  SizedBox(width: 8),
                                  Text(
                                    'Confidence: ${(_extractedData!.confidence * 100).toStringAsFixed(0)}%',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _saveTransaction, // Disable when saving
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF4CAF50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              disabledBackgroundColor: Colors.grey[400], // Style for disabled state
                            ),
                            child: _isSaving
                                ? CircularProgressIndicator(color: Colors.white) // Show loading indicator
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle, color: Colors.white),
                                      SizedBox(width: 8),
                                      Text(
                                        'Save Transaction',
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

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}