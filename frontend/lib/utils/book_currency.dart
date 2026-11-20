import 'package:flutter/widgets.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:provider/provider.dart';

/// The currency the current book opens in (balances, reports, analytics,
/// goals) and new entries default to: in the Family book, the family's
/// currency (its owner's default, so every member sees the same); otherwise,
/// or while the family's currency isn't known, the person's own default.
///
/// [listen]: rebuild when the person, the mode or the family changes (as
/// `Provider.of`).
Currency bookCurrency(BuildContext context, {bool listen = true}) {
  final own = Provider.of<AuthProvider>(context, listen: listen).defaultCurrency;
  final books = Provider.of<BookModeProvider?>(context, listen: listen);
  if (books?.isFamily != true) return own;
  final family = Provider.of<FamilyProvider?>(context, listen: listen);
  return family?.family?.currency ?? own;
}
