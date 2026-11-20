import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/utils/book_currency.dart';
import 'package:provider/provider.dart';

/// A person whose own default currency is [currency].
class _Auth extends AuthProvider {
  _Auth(this.currency);
  final Currency currency;
  @override
  Currency get defaultCurrency => currency;
}

/// A known family whose currency (its owner's) is [currency].
class _Family extends FamilyProvider {
  _Family(this.currency);
  final Currency? currency;
  @override
  Family? get family => Family(id: 'f1', name: 'Kyat family', currency: currency);
  @override
  bool get inFamily => true;
  @override
  bool get loaded => true;
  @override
  Future<void> refresh() async {}
}

void main() {
  group('Family.fromJson', () {
    test('reads the family\'s currency', () {
      expect(Family.fromJson({'id': 'f1', 'name': 'F', 'currency': 'mmk'}).currency, Currency.mmk);
    });
    test('no currency (an older server): null', () {
      expect(Family.fromJson({'id': 'f1', 'name': 'F'}).currency, isNull);
    });
  });

  /// What bookCurrency gives under these providers (family / books null: not in the tree).
  Future<Currency> read(WidgetTester tester,
      {required Currency mine, FamilyProvider? family, BookModeProvider? books}) async {
    late Currency got;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: _Auth(mine)),
        if (family != null) ChangeNotifierProvider<FamilyProvider>.value(value: family),
        if (books != null) ChangeNotifierProvider<BookModeProvider>.value(value: books),
      ],
      child: Builder(builder: (context) {
        got = bookCurrency(context);
        return const SizedBox();
      }),
    ));
    return got;
  }

  BookModeProvider familyMode() => BookModeProvider()..setMode(BookMode.family);

  testWidgets('Family book: the family\'s currency, not the member\'s own', (tester) async {
    expect(await read(tester, mine: Currency.usd, family: _Family(Currency.mmk), books: familyMode()), Currency.mmk);
  });

  testWidgets('Personal book: the person\'s own currency, family or not', (tester) async {
    expect(await read(tester, mine: Currency.usd, family: _Family(Currency.mmk), books: BookModeProvider()),
        Currency.usd);
    expect(await read(tester, mine: Currency.mmk), Currency.mmk);
  });

  testWidgets('Family book whose currency isn\'t known (an older server): the person\'s own', (tester) async {
    expect(await read(tester, mine: Currency.usd, family: _Family(null), books: familyMode()), Currency.usd);
  });

  testWidgets('it follows the family\'s currency when the family loads', (tester) async {
    final family = _Loading();
    final books = familyMode();
    expect(await read(tester, mine: Currency.usd, family: family, books: books), Currency.usd);
    family.arrive(Currency.mmk);
    late Currency got;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: _Auth(Currency.usd)),
        ChangeNotifierProvider<FamilyProvider>.value(value: family),
        ChangeNotifierProvider<BookModeProvider>.value(value: books),
      ],
      child: Builder(builder: (context) {
        got = bookCurrency(context);
        return const SizedBox();
      }),
    ));
    expect(got, Currency.mmk);
  });
}

/// A family not known yet, then loaded with [arrive].
class _Loading extends FamilyProvider {
  Family? _family;
  void arrive(Currency currency) {
    _family = Family(id: 'f1', name: 'F', currency: currency);
    notifyListeners();
  }

  @override
  Family? get family => _family;
  @override
  bool get inFamily => _family != null;
  @override
  bool get loaded => _family != null;
  @override
  Future<void> refresh() async {}
}
