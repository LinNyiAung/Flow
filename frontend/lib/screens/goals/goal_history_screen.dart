import 'package:flutter/material.dart';
import 'package:frontend/models/goal.dart';
import 'package:frontend/models/goal_entry.dart';
import 'package:frontend/screens/goals/goal_entry_tile.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/utils/family_entries.dart';

/// "Goal history": every entry of a goal, newest first, loaded a page at a
/// time as the person scrolls, until all `total` are in.
class GoalHistoryScreen extends StatefulWidget {
  final Goal goal;

  const GoalHistoryScreen({super.key, required this.goal});

  @override
  State<GoalHistoryScreen> createState() => _GoalHistoryScreenState();
}

class _GoalHistoryScreenState extends State<GoalHistoryScreen> {
  static const _pageSize = 50;

  /// Within this many pixels of the end, the next page loads.
  static const _loadAhead = 400.0;

  final _scroll = ScrollController();
  final _entries = <GoalEntry>[];
  int? _total;
  bool _loading = true; // the first page loads on open
  bool _failed = false;

  bool get _hasMore => _total == null || _entries.length < _total!;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    _fetchPage();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_loading || _failed || !_hasMore || !_scroll.hasClients) return;
    if (_scroll.position.extentAfter > _loadAhead) return;
    setState(() => _loading = true);
    _fetchPage();
  }

  void _retry() {
    setState(() {
      _failed = false;
      _loading = true;
    });
    _fetchPage();
  }

  Future<void> _fetchPage() async {
    try {
      final page = await ApiService.getGoalHistory(widget.goal.id, limit: _pageSize, offset: _entries.length);
      if (!mounted) return;
      setState(() {
        _entries.addAll(page.entries);
        // An empty page ends the list even if the total says otherwise.
        _total = page.entries.isEmpty ? _entries.length : page.total;
        _loading = false;
      });
      // A page that doesn't fill the screen can't be scrolled to load the next.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeLoadMore();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.goalHistoryTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _entries.isEmpty ? Center(child: _buildStatus(l)) : _buildList(l),
    );
  }

  /// The spinner, the failure with its retry, or (no entries) the empty line.
  Widget _buildStatus(AppLocalizations l) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final muted = TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant);
    if (_failed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.goalHistoryLoadFailed, style: muted, textAlign: TextAlign.center),
          TextButton(onPressed: _retry, child: Text(l.tryAgain)),
        ],
      );
    }
    return Text(l.goalHistoryEmpty, style: muted, textAlign: TextAlign.center);
  }

  Widget _buildList(AppLocalizations l) {
    final scheme = Theme.of(context).colorScheme;
    final showName = showsFamilyBook(context);
    final footer = _loading || _failed;
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.all(20),
      itemCount: _entries.length + (footer ? 1 : 0),
      separatorBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Container(height: 1, color: scheme.outlineVariant),
      ),
      itemBuilder: (context, i) => i < _entries.length
          ? GoalEntryTile(entry: _entries[i], currency: widget.goal.currency, showName: showName)
          : Center(child: _buildStatus(l)),
    );
  }
}
