import 'dart:io';
import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:frontend/widgets/app_list_row.dart';
import 'package:frontend/widgets/status_pill.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/api_service.dart';
import '../../providers/transaction_provider.dart';
import '../../models/transaction.dart';
import '../../models/voice_image_models.dart';
import 'package:intl/intl.dart';

class ImageInputScreen extends StatefulWidget {
  @override
  _ImageInputScreenState createState() => _ImageInputScreenState();
}

class _ImageInputScreenState extends State<ImageInputScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  File? _selectedImage;
  bool _isProcessing = false;
  bool _isSaving = false;
  ExtractedTransactionData? _extractedData;
  String? _error;
  final formatter = NumberFormat("#,##0.00", "en_US");

  @override
  void initState() {
    super.initState();
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
    if (_extractedData == null || _isSaving) return;

    setState(() {
      _isSaving = true;
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
      currency: _extractedData!.currency, // Use detected currency from AI
      context: context,
    );

    if (success) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _isSaving = false;
        _error = transactionProvider.error ?? 'Failed to save transaction';
      });
    }
  }

  void _showImageSourceDialog() {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (_isSaving) return; // Don't show dialog while saving

    showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add a receipt', style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: const Color(0x14101815), blurRadius: 3, offset: Offset(0, 1))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  AppListRow(
                    icon: Icons.photo_camera_rounded,
                    iconBg: scheme.secondaryContainer,
                    title: localizations.cameraListTileTitle,
                    subtitle: localizations.cameraListTileSubtitle,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _pickImageFromCamera();
                    },
                  ),
                  Divider(height: 1, indent: 70),
                  AppListRow(
                    icon: Icons.photo_library_rounded,
                    iconBg: scheme.secondaryContainer,
                    title: localizations.galleryListTileTitle,
                    subtitle: localizations.galleryListTileSubtitle,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _pickImageFromGallery();
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
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
        title: Text(localizations.imageInputTitle, style: TextStyle(fontSize: 18)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            children: [
              if (!authProvider.isPremium) _buildPremiumUpsell(localizations),

              if (authProvider.isPremium) ...[
                if (_selectedImage == null) _buildEmptyCapture(localizations),
                if (_selectedImage != null) _buildImagePreview(localizations),

                if (_isProcessing) _buildScanningPlaceholder(localizations),

                if (_extractedData != null) _buildExtractedResult(localizations),
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
      margin: const EdgeInsets.only(top: 8, bottom: 8),
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
            localizations.premiumFeatureUpgradeDescImg,
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

  Widget _buildEmptyCapture(AppLocalizations localizations) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(height: 16),
        GestureDetector(
          onTap: _isSaving ? null : _showImageSourceDialog,
          child: CustomPaint(
            painter: _DashedRoundedRectPainter(color: scheme.outline, radius: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 52, horizontal: 20),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Icon(Icons.add_a_photo_rounded, size: 48, color: scheme.primary),
                  SizedBox(height: 14),
                  Text(
                    localizations.tapToAddImagePlaceholder,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 6),
                  Text(
                    localizations.cameraOrGalleryPlaceholder,
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppTheme.trackFor(context), borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('WHAT WE READ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
              SizedBox(height: 6),
              Text(
                'Merchant, date, amount and category — nothing is saved until you confirm.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreview(AppLocalizations localizations) {
    return Column(
      children: [
        SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.file(_selectedImage!, width: double.infinity, height: 220, fit: BoxFit.cover),
        ),
        SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _isSaving ? null : _showImageSourceDialog,
          icon: Icon(Icons.refresh_rounded),
          label: Text(localizations.chooseDifferentImageButton),
        ),
      ],
    );
  }

  Widget _buildScanningPlaceholder(AppLocalizations localizations) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(color: AppTheme.trackFor(context), borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Icon(Icons.document_scanner_rounded, size: 40, color: scheme.primary),
          SizedBox(height: 14),
          Text(localizations.analyzingReceipt, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          SizedBox(height: 14),
          SizedBox(
            width: 160,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(color: scheme.primary, backgroundColor: scheme.primaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtractedResult(AppLocalizations localizations) {
    final scheme = Theme.of(context).colorScheme;
    final data = _extractedData!;
    final isInflow = data.type == TransactionType.inflow;
    final amountColor = isInflow ? scheme.primary : scheme.error;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(18),
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
              Expanded(child: Text(localizations.extractedTransactionTitle, style: Theme.of(context).textTheme.titleMedium)),
              StatusPill(
                label: '${(data.confidence * 100).toStringAsFixed(0)}%',
                background: _confidenceBg(context, data.confidence),
                foreground: _confidenceInk(context, data.confidence),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            '${data.currency.symbol}${formatter.format(data.amount)}',
            style: AppTheme.money(28, weight: FontWeight.w800, color: amountColor),
          ),
          SizedBox(height: 14),
          _dataRow(localizations.dataLabelType, data.type.name.toUpperCase()),
          _dataRow(localizations.currency, data.currency.displayName),
          _dataRow(localizations.dataLabelCategory, '${data.mainCategory} > ${data.subCategory}'),
          _dataRow(localizations.dataLabelDate, DateFormat('yyyy-MM-dd').format(data.date)),
          if (data.description != null) _dataRow(localizations.dataLabelDescription, data.description!),
          if (data.reasoning != null) ...[
            SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.trackFor(context), borderRadius: BorderRadius.circular(10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline_rounded, size: 16, color: scheme.onSurfaceVariant),
                      SizedBox(width: 8),
                      Text(
                        localizations.aiReasoningLabel,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(data.reasoning!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
          SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isSaving ? null : _saveTransaction,
              child: _isSaving
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(localizations.saveTransactionButton),
            ),
          ),
          SizedBox(height: 8),
          TextButton(
            onPressed: _isSaving ? null : _showImageSourceDialog,
            child: Text('Use a different photo'),
          ),
        ],
      ),
    );
  }

  Widget _dataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
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

/// Draws a dashed rounded-rect outline — matches the mockup's dashed
/// "add a photo" drop zone, which plain [Border.all] cannot express.
class _DashedRoundedRectPainter extends CustomPainter {
  const _DashedRoundedRectPainter({required this.color, this.radius = 20});

  final Color color;
  final double radius;

  static const _strokeWidth = 2.0;
  static const _dashWidth = 6.0;
  static const _gapWidth = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(_strokeWidth / 2),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + _dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + _gapWidth;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedRectPainter oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
}
