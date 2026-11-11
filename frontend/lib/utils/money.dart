import 'package:intl/intl.dart';
import 'package:frontend/models/user.dart';

/// The app's one way to show an amount of money.
///
/// - Kyat is always whole ("K90,150"); dollars and baht keep two decimals
///   ("$1,300.00", "฿52.50").
/// - A minus goes before the symbol: "-$46.84", never "$-46.84".
/// - [showPlus] adds "+" to positive amounts ("+$8.80"), for gains/changes.
/// - Neither sign shows when the amount rounds to zero ("K0", "$0.00").
///
/// Display only: stored values and what's sent to the server are untouched.
String formatMoney(num amount, Currency currency, {bool showPlus = false}) {
  final number = formatMoneyNumber(amount.abs(), currency);
  final sign = roundsToZero(amount, currency)
      ? ''
      : amount < 0
          ? '-'
          : (showPlus && amount > 0 ? '+' : '');
  return '$sign${currency.symbol}$number';
}

/// The digits of [formatMoney] without symbol or sign ("1,300.00", "90,150"),
/// for layouts that draw the symbol themselves.
String formatMoneyNumber(num amount, Currency currency) => _formatFor(currency).format(amount);

/// Whether [amount] reads as zero once rounded for display: whole kyat for
/// MMK, cents otherwise. So a rounded-away amount shows no sign ("-K0",
/// "+$0.00"), and "over by" checks can ignore an excess too small to show.
bool roundsToZero(num amount, Currency currency) =>
    _formatFor(currency).format(amount.abs()) == _formatFor(currency).format(0);

final _wholeFormat = NumberFormat('#,##0', 'en_US');
final _centsFormat = NumberFormat('#,##0.00', 'en_US');

NumberFormat _formatFor(Currency currency) => currency == Currency.mmk ? _wholeFormat : _centsFormat;
