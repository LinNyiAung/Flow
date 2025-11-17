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

class User {
  final String id;
  final String name;
  final String email;
  final DateTime createdAt;
  final SubscriptionType subscriptionType;  // NEW
  final DateTime? subscriptionExpiresAt;  // NEW

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.createdAt,
    this.subscriptionType = SubscriptionType.free,  // NEW
    this.subscriptionExpiresAt,  // NEW
  });

  // NEW: Helper method to check if premium is active
  bool get isPremium {
    if (subscriptionType != SubscriptionType.premium) return false;
    if (subscriptionExpiresAt == null) return true; // Lifetime premium
    return subscriptionExpiresAt!.isAfter(DateTime.now());
  }

  // NEW: Helper method to check if subscription is expired
  bool get isExpired {
    if (subscriptionType != SubscriptionType.premium) return false;
    if (subscriptionExpiresAt == null) return false; // Lifetime premium
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
      ),  // NEW
      subscriptionExpiresAt: json['subscription_expires_at'] != null
          ? DateTime.parse(json['subscription_expires_at'])
          : null,  // NEW
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