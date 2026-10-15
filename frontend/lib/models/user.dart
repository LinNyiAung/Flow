import 'package:frontend/utils/date_parsing.dart';

// NEW: Add subscription type enum
enum SubscriptionType {
  free,
  premium;

  static SubscriptionType fromString(String value) {
    return SubscriptionType.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => SubscriptionType.free,
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
  final SubscriptionType subscriptionType;
  final DateTime? subscriptionExpiresAt;
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
    this.subscriptionType = SubscriptionType.free,
    this.subscriptionExpiresAt,
    this.defaultCurrency = Currency.usd,
    this.isVerified = false,
    this.hasClaimedFreeTrial = false,
    this.language,
  });

  User copyWith({
    String? name,
    SubscriptionType? subscriptionType,
    DateTime? subscriptionExpiresAt,
    bool clearSubscriptionExpiresAt = false,
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
      subscriptionType: subscriptionType ?? this.subscriptionType,
      subscriptionExpiresAt: clearSubscriptionExpiresAt
          ? null
          : (subscriptionExpiresAt ?? this.subscriptionExpiresAt),
      defaultCurrency: defaultCurrency ?? this.defaultCurrency,
      isVerified: isVerified ?? this.isVerified,
      hasClaimedFreeTrial: hasClaimedFreeTrial ?? this.hasClaimedFreeTrial,
      language: language ?? this.language,
    );
  }

  bool get isPremium {
    if (subscriptionType != SubscriptionType.premium) return false;
    if (subscriptionExpiresAt == null) return true;
    return subscriptionExpiresAt!.isAfter(DateTime.now());
  }

  bool get isExpired {
    if (subscriptionType != SubscriptionType.premium) return false;
    if (subscriptionExpiresAt == null) return false;
    return subscriptionExpiresAt!.isBefore(DateTime.now());
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      name: json['name'],
      email: json['email'],
      createdAt: parseInstant(json['created_at']),
      subscriptionType: SubscriptionType.fromString(
        json['subscription_type'] ?? 'free',
      ),
      subscriptionExpiresAt: parseInstantOrNull(json['subscription_expires_at']),
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
      'subscription_type': subscriptionType.name,
      'subscription_expires_at': subscriptionExpiresAt?.toIso8601String(),
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

class SubscriptionStatus {
  final SubscriptionType subscriptionType;
  final bool isPremium;
  final DateTime? expiresAt;
  final bool isExpired;

  SubscriptionStatus({
    required this.subscriptionType,
    required this.isPremium,
    this.expiresAt,
    required this.isExpired,
  });

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatus(
      subscriptionType: SubscriptionType.fromString(
        json['subscription_type'] ?? 'free',
      ),
      isPremium: json['is_premium'] ?? false,
      expiresAt: parseInstantOrNull(json['expires_at']),
      isExpired: json['is_expired'] ?? false,
    );
  }
}