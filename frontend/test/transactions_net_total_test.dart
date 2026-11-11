import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/screens/transactions/transactions_list_screen.dart';

Transaction _t(TransactionType type, double amount, Currency currency) => Transaction(
      id: 'x',
      userId: 'u',
      type: type,
      mainCategory: 'Food',
      subCategory: 'Lunch',
      date: DateTime(2026, 11, 10),
      amount: amount,
      currency: currency,
      createdAt: DateTime(2026, 11, 10),
      updatedAt: DateTime(2026, 11, 10),
    );

void main() {
  test('a kyat net that rounds to zero shows "K0", not "-K0"', () {
    final list = [
      _t(TransactionType.inflow, 1000, Currency.mmk),
      _t(TransactionType.outflow, 1000.3, Currency.mmk),
    ];
    expect(transactionsNetTotal(list, Currency.mmk), 'K0');
  });

  test('a dollar float residue shows "\$0.00", not "-\$0.00"', () {
    final list = [
      _t(TransactionType.inflow, 0.1, Currency.usd),
      _t(TransactionType.inflow, 0.2, Currency.usd),
      _t(TransactionType.outflow, 0.3, Currency.usd),
    ];
    expect(transactionsNetTotal(list, Currency.usd), r'$0.00');
  });

  test('a real net keeps its sign; other currencies are skipped', () {
    final list = [
      _t(TransactionType.inflow, 50, Currency.usd),
      _t(TransactionType.outflow, 20.5, Currency.usd),
      _t(TransactionType.outflow, 9999, Currency.mmk),
    ];
    expect(transactionsNetTotal(list, Currency.usd), r'+$29.50');
    expect(transactionsNetTotal(list, Currency.mmk), '-K9,999');
  });
}
