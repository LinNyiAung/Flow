enum FeedbackCategory {
  bug,
  feature_request,
  general,
  usability;

  String get displayName {
    switch (this) {
      case FeedbackCategory.bug:
        return 'Report a Bug';
      case FeedbackCategory.feature_request:
        return 'Feature Request';
      case FeedbackCategory.general:
        return 'General Feedback';
      case FeedbackCategory.usability:
        return 'Usability Issue';
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