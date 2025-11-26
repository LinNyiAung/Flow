import 'dart:io';
import 'package:flutter/material.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/api_service.dart';
import '../../providers/transaction_provider.dart';
import '../../models/voice_image_models.dart';
import 'package:intl/intl.dart';

class ImageInputScreen extends StatefulWidget {
  @override
  _ImageInputScreenState createState() => _ImageInputScreenState();
}

class _ImageInputScreenState extends State<ImageInputScreen>
    with TickerProviderStateMixin {
  final ImagePicker _imagePicker = ImagePicker();
  File? _selectedImage;
  bool _isProcessing = false;
  bool _isSaving = false; // Add this flag
  ExtractedTransactionData? _extractedData;
  String? _error;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  Currency _selectedCurrency = Currency.usd;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      setState(() {
        _selectedCurrency = authProvider.defaultCurrency;
      });
    });

    _animationController.forward();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.camera.request();
    await Permission.photos.request();
  }

  Future<void> _pickImageFromCamera() async {
    final localizations = AppLocalizations.of(context);
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _error = null;
          _extractedData = null;
        });
        await _processImage();
      }
    } catch (e) {
      setState(() {
        _error = '${localizations.errorCaptureImage} ${e.toString()}';
      });
    }
  }

  Future<void> _pickImageFromGallery() async {
    final localizations = AppLocalizations.of(context);
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _error = null;
          _extractedData = null;
        });
        await _processImage();
      }
    } catch (e) {
      setState(() {
        _error = '${localizations.errorPickImage} ${e.toString()}';
      });
    }
  }

  Future<void> _processImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final extractedData = await ApiService.extractTransactionFromImage(_selectedImage!);
      
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
      currency: _selectedCurrency,
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

  void _showImageSourceDialog() {
    final localizations = AppLocalizations.of(context);
    if (_isSaving) return; // Don't show dialog while saving
    
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                localizations.chooseImageSourceModalTitle,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF333333),
                ),
              ),
              SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Color(0xFF667eea).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.camera_alt, color: Color(0xFF667eea)),
                ),
                title: Text(
                  localizations.cameraListTileTitle,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  localizations.cameraListTileSubtitle,
                  style: GoogleFonts.poppins(fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageFromCamera();
                },
              ),
              ListTile(
                leading: Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Color(0xFF667eea).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.photo_library, color: Color(0xFF667eea)),
                ),
                title: Text(
                  localizations.galleryListTileTitle,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  localizations.galleryListTileSubtitle,
                  style: GoogleFonts.poppins(fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageFromGallery();
                },
              ),
              SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final localizations = AppLocalizations.of(context);
    
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
                    Row(
                      children: [
                        Text(
                          localizations.imageInputTitle,
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
                              localizations.premium,
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
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        children: [
                        if (!authProvider.isPremium)
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(20),
                            margin: EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0xFFFFD700).withOpacity(0.3),
                                  spreadRadius: 2,
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.star, color: Colors.white, size: 48),
                                SizedBox(height: 12),
                                Text(
                                  localizations.premiumFeatureTitle,
                                  style: GoogleFonts.poppins(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  localizations.premiumFeatureUpgradeDescImg,
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () => Navigator.pushNamed(context, '/subscription'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Color(0xFFFFD700),
                                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.upgrade),
                                      SizedBox(width: 8),
                                      Text(
                                        localizations.upgradeNowButton,
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Image Selection Area
                          if (authProvider.isPremium)
                          if (_selectedImage == null) ...[
                            SizedBox(height: 40),
                            GestureDetector(
                              onTap: _isSaving ? null : _showImageSourceDialog, // Disable while saving
                              child: Container(
                                width: double.infinity,
                                height: 250,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0xFF667eea).withOpacity(0.3),
                                      spreadRadius: 2,
                                      blurRadius: 12,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_photo_alternate,
                                      size: 80,
                                      color: Colors.white,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      localizations.tapToAddImagePlaceholder,
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      localizations.cameraOrGalleryPlaceholder,
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ] else ...[
                            // Selected Image Preview
                            Container(
                              width: double.infinity,
                              height: 300,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.2),
                                    spreadRadius: 2,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Image.file(
                                  _selectedImage!,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _isSaving ? null : _showImageSourceDialog, // Disable while saving
                              icon: Icon(Icons.refresh, color: Colors.white),
                              label: Text(
                                localizations.chooseDifferentImageButton,
                                style: GoogleFonts.poppins(color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(0xFF667eea),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                disabledBackgroundColor: Colors.grey[400], // Style for disabled state
                              ),
                            ),
                          ],

                          SizedBox(height: 30),

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
                                    localizations.analyzingReceipt,
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
                                    localizations.extractedTransactionTitle,
                                    style: GoogleFonts.poppins(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: 16),
                                  _buildDataRow(localizations.dataLabelType, _extractedData!.type.name.toUpperCase()),
                                  _buildDataRow(localizations.dataLabelAmount, '\$${_extractedData!.amount.toStringAsFixed(2)}'),
                                  _buildDataRow(localizations.dataLabelCategory, '${_extractedData!.mainCategory} > ${_extractedData!.subCategory}'),
                                  _buildDataRow(localizations.dataLabelDate, DateFormat('yyyy-MM-dd').format(_extractedData!.date)),
                                  if (_extractedData!.description != null)
                                    _buildDataRow(localizations.dataLabelDescription, _extractedData!.description!),
                                  if (_extractedData!.reasoning != null) ...[
                                    SizedBox(height: 12),
                                    Container(
                                      padding: EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.lightbulb_outline, 
                                                color: Colors.white70, size: 16),
                                              SizedBox(width: 8),
                                              Text(
                                                localizations.aiReasoningLabel,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 12,
                                                  color: Colors.white70,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            _extractedData!.reasoning!,
                                            style: GoogleFonts.poppins(
                                              fontSize: 11,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Icon(Icons.psychology, color: Colors.white70, size: 16),
                                      SizedBox(width: 8),
                                      Text(
                                        '${localizations.confidenceLabel} ${(_extractedData!.confidence * 100).toStringAsFixed(0)}%',
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
                                            localizations.saveTransactionButton,
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