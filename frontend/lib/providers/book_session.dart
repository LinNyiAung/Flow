import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/services/api_service.dart';

/// Ties the Personal / Family mode to the rest of the app (owned by the app
/// root; kept out of `main.dart` so it can be tested):
///
/// - **a mode change** closes every screen above Home (they hold the other
///   book's data), then resets the providers that hold book data
///   ([resetBookData]); Home itself is rebuilt by its key (R18);
/// - **sign-in** reloads the family and the user's remembered mode; a
///   remembered Family mode waits until the family is confirmed (R19);
/// - **the family turns out to be gone** (left, removed, deleted): back to
///   Personal;
/// - **a Family-mode request answered `no_family`**: back to Personal, reload
///   the family, and say why ([showMessage], once per switch).
class BookSession {
  final BookModeProvider books;
  final FamilyProvider family;
  final GlobalKey<NavigatorState> navigatorKey;

  /// Resets the providers that hold one book's data.
  final VoidCallback resetBookData;

  /// Shows a short message (a snackbar).
  final void Function(String message) showMessage;

  /// "You're no longer in this family", in the app's current language.
  final String Function() noLongerMemberText;

  BookSession({
    required this.books,
    required this.family,
    required this.navigatorKey,
    required this.resetBookData,
    required this.showMessage,
    required this.noLongerMemberText,
  });

  void attach() {
    books.onModeChanged = _onModeChanged;
    family.addListener(_onFamilyChanged);
    ApiService.onNoFamily = _onNoFamily;
  }

  void detach() {
    if (books.onModeChanged == _onModeChanged) books.onModeChanged = null;
    family.removeListener(_onFamilyChanged);
    if (ApiService.onNoFamily == _onNoFamily) ApiService.onNoFamily = null;
  }

  /// A user signed in: their family and their remembered mode.
  void signedIn(String userId) {
    unawaited(family.refresh());
    unawaited(books.load(userId));
  }

  /// Logout or another account.
  void reset() {
    family.reset();
    books.reset();
  }

  void _onModeChanged() {
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    resetBookData();
  }

  void _onFamilyChanged() {
    if (family.loaded) books.familyKnown(family.inFamily);
  }

  void _onNoFamily() {
    if (!books.fallBackToPersonal()) return;
    unawaited(family.refresh());
    showMessage(noLongerMemberText());
  }
}
