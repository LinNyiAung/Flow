import 'package:frontend/models/user.dart';
import 'package:frontend/utils/contact_details.dart';
import 'package:frontend/utils/date_parsing.dart';

/// The quota feature keys the server uses (`GET /api/plan`, limit errors).
class PlanFeature {
  PlanFeature._();

  static const String chat = 'chat';
  static const String chatAdvanced = 'chat_advanced';
  static const String insightMonthly = 'insight_monthly';
  static const String insightWeekly = 'insight_weekly';
  static const String insightTranslation = 'insight_translation';
  static const String insightCustom = 'insight_custom';
  static const String entry = 'entry';
  static const String budgetSuggestion = 'budget_suggestion';
  static const String reports = 'reports';

  /// In the order the Upgrade screen lists them.
  static const List<String> all = [
    chat,
    chatAdvanced,
    insightMonthly,
    insightWeekly,
    insightTranslation,
    insightCustom,
    entry,
    budgetSuggestion,
    reports,
  ];
}

int? _asInt(dynamic value) => value is num ? value.toInt() : null;

/// One feature's allowance for the signed-in user this period.
///
/// `mode` is `locked` (not in the plan), `included` (no count) or `counted`
/// (a quota per `period`, `week` or `month`). Locked and included features
/// carry no counts.
class FeatureAllowance {
  static const String modeLocked = 'locked';
  static const String modeIncluded = 'included';
  static const String modeCounted = 'counted';

  final String mode;
  final int? limit;
  final String? period;
  final int? used;

  /// Never negative: the owner can lower a limit below what a user already
  /// used, and the app then shows "0 left", not a negative number.
  final int? remaining;
  final DateTime? resetsAt;

  const FeatureAllowance({
    required this.mode,
    this.limit,
    this.period,
    this.used,
    this.remaining,
    this.resetsAt,
  });

  bool get isLocked => mode == modeLocked;
  bool get isIncluded => mode == modeIncluded;
  bool get isCounted => mode == modeCounted;

  /// A counted allowance with nothing left this period.
  bool get isExhausted => isCounted && (remaining ?? 1) <= 0;

  factory FeatureAllowance.fromJson(Map<String, dynamic> json) {
    final limit = _asInt(json['limit']);
    final used = _asInt(json['used']);
    var remaining = _asInt(json['remaining']);
    if (remaining == null && limit != null && used != null) {
      remaining = limit - used;
    }
    if (remaining != null && remaining < 0) remaining = 0;
    return FeatureAllowance(
      mode: json['mode'] is String ? json['mode'] as String : modeIncluded,
      limit: limit,
      period: json['period'] is String ? json['period'] as String : null,
      used: used,
      remaining: remaining,
      resetsAt: parseInstantOrNull(json['resets_at']),
    );
  }
}

/// One plan's limit for one feature, from the `catalog` of `GET /api/plan`.
class CatalogLimit {
  final String mode;
  final int? quota;
  final String? period;

  const CatalogLimit({required this.mode, this.quota, this.period});

  bool get isLocked => mode == FeatureAllowance.modeLocked;
  bool get isIncluded => mode == FeatureAllowance.modeIncluded;
  bool get isCounted => mode == FeatureAllowance.modeCounted;

  factory CatalogLimit.fromJson(Map<String, dynamic> json) {
    return CatalogLimit(
      mode: json['mode'] is String
          ? json['mode'] as String
          : FeatureAllowance.modeIncluded,
      quota: _asInt(json['quota']),
      period: json['period'] is String ? json['period'] as String : null,
    );
  }
}

/// One plan's price in kyat, from the `prices` of `GET /api/plan`, set by the
/// owner in the admin panel. Either is null when not set: then the app shows
/// no price. Free never has one; a yearly price comes only with a monthly one.
class PlanPrice {
  final int? monthlyMmk;
  final int? yearlyMmk;

  const PlanPrice({this.monthlyMmk, this.yearlyMmk});

  static const PlanPrice none = PlanPrice();

  bool get hasMonthly => monthlyMmk != null;
  bool get hasYearly => monthlyMmk != null && yearlyMmk != null;

  /// How much the yearly price saves against 12 monthly payments, in whole
  /// percent (`round((1 - yearly / (12 * monthly)) * 100)`); null without
  /// both prices. Shown only when it is above 0.
  int? get savePercent {
    final monthly = monthlyMmk, yearly = yearlyMmk;
    if (monthly == null || yearly == null) return null;
    return ((1 - yearly / (12 * monthly)) * 100).round();
  }

  /// Missing or unreadable values are "not set", so an older server (no
  /// `prices`) shows no price.
  factory PlanPrice.fromJson(dynamic json) {
    if (json is! Map) return none;
    int? positive(dynamic value) {
      final n = _asInt(value);
      return n != null && n > 0 ? n : null;
    }

    final monthly = positive(json['monthly_mmk']);
    return PlanPrice(monthlyMmk: monthly, yearlyMmk: monthly == null ? null : positive(json['yearly_mmk']));
  }
}

/// The price a user picked on an upgrade request (`billing`).
class PlanBilling {
  PlanBilling._();

  static const String month = 'month';
  static const String year = 'year';
}

/// The user's pending request to be moved to Plus or Pro (`upgrade_request` of
/// `GET /api/plan`, and the answer of `POST /api/plan/upgrade-request`).
/// Upgrades are manual: the owner sees the request in the admin panel.
class UpgradeRequest {
  final Plan plan;
  final String? note;

  /// The Viber number the user gave (`+` and digits) for the owner to contact
  /// them on; null when they gave none (the owner emails them instead).
  final String? viberNumber;

