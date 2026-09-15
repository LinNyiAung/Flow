import 'package:flutter/material.dart';
import 'package:frontend/models/feedback.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';
import '../../providers/feedback_provider.dart';
import '../../services/localization_service.dart';

class FeedbackScreen extends StatefulWidget {
  @override
  _FeedbackScreenState createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  FeedbackCategory _selectedCategory = FeedbackCategory.general;
  int _rating = 0;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  String _ratingHelper(AppLocalizations localizations) {
    switch (_rating) {
      case 1:
        return localizations.ratingHelper1;
      case 2:
        return localizations.ratingHelper2;
      case 3:
        return localizations.ratingHelper3;
      case 4:
        return localizations.ratingHelper4;
      case 5:
        return localizations.ratingHelper5;
      default:
        return localizations.ratingHelperDefault;
    }
  }

  void _submitFeedback() async {
    final localizations = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;

    // For general feedback or usability, require a rating
    if ((_selectedCategory == FeedbackCategory.general ||
            _selectedCategory == FeedbackCategory.usability) &&
        _rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.pleaseSelectRating)),
      );
      return;
    }

    final success = await Provider.of<FeedbackProvider>(context, listen: false)
        .submitFeedback(
      category: _selectedCategory,
      message: _messageController.text,
      rating: _rating > 0 ? _rating : null,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.feedbackSubmittedSuccess)),
      );
      Navigator.pop(context);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Provider.of<FeedbackProvider>(context, listen: false).error ??
                localizations.feedbackFailed,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedbackProvider = Provider.of<FeedbackProvider>(context);
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final messageLength = _messageController.text.trim().length;

    return Scaffold(
      appBar: AppBar(title: Text(localizations.sendFeedback)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(Icons.feedback_rounded, color: scheme.onPrimaryContainer, size: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            localizations.weValueYourInput,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            localizations.feedbackHeaderSubtitle,
                            style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer.withValues(alpha: 0.85)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Topic Chips
              Text(
                localizations.whatIsThisRegarding,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: FeedbackCategory.values.map((category) {
                  final isSelected = category == _selectedCategory;
                  return ChoiceChip(
                    label: Text(category.getDisplayName(context)),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedCategory = category),
                    selectedColor: scheme.primary,
                    backgroundColor: scheme.secondaryContainer,
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : scheme.primary,
                    ),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // Star Rating
              Text(
                localizations.howRateExperience,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: List.generate(5, (index) {
                          return GestureDetector(
                            onTap: () => setState(() => _rating = index + 1),
                            child: Icon(
                              index < _rating ? Icons.star_rounded : Icons.star_border_rounded,
                              color: index < _rating ? AppTheme.starFor(context) : AppTheme.hintFor(context),
                              size: 34,
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _ratingHelper(localizations),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Message Input
              Text(
                localizations.tellUsMore,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _messageController,
                maxLines: 5,
                decoration: InputDecoration(hintText: localizations.feedbackHint),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return localizations.pleaseEnterMessage;
                  }
                  if (value.trim().length < 10) {
                    return localizations.feedbackMinLength;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  '$messageLength${localizations.charCountMinimumSuffix}',
                  style: TextStyle(
                    fontSize: 11,
                    color: messageLength >= 10 ? scheme.primary : AppTheme.hintFor(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: feedbackProvider.isLoading ? null : _submitFeedback,
                  child: feedbackProvider.isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(localizations.submitFeedback),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
