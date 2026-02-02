import 'package:flutter/material.dart';
import '../services/localization_service.dart';

enum FeedbackCategory {
  bug,
  feature_request,
  general,
  usability;

  String getDisplayName(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    switch (this) {
      case FeedbackCategory.bug:
        return localizations.feedbackCategoryBug;
      case FeedbackCategory.feature_request:
        return localizations.feedbackCategoryFeature;
      case FeedbackCategory.general:
        return localizations.feedbackCategoryGeneral;
      case FeedbackCategory.usability:
        return localizations.feedbackCategoryUsability;
    }
  }

  String get value {
    // Matches backend enum values
    switch (this) {
      case FeedbackCategory.bug:
        return 'bug';
      case FeedbackCategory.feature_request:
        return 'feature_request';
      case FeedbackCategory.general:
        return 'general';
      case FeedbackCategory.usability:
        return 'usability';
    }
  }
}

class FeedbackCreate {
  final FeedbackCategory category;
  final String message;
  final int? rating;
  final String? screenshotUrl;

  FeedbackCreate({
    required this.category,
    required this.message,
    this.rating,
    this.screenshotUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'category': category.value,
      'message': message,
      'rating': rating,
      'screenshot_url': screenshotUrl,
    };
  }
}