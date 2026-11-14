import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/services/api_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:frontend/models/family.dart' show BookMode;

/// The Personal / Family switch for the whole app.
///
/// The mode is remembered on the device per user ([prefsKeyFor]) and defaults
/// to Personal. A remembered Family mode is applied only once the family is
/// confirmed ([familyKnown]); until then the app stays Personal, so nobody is
/// sent to a family book they no longer (or never) belong to.
///
/// Every change sets [ApiService.bookMode] (so every request carries the
/// right `X-Book`) and calls [onModeChanged], which the app root uses to close
/// the screens above Home, reset the providers that hold book data and
/// rebuild Home for the new book.
class BookModeProvider with ChangeNotifier {
  /// The prefix of the per-user key ([prefsKeyFor]).
  static const String prefsKey = 'book_mode';

  /// Where [userId]'s mode is remembered: `book_mode:<userId>`.
  static String prefsKeyFor(String userId) => '$prefsKey:$userId';

  BookMode _mode = BookMode.personal;

  /// The signed-in user whose mode this is (null when signed out).
  String? _userId;

  /// What the family is known to be since the last [reset]: null unknown.
  bool? _inFamily;

  /// Family mode was remembered and waits for the family to be confirmed.
  bool _familyPending = false;

  /// Bumped by [reset] and [setMode]: a [load] that started before either is
  /// dropped, so a late read of the device can't undo a newer choice.
  int _generation = 0;

  /// Called after the mode changed (by [setMode], a confirmed remembered
  /// Family mode, [familyKnown] or [fallBackToPersonal]); never by [reset].
  VoidCallback? onModeChanged;

  BookMode get mode => _mode;
  bool get isFamily => _mode == BookMode.family;
  String? get userId => _userId;

  /// Reads [userId]'s remembered mode. A remembered Family mode is applied
  /// when the family is (or once it is) confirmed by [familyKnown].
  Future<void> load(String userId) async {
    final generation = _generation;
    _userId = userId;
    BookMode saved;
    try {
      final prefs = await SharedPreferences.getInstance();
      saved = BookMode.fromName(prefs.getString(prefsKeyFor(userId)));
    } catch (e) {
      debugPrint('Could not read the book mode: $e');
      return;
    }
    if (generation != _generation) return;
    if (saved == BookMode.family) {
      _familyPending = true;
      _applyPendingFamily();
    }
  }

  /// The family is now known: [inFamily] is whether the user is in one.
  /// Applies a remembered Family mode, or, with no family, goes back to
  /// Personal (left, removed, deleted) and drops the remembered one.
  void familyKnown(bool inFamily) {
    _inFamily = inFamily;
    if (inFamily) {
      _applyPendingFamily();
      return;
    }
    _familyPending = false;
    if (_mode == BookMode.family) unawaited(setMode(BookMode.personal));
  }

  /// Switches the whole app to [mode] and remembers it for the signed-in user.
  Future<void> setMode(BookMode mode) async {
    _generation++;
    _familyPending = false;
    if (!_apply(mode)) return;
    await _save(mode);
  }

  /// Back to Personal when in Family mode (a request answered `no_family`):
  /// true when it switched. The switch itself is synchronous, so the requests
  /// that follow already go to the personal book.
  bool fallBackToPersonal() {
    if (_mode != BookMode.family) return false;
    unawaited(setMode(BookMode.personal));
    return true;
  }

  /// Logout or another account: back to Personal, nothing known. What the
  /// device remembers is kept and read again by the next [load].
  void reset() {
    _generation++;
    _userId = null;
    _inFamily = null;
    _familyPending = false;
    _mode = BookMode.personal;
    ApiService.bookMode = BookMode.personal;
    notifyListeners();
  }

  void _applyPendingFamily() {
    if (!_familyPending || _inFamily != true) return;
    _familyPending = false;
    _apply(BookMode.family);
  }

  /// Sets [mode] everywhere; false when it was already the mode.
  bool _apply(BookMode mode) {
    if (mode == _mode) return false;
    _mode = mode;
    ApiService.bookMode = mode;
    notifyListeners();
    onModeChanged?.call();
    return true;
  }

  Future<void> _save(BookMode mode) async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKeyFor(userId), mode.name);
    } catch (e) {
      debugPrint('Could not save the book mode: $e');
    }
  }
}

/// Opens something that belongs to a book (a tapped notification or push):
/// first makes the mode match the notice's book ([family]: Family; otherwise
/// the person's own book, Personal), then calls [open]. A notice without the
/// family marker is about the person's own book, which would 404 in Family
/// mode (ruling R17).
///
/// A switch closes every screen above Home (R18), the one that called this
/// included, so [open] must push with the root navigator (`navigatorKey`),
/// not with a context from a closed screen.
Future<void> openInBook(BuildContext context, {required bool family, required VoidCallback open}) =>
    openInBookWith(Provider.of<BookModeProvider>(context, listen: false), family: family, open: open);

/// [openInBook] without a BuildContext (the push tap handler).
Future<void> openInBookWith(BookModeProvider books, {required bool family, required VoidCallback open}) async {
  final wanted = family ? BookMode.family : BookMode.personal;
  if (books.mode != wanted) {
    await books.setMode(wanted);
  }
  open();
}