  /// [PlanBilling.month] or [PlanBilling.year], the price the user picked;
  /// null when the plan had no price.
  final String? billing;
  final DateTime createdAt;

  const UpgradeRequest({
    required this.plan,
    this.note,
    this.viberNumber,
    this.billing,
    required this.createdAt,
  });

  /// Null when [json] is not a request (no pending request, or an unreadable one).
  static UpgradeRequest? tryParse(dynamic json) {
    if (json is! Map) return null;
    final plan = Plan.fromString(json['plan'] as String?);
    final createdAt = parseInstantOrNull(json['created_at']);
    if (plan == Plan.free || createdAt == null) return null;
    final note = json['note'];
    final viber = json['viber_number'];
    final billing = json['billing'];
    return UpgradeRequest(
      plan: plan,
      note: note is String && note.trim().isNotEmpty ? note : null,
      viberNumber: viber is String && viber.trim().isNotEmpty ? viber.trim() : null,
      billing: billing == PlanBilling.month || billing == PlanBilling.year ? billing as String : null,
      createdAt: createdAt,
    );
  }
}

/// `GET /api/plan`: the user's plan, trial state, each feature's allowance
/// this period, every plan's limits (for the Upgrade screen, so no number is
/// hard-coded in the app), every plan's price, the upgrade contact message per
/// language and the pending upgrade request, if any.
class PlanStatus {
  final Plan plan;
  final DateTime? expiresAt;
  final bool isTrial;
  final DateTime? trialEndsAt;
  final Map<String, FeatureAllowance> features;
  final Map<Plan, Map<String, CatalogLimit>> catalog;

  /// The price of each plan the server listed; see [priceOf].
  final Map<Plan, PlanPrice> prices;

  /// Language code ('en' | 'my') -> message.
  final Map<String, String> upgradeContact;

  /// The owner's own email and Viber number, for "Contact us directly".
  final OwnerContact ownerContact;

  /// The user's pending request for Plus or Pro; null when there is none.
  final UpgradeRequest? upgradeRequest;

  const PlanStatus({
    required this.plan,
    this.expiresAt,
    this.isTrial = false,
    this.trialEndsAt,
    this.features = const {},
    this.catalog = const {},
    this.prices = const {},
    this.upgradeContact = const {},
    this.ownerContact = OwnerContact.none,
    this.upgradeRequest,
  });

  /// This status with [request] as the pending upgrade request (null clears it).
  PlanStatus withUpgradeRequest(UpgradeRequest? request) => PlanStatus(
        plan: plan,
        expiresAt: expiresAt,
        isTrial: isTrial,
        trialEndsAt: trialEndsAt,
        features: features,
        catalog: catalog,
        prices: prices,
        upgradeContact: upgradeContact,
        ownerContact: ownerContact,
        upgradeRequest: request,
      );

  bool get isPaid => plan != Plan.free;
  bool get isPro => plan == Plan.pro;

  FeatureAllowance? feature(String key) => features[key];

  /// [plan]'s price; [PlanPrice.none] when it has none.
  PlanPrice priceOf(Plan plan) => prices[plan] ?? PlanPrice.none;

  /// The upgrade contact message in [languageCode], falling back to English.
  /// Empty when the owner has not set one.
  String contactMessage(String languageCode) {
    final own = upgradeContact[languageCode]?.trim() ?? '';
    if (own.isNotEmpty) return own;
    return upgradeContact['en']?.trim() ?? '';
  }

  factory PlanStatus.fromJson(Map<String, dynamic> json) {
    final features = <String, FeatureAllowance>{};
    final rawFeatures = json['features'];
    if (rawFeatures is Map) {
      rawFeatures.forEach((key, value) {
        if (key is String && value is Map) {
          features[key] = FeatureAllowance.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      });
    }

    final catalog = <Plan, Map<String, CatalogLimit>>{};
    final rawCatalog = json['catalog'];
    if (rawCatalog is Map) {
      rawCatalog.forEach((planName, limits) {
        if (planName is! String || limits is! Map) return;
        final plan = Plan.values.where((p) => p.name == planName).firstOrNull;
        if (plan == null) return;
        final parsed = <String, CatalogLimit>{};
        limits.forEach((key, value) {
          if (key is String && value is Map) {
            parsed[key] = CatalogLimit.fromJson(
              Map<String, dynamic>.from(value),
            );
          }
        });
        catalog[plan] = parsed;
      });
    }

    final prices = <Plan, PlanPrice>{};
    final rawPrices = json['prices'];
    if (rawPrices is Map) {
      rawPrices.forEach((planName, price) {
        final plan = Plan.values.where((p) => p.name == planName).firstOrNull;
        if (plan != null) prices[plan] = PlanPrice.fromJson(price);
      });
    }

    final contact = <String, String>{};
    final rawContact = json['upgrade_contact'];
    if (rawContact is Map) {
      rawContact.forEach((key, value) {
        if (key is String && value is String) contact[key] = value;
      });
    }

    return PlanStatus(
      plan: Plan.fromString(json['plan'] as String?),
      expiresAt: parseInstantOrNull(json['expires_at']),
      isTrial: json['is_trial'] == true,
      trialEndsAt: parseInstantOrNull(json['trial_ends_at']),
      features: features,
      catalog: catalog,
      prices: prices,
      upgradeContact: contact,
      ownerContact: OwnerContact.fromJson(json['owner_contact']),
      upgradeRequest: UpgradeRequest.tryParse(json['upgrade_request']),
    );
  }
}
