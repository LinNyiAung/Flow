import 'package:flutter/material.dart';
import 'package:frontend/models/goal.dart';
import 'package:frontend/models/goal_entry.dart';
import 'package:frontend/screens/goals/goal_entry_tile.dart';
import 'package:frontend/screens/goals/goal_history_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/utils/family_entries.dart';

/// The goal screen's "History" card: the latest entries, newest first, with
/// "Show all" when there are more. It loads on its own, so a failure here
/// leaves the rest of the goal screen working; [GoalHistorySectionState.reload]
/// fetches it again (after an Add or Withdraw).
class GoalHistorySection extends StatefulWidget {
  final Goal goal;

  const GoalHistorySection({super.key, required this.goal});

  @override
  GoalHistorySectionState createState() => GoalHistorySectionState();
}

class GoalHistorySectionState extends State<GoalHistorySection> {
  static const _latest = 10;

  GoalHistoryPage? _page;
  bool _failed = false;

  /// Only the newest load's answer is shown.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final generation = ++_generation;
    if (_failed) setState(() => _failed = false);
    try {
      final page = await ApiService.getGoalHistory(widget.goal.id, limit: _latest);
      if (!mounted || generation != _generation) return;
      setState(() => _page = page);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.goalHistory, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildBody(l),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant);
    final page = _page;

    if (_failed) {
      return Row(
        children: [
          Expanded(child: Text(l.goalHistoryLoadFailed, style: muted)),
          TextButton(onPressed: reload, child: Text(l.tryAgain)),
        ],
      );
    }
    if (page == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (page.entries.isEmpty) return Text(l.goalHistoryEmpty, style: muted);

    final showName = showsFamilyBook(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < page.entries.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: 12),
          ],
          GoalEntryTile(entry: page.entries[i], currency: widget.goal.currency, showName: showName),
        ],
        if (page.total > _latest) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => GoalHistoryScreen(goal: widget.goal)),
              ),
              child: Text(l.goalHistoryShowAll(page.total)),
            ),
          ),
        ],
      ],
    );
  }
}
