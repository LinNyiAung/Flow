import 'package:flutter/material.dart';
import 'package:frontend/models/feedback.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/feedback_provider.dart';
import '../../services/responsive_helper.dart';
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
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _submitFeedback() async {
    final localizations = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    
    // For general feedback or usability, require a rating
    if ((_selectedCategory == FeedbackCategory.general || 
         _selectedCategory == FeedbackCategory.usability) && 
         _rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.pleaseSelectRating),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
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
        SnackBar(
          content: Text(localizations.feedbackSubmittedSuccess),
          backgroundColor: Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Provider.of<FeedbackProvider>(context, listen: false).error ?? 
            localizations.feedbackFailed,
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final responsive = ResponsiveHelper(context);
    final feedbackProvider = Provider.of<FeedbackProvider>(context);
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          localizations.sendFeedback,
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
      ),
      body: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF667eea).withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: responsive.padding(all: 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Card
                Container(
                  padding: responsive.padding(all: 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                    ),
                    borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF667eea).withOpacity(0.3),
                        spreadRadius: 2,
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: responsive.padding(all: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.feedback_outlined,
                          color: Colors.white,
                          size: responsive.icon32,
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localizations.weValueYourInput,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              localizations.feedbackHeaderSubtitle,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs12,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 24),

                // Category Dropdown
                Text(
                  localizations.whatIsThisRegarding,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<FeedbackCategory>(
                      value: _selectedCategory,
                      isExpanded: true,
                      icon: Icon(Icons.keyboard_arrow_down, color: Color(0xFF667eea)),
                      items: FeedbackCategory.values.map((category) {
                        return DropdownMenuItem(
                          value: category,
                          child: Text(
                            // FIXED: Use getDisplayName(context) instead of .displayName
                            category.getDisplayName(context),
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs14,
                              color: Color(0xFF333333),
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedCategory = value);
                        }
                      },
                    ),
                  ),
                ),

                SizedBox(height: 24),

                // Star Rating
                Text(
                  localizations.howRateExperience,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  padding: responsive.padding(all: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(5, (index) {
                      return GestureDetector(
                        onTap: () {
                          setState(() => _rating = index + 1);
                        },
                        child: Icon(
                          index < _rating ? Icons.star : Icons.star_border,
                          color: index < _rating ? Color(0xFFFFD700) : Colors.grey[400],
                          size: responsive.icon32,
                        ),
                      );
                    }),
                  ),
                ),

                SizedBox(height: 24),

                // Message Input
                Text(
                  localizations.tellUsMore,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                SizedBox(height: 8),
                TextFormField(
                  controller: _messageController,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: localizations.feedbackHint,
                    hintStyle: GoogleFonts.poppins(color: Colors.grey[400]),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                      borderSide: BorderSide(color: Color(0xFF667eea), width: 2),
                    ),
                  ),
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

                SizedBox(height: 32),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: responsive.cardHeight(baseHeight: 50),
                  child: ElevatedButton(
                    onPressed: feedbackProvider.isLoading ? null : _submitFeedback,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF667eea),
                      disabledBackgroundColor: Colors.grey[300],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                      ),
                      elevation: 4,
                    ),
                    child: feedbackProvider.isLoading
                        ? SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            localizations.submitFeedback,
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
          ),
        ),
      ),
    );
  }
}