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
  thb;  // ADD THIS LINE

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
      case Currency.thb:  // ADD THIS CASE
        return '฿';
    }
  }
  
  String get displayName {
    switch (this) {
      case Currency.usd:
        return 'US Dollar (USD)';
      case Currency.mmk:
        return 'Myanmar Kyat (MMK)';
      case Currency.thb:  // ADD THIS CASE
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
  final Currency defaultCurrency;  // NEW

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.createdAt,
    this.subscriptionType = SubscriptionType.free,
    this.subscriptionExpiresAt,
    this.defaultCurrency = Currency.usd,  // NEW
  });

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
      createdAt: DateTime.parse(json['created_at']),
      subscriptionType: SubscriptionType.fromString(
        json['subscription_type'] ?? 'free',
      ),
      subscriptionExpiresAt: json['subscription_expires_at'] != null
          ? DateTime.parse(json['subscription_expires_at'])
          : null,
      defaultCurrency: Currency.fromString(  // NEW
        json['default_currency'] ?? 'usd',
      ),
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
      'default_currency': defaultCurrency.name,  // NEW
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

// NEW: Subscription status response
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
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'])
          : null,
      isExpired: json['is_expired'] ?? false,
    );
  }
}