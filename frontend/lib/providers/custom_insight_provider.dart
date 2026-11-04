import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:frontend/models/custom_insight.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/notification_event_bus.dart';

/// What [CustomInsightProvider] needs from the server; the real one is
/// [ApiCustomInsightClient], tests supply their own.
abstract class CustomInsightClient {
  /// The first page, or the page after [before] (a [CustomInsightPage.nextBefore]).
  Future<CustomInsightPage> list({String? before});
  Future<CustomInsight> get(String id);
  Future<CustomInsightCreateResult> create(CustomInsightRequest request);
  Future<CustomInsight> translate(String id);
  Future<void> delete(String id);
}

class ApiCustomInsightClient implements CustomInsightClient {
  const ApiCustomInsightClient();

  @override
  Future<CustomInsightPage> list({String? before}) => ApiService.getCustomInsights(before: before);

  @override
  Future<CustomInsight> get(String id) => ApiService.getCustomInsight(id);

  @override
  Future<CustomInsightCreateResult> create(CustomInsightRequest request) =>
      ApiService.createCustomInsight(request);

  @override
  Future<CustomInsight> translate(String id) => ApiService.translateCustomInsight(id);

  @override
  Future<void> delete(String id) => ApiService.deleteCustomInsight(id);
}

/// The user's custom insights: the list, the opened reports, create / translate
/// / delete, and polling while a report is still being written.
///
/// The server sends the list a page at a time. [load] (and every poll or push)
/// reads the first page again and keeps the older pages already loaded with
/// [loadMore]; [hasMore] says whether another page is waiting.
///
/// A failed call returns null / false and leaves the reason in [lastErrorCode],
/// [lastError] and [lastPlanLimit] (all cleared by the next call).
class CustomInsightProvider with ChangeNotifier {
  final CustomInsightClient _client;
  final Duration _pollInterval;
  final VoidCallback _onUsageChanged;
  StreamSubscription<void>? _eventSubscription;

  CustomInsightProvider({
    CustomInsightClient? client,
    Duration pollInterval = const Duration(seconds: 5),
    VoidCallback? onUsageChanged,
  })  : _client = client ?? const ApiCustomInsightClient(),
        _pollInterval = pollInterval,
        _onUsageChanged =
            onUsageChanged ?? (() => ApiService.onPlanUsageChanged?.call()) {
    _eventSubscription =
        NotificationEventBus().onCustomInsightUpdated.listen((_) => _onPush());
  }

  List<CustomInsight> _reports = const [];
  final Map<String, CustomInsight> _details = {};
  bool _isLoading = false;
  String? _error;

  /// The cursor of the next (older) page after the rows loaded so far; null
  /// when everything is loaded.
  String? _nextBefore;
  bool _isLoadingMore = false;
  String? _loadMoreError;
  String? _lastErrorCode;
  String? _lastError;
  PlanLimitException? _lastPlanLimit;
  bool _notFound = false;

  Timer? _timer;
  bool _polling = false;

  /// True once the list was loaded or a report created since the last [reset];
  /// a push only reloads a provider that is in use.
  bool _active = false;

  /// Bumped on [reset]; answers that arrive for an older generation (the
  /// previous user) are discarded.
  int _generation = 0;

  /// Newest first. Rows from the list carry no text or figures; use [detail].
  List<CustomInsight> get reports => List.unmodifiable(_reports);
  bool get isLoading => _isLoading;

  /// Why the last [load] failed; null when it worked.
  String? get error => _error;

  bool get hasPending => _reports.any((r) => r.status == CustomInsightStatus.pending);

  /// True when older reports are waiting on the server ([loadMore] reads them).
  bool get hasMore => _nextBefore != null;
  bool get isLoadingMore => _isLoadingMore;

  /// Why the last [loadMore] failed; null when it worked.
  String? get loadMoreError => _loadMoreError;

  /// The code of the last failed create / open / translate / delete: a
  /// `CustomInsightRequestException` code or a plan code; null for any other failure.
  String? get lastErrorCode => _lastErrorCode;

  /// The message of that failure (already in the user's language for server errors).
  String? get lastError => _lastError;

  /// Set when the failure was the plan refusing the request (locked, used up, cost cap).
  PlanLimitException? get lastPlanLimit => _lastPlanLimit;

