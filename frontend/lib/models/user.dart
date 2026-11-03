import 'package:frontend/utils/date_parsing.dart';

/// The plans a user can be on. The server stores `free`, `plus` or `pro`;
/// anything else (e.g. a stray legacy value) is treated as Free.
enum Plan {
  free,
  plus,
  pro;

  static Plan fromString(String? value) {
    final name = value?.toLowerCase();
    return Plan.values.firstWhere(
      (e) => e.name == name,
      orElse: () => Plan.free,
    );
  }
}

enum Currency {
  usd,
  mmk,
  thb;

  static Currency fromString(String value) {
    return Currency.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => Currency.usd,
    );
  }

  String get symbol {
    switch (this) {
      case Currency.usd:
        return '\$';
      case Currency.mmk:
        return 'K';
      case Currency.thb:
        return '฿';
    }
  }

  String get displayName {
    switch (this) {
      case Currency.usd:
        return 'US Dollar (USD)';
      case Currency.mmk:
        return 'Myanmar Kyat (MMK)';
      case Currency.thb:
        return 'Thai Baht (THB)';
    }
  }
}

class User {
  final String id;
  final String name;
  final String email;
  final DateTime createdAt;

  /// The plan stored on the account. An expired Plus / Pro plan is still
  /// stored as such until the server's hourly job moves it to Free: use
  /// [effectivePlan] (or [isPaid] / [isPro]) to know what the user has now.
  final Plan plan;
  final DateTime? subscriptionExpiresAt;

  /// True while the user is on the one-time Plus trial. `/api/auth/me` does
  /// not carry this; it is filled in from `/api/plan` (see
  /// AuthProvider.applyPlanStatus).
  final bool isTrial;
  final DateTime? trialEndsAt;
  final Currency defaultCurrency;
  final bool isVerified;
  final bool hasClaimedFreeTrial;

  /// Server-side UI language preference ('en' | 'my'), when provided.
  final String? language;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.createdAt,
    this.plan = Plan.free,
    this.subscriptionExpiresAt,
    this.isTrial = false,
    this.trialEndsAt,
    this.defaultCurrency = Currency.usd,
    this.isVerified = false,
    this.hasClaimedFreeTrial = false,
    this.language,
  });

  User copyWith({
    String? name,
    Plan? plan,
    DateTime? subscriptionExpiresAt,
    bool clearSubscriptionExpiresAt = false,
    bool? isTrial,
    DateTime? trialEndsAt,
    bool clearTrialEndsAt = false,
    Currency? defaultCurrency,
    bool? isVerified,
    bool? hasClaimedFreeTrial,
    String? language,
  }) {
    return User(
      id: id,
      name: name ?? this.name,
      email: email,
      createdAt: createdAt,
      plan: plan ?? this.plan,
      subscriptionExpiresAt: clearSubscriptionExpiresAt
          ? null
          : (subscriptionExpiresAt ?? this.subscriptionExpiresAt),
      isTrial: isTrial ?? this.isTrial,
      trialEndsAt:
          clearTrialEndsAt ? null : (trialEndsAt ?? this.trialEndsAt),
      defaultCurrency: defaultCurrency ?? this.defaultCurrency,
      isVerified: isVerified ?? this.isVerified,
      hasClaimedFreeTrial: hasClaimedFreeTrial ?? this.hasClaimedFreeTrial,
      language: language ?? this.language,
    );
  }

  /// The plan the user has right now: a paid plan whose end date has passed
  /// counts as Free at once (the server does the same).
  Plan get effectivePlan {
    if (plan == Plan.free) return Plan.free;
    final expires = subscriptionExpiresAt;
    if (expires != null && !expires.isAfter(DateTime.now())) return Plan.free;
    return plan;
  }

  bool get isPaid => effectivePlan != Plan.free;
  bool get isPro => effectivePlan == Plan.pro;

  /// A paid plan that has run out and is still stored as paid.
  bool get isExpired => plan != Plan.free && effectivePlan == Plan.free;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      name: json['name'],
      email: json['email'],
      createdAt: parseInstant(json['created_at']),
      plan: Plan.fromString(json['subscription_type'] as String?),
      subscriptionExpiresAt: parseInstantOrNull(json['subscription_expires_at']),
      isTrial: json['is_trial'] == true,
      trialEndsAt: parseInstantOrNull(json['trial_ends_at']),
      defaultCurrency: Currency.fromString(json['default_currency'] ?? 'usd'),
      isVerified: json['is_verified'] ?? false,
      hasClaimedFreeTrial: json['has_claimed_free_trial'] == true,
      language: json['language'] is String ? json['language'] as String : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'created_at': createdAt.toIso8601String(),
      'subscription_type': plan.name,
      'subscription_expires_at': subscriptionExpiresAt?.toIso8601String(),
      'is_trial': isTrial,
      'trial_ends_at': trialEndsAt?.toIso8601String(),
      'default_currency': defaultCurrency.name,
      'is_verified': isVerified,
      'has_claimed_free_trial': hasClaimedFreeTrial,
      if (language != null) 'language': language,
    };
  }
}
class AuthResponse {
  final String accessToken;
  final String tokenType;
  final User user;

  AuthResponse({
    required this.accessToken,
    required this.tokenType,
    required this.user,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      accessToken: json['access_token'],
      tokenType: json['token_type'],
      user: User.fromJson(json['user']),
    );
  }
}

/// `GET /api/auth/subscription-status`. [plan] is what the user has right now
/// (an expired Plus / Pro plan is Free); [storedPlan] is what is stored.
class SubscriptionStatus {
  final Plan storedPlan;
  final Plan plan;
  final bool isPaid;
  final bool isTrial;
  final DateTime? expiresAt;
  final bool isExpired;

  SubscriptionStatus({
    required this.storedPlan,
    required this.plan,
    required this.isPaid,
    required this.isTrial,
    this.expiresAt,
    required this.isExpired,
  });

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    final stored = Plan.fromString(json['subscription_type'] as String?);
    final plan = json['plan'] is String
        ? Plan.fromString(json['plan'] as String)
        : stored;
    return SubscriptionStatus(
      storedPlan: stored,
      plan: plan,
      isPaid: json['is_paid'] ?? plan != Plan.free,
      isTrial: json['is_trial'] == true,
      expiresAt: parseInstantOrNull(json['expires_at']),
      isExpired: json['is_expired'] ?? false,
    );
  }
}