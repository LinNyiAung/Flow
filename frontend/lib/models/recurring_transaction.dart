import 'package:flutter/material.dart';

import '../services/localization_service.dart';

enum RecurrenceFrequency {
  daily,
  weekly,
  monthly,
  annually,
}

extension RecurrenceFrequencyExtension on RecurrenceFrequency {
  String getDisplayName(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    switch (this) {
      case RecurrenceFrequency.daily:
        return localizations.daily;
      case RecurrenceFrequency.weekly:
        return localizations.weekly;
      case RecurrenceFrequency.monthly:
        return localizations.monthly;
      case RecurrenceFrequency.annually:
        return localizations.annually;
    }
  }


  String getDescription(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    switch (this) {
      case RecurrenceFrequency.daily:
        return localizations.dailyDes;
      case RecurrenceFrequency.weekly:
        return localizations.weeklyDes;
      case RecurrenceFrequency.monthly:
        return localizations.monthlyDes;
      case RecurrenceFrequency.annually:
        return localizations.annuallyDes;
    }
  }
}

class RecurrenceConfig {
  final RecurrenceFrequency frequency;
  final int? dayOfWeek; // 0-6 for Monday-Sunday (weekly)
  final int? dayOfMonth; // 1-31 (monthly)
  final int? month; // 1-12 (annually)
  final int? dayOfYear; // 1-31 (annually)
  final DateTime? endDate;

  RecurrenceConfig({
    required this.frequency,
    this.dayOfWeek,
    this.dayOfMonth,
    this.month,
    this.dayOfYear,
    this.endDate,
  });

  factory RecurrenceConfig.fromJson(Map<String, dynamic> json) {
    return RecurrenceConfig(
      frequency: RecurrenceFrequency.values.firstWhere(
        (e) => e.name == json['frequency'],
      ),
      dayOfWeek: json['day_of_week'],
      dayOfMonth: json['day_of_month'],
      month: json['month'],
      dayOfYear: json['day_of_year'],
      endDate: json['end_date'] != null ? DateTime.parse(json['end_date']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'frequency': frequency.name,
      if (dayOfWeek != null) 'day_of_week': dayOfWeek,
      if (dayOfMonth != null) 'day_of_month': dayOfMonth,
      if (month != null) 'month': month,
      if (dayOfYear != null) 'day_of_year': dayOfYear,
      if (endDate != null) 'end_date': endDate!.toIso8601String(),
    };
  }

  String getDisplayText() {
    switch (frequency) {
      case RecurrenceFrequency.daily:
        return 'Every day';
      case RecurrenceFrequency.weekly:
        final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        return 'Every ${days[dayOfWeek ?? 0]}';
      case RecurrenceFrequency.monthly:
        return 'Every ${_getOrdinal(dayOfMonth ?? 1)} of the month';
      case RecurrenceFrequency.annually:
        final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return 'Every ${months[(month ?? 1) - 1]} ${dayOfYear ?? 1}';
    }
  }

  String _getOrdinal(int number) {
    if (number >= 11 && number <= 13) {
      return '${number}th';
    }
    switch (number % 10) {
      case 1:
        return '${number}st';
      case 2:
        return '${number}nd';
      case 3:
        return '${number}rd';
      default:
        return '${number}th';
    }
  }
}

class TransactionRecurrence {
  final bool enabled;
  final RecurrenceConfig? config;
  final DateTime? lastCreatedDate;
  final String? parentTransactionId;

  TransactionRecurrence({
    required this.enabled,
    this.config,
    this.lastCreatedDate,
    this.parentTransactionId,
  });

  factory TransactionRecurrence.fromJson(Map<String, dynamic> json) {
    return TransactionRecurrence(
      enabled: json['enabled'] ?? false,
      config: json['config'] != null ? RecurrenceConfig.fromJson(json['config']) : null,
      lastCreatedDate: json['last_created_date'] != null
          ? DateTime.parse(json['last_created_date'])
          : null,
      parentTransactionId: json['parent_transaction_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      if (config != null) 'config': config!.toJson(),
      if (lastCreatedDate != null) 'last_created_date': lastCreatedDate!.toIso8601String(),
      if (parentTransactionId != null) 'parent_transaction_id': parentTransactionId,
    };
  }
}