  /// True when the last [open] got a 404: the report was deleted (or is not
  /// the user's). False after any other [open] result.
  bool get notFound => _notFound;

  /// The full report last fetched by [open] / [create] / [translate]; null
  /// when it was not fetched, or it changed since (a report that left pending).
  CustomInsight? detail(String id) => _details[id];

  // ------------------------------------------------------------ helpers

  static String _clean(Object e) =>
      e is ApiException ? e.message : e.toString().replaceAll('Exception: ', '');

  void _clearFailure() {
    _lastErrorCode = null;
    _lastError = null;
    _lastPlanLimit = null;
  }

  void _setFailure(Object e) {
    _lastPlanLimit = e is PlanLimitException ? e : null;
    _lastErrorCode = e is CustomInsightRequestException
        ? e.code
        : e is PlanLimitException
            ? e.code
            : null;
    _lastError = _clean(e);
  }

  static bool _isUsageGivenBack(CustomInsight before, CustomInsight now) =>
      before.status == CustomInsightStatus.pending &&
      (now.status == CustomInsightStatus.failed || now.status == CustomInsightStatus.refused);

  /// The server's order: newest first, then the larger id.
  static int _newestFirst(CustomInsight a, CustomInsight b) {
    final byTime = b.createdAt.compareTo(a.createdAt);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  }

  /// Replaces the start of the list with the server's first [page]. A report
  /// that left pending loses its cached detail (it has no text yet); one that
  /// left it as failed or refused had its use given back, so the plan is
  /// refreshed (returns true). A pending report the answer does not have yet
  /// (the list was read just before it was created) is kept. Older pages
  /// loaded with [loadMore] are kept when the first page reaches them (it
  /// shares a report with what was loaded); otherwise the list starts again
  /// from this page.
  bool _applyList(CustomInsightPage page) {
    final rows = page.reports;
    final before = {for (final r in _reports) r.id: r};
    var givenBack = false;
    for (final row in rows) {
      final old = before[row.id];
      if (old == null || !old.isPending || row.isPending) continue;
      _details.remove(row.id);
      if (_isUsageGivenBack(old, row)) givenBack = true;
    }
    final serverIds = {for (final r in rows) r.id};
    var older = <CustomInsight>[];
    final reaches = rows.any((r) => before.containsKey(r.id));
    if (page.nextBefore != null && reaches) {
      final last = rows.last;
      older = [
        for (final r in _reports)
          if (!r.isPending && !serverIds.contains(r.id) && _newestFirst(last, r) < 0) r,
      ]..sort(_newestFirst);
    }
    _reports = [
      for (final r in _reports)
        if (r.isPending && !serverIds.contains(r.id)) r,
      ...rows,
      ...older,
    ];
    // Kept older rows: the cursor after them still holds. Otherwise the page's.
    if (older.isEmpty) _nextBefore = page.nextBefore;
    return givenBack;
  }

  /// Puts [report] in the list and the detail cache, in place when it is there.
  void _replace(CustomInsight report) {
    _details[report.id] = report;
    final index = _reports.indexWhere((r) => r.id == report.id);
    if (index >= 0) {
      final old = _reports[index];
      _reports = [..._reports]..[index] = report;
      if (_isUsageGivenBack(old, report)) _onUsageChanged();
    }
  }

