import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/models/voice_image_models.dart';
import 'package:frontend/screens/transactions/voice_input_screen.dart';

ExtractedTransactionData _e(TransactionType type, double amount, Currency currency) => ExtractedTransactionData(
      type: type,
      mainCategory: 'Food',
      subCategory: 'Lunch',
      date: DateTime(2026, 11, 10),
      amount: amount,
      currency: currency,
      confidence: 0.9,
    );

void main() {
  test('one currency: the app money format with its symbol', () {
    expect(
      voiceSelectedTotal([
        _e(TransactionType.outflow, 4500, Currency.mmk),
        _e(TransactionType.outflow, 1200.4, Currency.mmk),
      ]),
      '-K5,700',
    );
    expect(
      voiceSelectedTotal([
        _e(TransactionType.inflow, 20, Currency.usd),
        _e(TransactionType.outflow, 4.5, Currency.usd),
      ]),
      r'+$15.50',
    );
  });

  test('one currency that nets to zero after rounding has no sign', () {
    expect(
      voiceSelectedTotal([
        _e(TransactionType.inflow, 1000, Currency.mmk),
        _e(TransactionType.outflow, 1000.3, Currency.mmk),
      ]),
      'K0',
    );
  });

  test('mixed currencies keep the plain number, without "-0.00"', () {
    expect(
      voiceSelectedTotal([
        _e(TransactionType.inflow, 20, Currency.usd),
        _e(TransactionType.outflow, 4.5, Currency.thb),
      ]),
      '+15.50',
    );
    expect(
      voiceSelectedTotal([
        _e(TransactionType.inflow, 0.1, Currency.usd),
        _e(TransactionType.inflow, 0.2, Currency.usd),
        _e(TransactionType.outflow, 0.3, Currency.thb),
      ]),
      '0.00',
    );
  });
}
