import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/services/api_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:frontend/models/family.dart' show BookMode;

/// The Personal / Family switch for the whole app.
///
/// The mode is remembered on the device ([prefsKey]) and defaults to
/// Personal. Every change sets [ApiService.bookMode] (so every request carries
/// the right `X-Book`) and calls [onModeChanged], which the app root uses to
/// reset the providers that hold book data and rebuild Home for the new book.
class BookModeProvider with ChangeNotifier {
  static const String prefsKey = 'book_mode';

  BookMode _mode = BookMode.personal;

  /// Bumped by [reset] and [setMode]: a [load] that started before either is
  /// dropped, so a late read of the device can't undo a newer choice.
  int _generation = 0;

  /// Called after the mode changed (by [setMode], [load] or
  /// [fallBackToPersonal]); never by [reset].
  VoidCallback? onModeChanged;

  BookMode get mode => _mode;
  bool get isFamily => _mode == BookMode.family;

  /// Reads the mode remembered on this device. Calls [onModeChanged] when it
  /// differs from the current one (screens already built for the other book
  /// must start again).
  Future<void> load() async {
    final generation = _generation;
    BookMode saved;
    try {
      final prefs = await SharedPreferences.getInstance();
      saved = BookMode.fromName(prefs.getString(prefsKey));
    } catch (e) {
      debugPrint('Could not read the book mode: $e');
      return;
    }
    if (generation != _generation) return;
    _apply(saved);
  }

  /// Switches the whole app to [mode] and remembers it on the device.
  Future<void> setMode(BookMode mode) async {
    _generation++;
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

  /// Logout or another account: back to Personal. What the device remembers
  /// is kept and read again by the next [load].
  void reset() {
    _generation++;
    _mode = BookMode.personal;
    ApiService.bookMode = BookMode.personal;
    notifyListeners();
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
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, mode.name);
    } catch (e) {
      debugPrint('Could not save the book mode: $e');
    }
  }
}

/// Opens something that belongs to a book (a tapped notification or push):
/// for a [family] one, switches to Family first when needed, then calls
/// [open]. A notice without the family marker may be personal or about no
/// book at all (an invitation, a plan change), so it leaves the mode alone.
Future<void> openInBook(BuildContext context, {required bool family, required VoidCallback open}) async {
  final books = Provider.of<BookModeProvider>(context, listen: false);
  if (family && !books.isFamily) {
    await books.setMode(BookMode.family);
  }
  open();
}