  void _syncPolling() {
    if (hasPending) {
      _timer ??= Timer.periodic(_pollInterval, (_) => _poll());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    final gen = _generation;
    try {
      final page = await _client.list();
      if (gen != _generation) return;
      final givenBack = _applyList(page);
      _syncPolling();
      notifyListeners();
      if (givenBack) _onUsageChanged();
    } catch (_) {
      // A missed poll is not an error to show; the next one tries again.
    } finally {
      // An old generation's poll must not clear the new generation's flag.
      if (gen == _generation) _polling = false;
    }
  }

  void _onPush() {
    if (_active) load();
  }

  // ------------------------------------------------------------ actions

  /// Loads the first page of the list (newest first), keeping older pages
  /// already loaded (see [_applyList]). On failure the list stays as it was
  /// and [error] says why.
  Future<void> load() async {
    final gen = _generation;
    _active = true;
    _error = null;
    _isLoading = true;
    notifyListeners();
    var givenBack = false;
    try {
      final page = await _client.list();
      if (gen != _generation) return;
      givenBack = _applyList(page);
    } catch (e) {
      if (gen != _generation) return;
      _error = _clean(e);
    }
    _isLoading = false;
    _syncPolling();
    notifyListeners();
    if (givenBack) _onUsageChanged();
  }

  /// Appends the next (older) page. Does nothing when there is none or one is
  /// already loading. On failure the list stays as it was and [loadMoreError]
  /// says why.
  Future<void> loadMore() async {
    final cursor = _nextBefore;
    if (cursor == null || _isLoadingMore) return;
    final gen = _generation;
    _isLoadingMore = true;
    _loadMoreError = null;
    notifyListeners();
    try {
      final page = await _client.list(before: cursor);
      if (gen != _generation) return;
      // A reload that started the list again meanwhile moved the cursor: this
      // page no longer follows the rows shown.
      if (_nextBefore == cursor) {
        final have = {for (final r in _reports) r.id};
        _reports = [..._reports, ...page.reports.where((r) => !have.contains(r.id))];
        _nextBefore = page.nextBefore;
      }
    } catch (e) {
      if (gen != _generation) return;
      _loadMoreError = _clean(e);
    }
    _isLoadingMore = false;
    notifyListeners();
  }

  /// Asks for a report. On success the report is at the top of the list (new
  /// and pending: polling starts; or an earlier ready one that was reused).
  /// Returns null on failure.
  Future<CustomInsightCreateResult?> create(CustomInsightRequest request) async {
    final gen = _generation;
    _active = true;
    _clearFailure();
    try {
      final result = await _client.create(request);
      if (gen != _generation) return null;
      final report = result.report;
      _details[report.id] = report;
      _reports = [report, ..._reports.where((r) => r.id != report.id)];
      _syncPolling();
      notifyListeners();
      return result;
    } catch (e) {
      if (gen != _generation) return null;
      _setFailure(e);
      notifyListeners();
      return null;
    }
  }

  /// Fetches the full report and keeps it for [detail]. Null on failure;
  /// [notFound] tells a deleted report (404) from any other failure.
  Future<CustomInsight?> open(String id) async {
    final gen = _generation;
    _clearFailure();
    _notFound = false;
    try {
      final report = await _client.get(id);
      if (gen != _generation) return null;
      _replace(report);
      _syncPolling();
      notifyListeners();
      return report;
    } catch (e) {
      if (gen != _generation) return null;
      if (e is ApiException && e.statusCode == 404) {
        _notFound = true;
        _details.remove(id);
        _reports = _reports.where((r) => r.id != id).toList();
        _syncPolling();
      } else {
        _setFailure(e);
      }
      notifyListeners();
      return null;
    }
  }

  /// Adds the Myanmar text to a ready report. Null on failure, with the report
  /// as it was and the reason in [lastPlanLimit] / [lastError].
  Future<CustomInsight?> translate(String id) async {
    final gen = _generation;
    _clearFailure();
    try {
      final report = await _client.translate(id);
      if (gen != _generation) return null;
      _replace(report);
      notifyListeners();
      return report;
    } catch (e) {
      if (gen != _generation) return null;
      _setFailure(e);
      notifyListeners();
      return null;
    }
  }

  /// Deletes a report. True when it is gone (a 404 means it already was).
  Future<bool> delete(String id) async {
    final gen = _generation;
    _clearFailure();
    try {
      await _client.delete(id);
    } catch (e) {
      if (gen != _generation) return false;
      if (!(e is ApiException && e.statusCode == 404)) {
        _setFailure(e);
        notifyListeners();
        return false;
      }
    }
    if (gen != _generation) return false;
    _details.remove(id);
    _reports = _reports.where((r) => r.id != id).toList();
    _syncPolling();
    notifyListeners();
    return true;
  }

  /// Clears all per-user state and stops polling (logout / user switch).
  void reset() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _polling = false;
    _active = false;
    _reports = const [];
    _details.clear();
    _isLoading = false;
    _error = null;
    _nextBefore = null;
    _isLoadingMore = false;
    _loadMoreError = null;
    _notFound = false;
    _clearFailure();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _eventSubscription?.cancel();
    _eventSubscription = null;
    super.dispose();
  }
}
