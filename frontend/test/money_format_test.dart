import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/utils/money.dart';

void main() {
  test('kyat is always whole kyat', () {
    expect(formatMoney(90150.26, Currency.mmk), 'K90,150');
    expect(formatMoney(300000, Currency.mmk), 'K300,000');
    expect(formatMoney(15000, Currency.mmk), 'K15,000');
  });

  test('dollars and baht keep two decimals', () {
    expect(formatMoney(1300, Currency.usd), r'$1,300.00');
    expect(formatMoney(8.8, Currency.usd), r'$8.80');
    expect(formatMoney(52.5, Currency.thb), '฿52.50');
  });

  test('the minus goes before the symbol', () {
    expect(formatMoney(-46.84, Currency.usd), r'-$46.84');
    expect(formatMoney(-640, Currency.usd), r'-$640.00');
    expect(formatMoney(-43434.95, Currency.mmk), '-K43,435');
    expect(formatMoney(-12.5, Currency.thb), '-฿12.50');
  });

  test('no minus when the amount rounds to zero', () {
    expect(formatMoney(-0.004, Currency.usd), r'$0.00');
    expect(formatMoney(-0.4, Currency.mmk), 'K0');
  });

  test('showPlus marks positive amounts only', () {
    expect(formatMoney(350, Currency.usd, showPlus: true), r'+$350.00');
    expect(formatMoney(-350, Currency.usd, showPlus: true), r'-$350.00');
    expect(formatMoney(0, Currency.usd, showPlus: true), r'$0.00');
  });

  test('the number alone, for layouts that draw the symbol', () {
    expect(formatMoneyNumber(1300, Currency.usd), '1,300.00');
    expect(formatMoneyNumber(90150.26, Currency.mmk), '90,150');
  });

  test('accepts ints (e.g. raw JSON numbers)', () {
    expect(formatMoney(1200, Currency.usd), r'$1,200.00');
  });
}
