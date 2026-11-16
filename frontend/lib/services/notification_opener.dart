import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/models/budget.dart';
import 'package:frontend/models/goal.dart';
import 'package:frontend/models/notification.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/providers/budget_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/providers/goal_provider.dart';
import 'package:frontend/screens/budgets/budget_detail_screen.dart';
import 'package:frontend/screens/family/family_invitations_screen.dart';
import 'package:frontend/screens/family/family_screen.dart';
import 'package:frontend/screens/goals/goal_detail_screen.dart';
import 'package:frontend/screens/insights/custom_insight_report_screen.dart';
import 'package:frontend/screens/insights/insights_screen.dart';

/// Opens what a tapped notice is about, from the notifications list or from
/// a tapped push.
///
/// A notice about one book's money ([notificationBelongsToBook]) is opened in
/// its own book: [openInBookWith] first makes the mode match (the family's
/// when the notice carries the family marker, the person's own otherwise),
/// which closes every screen above Home, then the target is fetched in that
/// book and pushed with [navigatorKey] (never with the tapped screen's
/// context, which may be closed by then). Notices about the family itself
/// (an invitation, a new member, the ownership) open the family screens in
/// whatever book is open.
class NotificationOpener {
  NotificationOpener({
    required this.navigatorKey,
    required this.budgets,
    required this.goals,
    this.books,
    this.family,
    Widget Function(Budget budget)? budgetPage,
    Widget Function(Goal goal)? goalPage,
  })  : budgetPage = budgetPage ?? ((budget) => BudgetDetailScreen(budget: budget)),
        goalPage = goalPage ?? ((goal) => GoalDetailScreen(goal: goal));

  final GlobalKey<NavigatorState> navigatorKey;
  final BudgetProvider budgets;
  final GoalProvider goals;

  /// Null where there is no Personal / Family switch (the notice is opened
  /// as it is).
  final BookModeProvider? books;

  /// For [openPush]: whether the family (and so the remembered mode) is known.
  final FamilyProvider? family;

  final Widget Function(Budget budget) budgetPage;
  final Widget Function(Goal goal) goalPage;

  /// Opens the screen for a notice of [type] ([subjectId]: the budget, goal,
  /// report or invitation it is about; [family]: it carries the family
  /// marker). [onClosed] runs when that screen is closed. Completes with
  /// false when there is nothing to open (an unknown type, a budget or goal
  /// that no longer exists), or when the book was switched again while the
  /// budget or goal was being fetched (it would open in the wrong book).
  Future<bool> open(String type, {String? subjectId, bool family = false, VoidCallback? onClosed}) async {
    if (type == NotificationType.family_invite.name) {
      return _push(MaterialPageRoute<void>(builder: (_) => const FamilyInvitationsScreen()), onClosed);
    }
    if (type == NotificationType.family_invite_accepted.name || type == NotificationType.family_owner.name) {
      return _push(MaterialPageRoute<void>(builder: (_) => const FamilyScreen()), onClosed);
    }
    final target = _bookTarget(type, subjectId);
    if (target == null) return false;

    final books = this.books;
    // The book the notice belongs to, which openInBookWith switches to.
    final wanted = family ? BookMode.family : BookMode.personal;

    Future<bool>? opening;
    Future<bool> run() async {
      final route = await target();
      // The user may have flipped the switch while the fetch was in flight:
      // never open one book's budget or goal in the other book.
      if (books != null && books.mode != wanted) return false;
      return route != null && _push(route, onClosed);
    }

    if (books == null) return run();
    await openInBookWith(books, family: family, open: () => opening = run());
    return await (opening ?? Future.value(false));
  }

  /// A tapped push ([family]: it carried `book: family`). False while it
  /// can't be opened yet; the caller keeps it and tries again (after
  /// sign-in, or once the family is known). True once it is dealt with:
  /// opened, or dropped (nothing to open; a family push for someone no longer
  /// in a family).
  ///
  /// A push about a book waits until the family is known (or failed to
  /// load): until then a remembered Family mode may still be applied, and
  /// that switch would close the screen just opened.
  bool openPush(String type, {String? subjectId, required bool family, required bool signedIn}) {
    if (!notificationOpensSomething(type)) return true;
    if (!signedIn || navigatorKey.currentState == null) return false;
    final known = this.family;
    if (known != null && notificationBelongsToBook(type)) {
      if (family) {
        if (!known.loaded) return false;
        if (!known.inFamily) return true;
      } else if (!known.loaded && known.error == null) {
        return false;
      }
    }
    unawaited(open(type, subjectId: subjectId, family: family));
    return true;
  }

  /// The screen for a notice about one book's money, built once the mode is
  /// that book's; null when this type opens nothing.
  Future<Route<Object?>?> Function()? _bookTarget(String type, String? subjectId) {
    final id = subjectId == null || subjectId.isEmpty ? null : subjectId;
    if (type.startsWith('budget_')) {
      if (id == null) return null;
      return () async {
        final budget = await budgets.getBudget(id);
        return budget == null ? null : MaterialPageRoute<void>(builder: (_) => budgetPage(budget));
      };
    }
    if (type.startsWith('goal_')) {
      if (id == null) return null;
      return () async {
        final goal = await goals.getGoal(id);
        return goal == null ? null : MaterialPageRoute<void>(builder: (_) => goalPage(goal));
      };
    }
    if (type == NotificationType.custom_insight_ready.name && id != null) {
      return () async => MaterialPageRoute<void>(builder: (_) => CustomInsightReportScreen(reportId: id));
    }
    if (type == NotificationType.custom_insight_ready.name || type == NotificationType.custom_insight_failed.name) {
      return () async => _named('/insights', InsightsScreen.customTabArgument);
    }
    if (type == NotificationType.weekly_insights_generated.name ||
        type == NotificationType.monthly_insights_generated.name) {
      return () async => _named('/insights');
    }
    if (notificationBelongsToBook(type)) {
      // Entries: large or unusual spending, reminders, recurring entries.
      return () async => _named('/transactions');
    }
    return null;
  }

  /// The app's named route [name], or null when it has none (tests).
  Route<Object?>? _named(String name, [Object? arguments]) {
    final navigator = navigatorKey.currentState;
    final settings = RouteSettings(name: name, arguments: arguments);
    return navigator?.widget.onGenerateRoute?.call(settings);
  }

  bool _push(Route<Object?> route, VoidCallback? onClosed) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return false;
    navigator.push(route).then((_) => onClosed?.call());
    return true;
  }
}
