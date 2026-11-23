import 'package:flutter/material.dart';
import 'package:frontend/models/family_spending.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/screens/family/family_person_spending_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/money.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:frontend/widgets/hero_card.dart';
import 'package:frontend/widgets/mascot.dart';
import 'package:frontend/widgets/progress_meter.dart';

/// Fetches one month of the family book's spending per person (tests pass a fake).
typedef FamilySpendingLoader = Future<FamilySpendingOverview> Function(DateTime month, {Currency? currency});

/// Fetches one person's month (memberId null: Whole family).
typedef PersonSpendingLoader = Future<FamilyPersonSpending> Function(DateTime month,
    {String? memberId, Currency? currency});

/// "▲ 40%", "▼ 10%" or "0%" against [previous]; [AppLocalizations.familySpendingNew]
/// when there was nothing before; null when there is nothing either month.
String? spendingChange(AppLocalizations l, double amount, double previous) {
  if (amount == 0 && previous == 0) return null;
  if (previous == 0) return l.familySpendingNew;
  final percent = ((amount - previous) / previous * 100).round();
  if (percent > 0) return '▲ $percent%';
  if (percent < 0) return '▼ ${-percent}%';
  return '0%';
}

/// The Family spending screen (side drawer, family members only): one calendar
/// month of the family book, how much was spent on each person (Whole family
/// on its own row), largest first, with each person's change against the
/// previous month. Always the family book, whichever book is switched on.
class FamilySpendingScreen extends StatefulWidget {
  const FamilySpendingScreen({super.key, this.loader, this.personLoader, this.now});

  /// Default: [ApiService.getFamilySpending].
  final FamilySpendingLoader? loader;

  /// Default: [ApiService.getFamilyPersonSpending].
  final PersonSpendingLoader? personLoader;

  /// The clock (tests fix it); the current month is the last one shown.
  final DateTime Function()? now;

  @override
  State<FamilySpendingScreen> createState() => _FamilySpendingScreenState();
}

class _FamilySpendingScreenState extends State<FamilySpendingScreen> {
  late final DateTime _currentMonth;
  late DateTime _month;
  Currency? _currency;

  /// The family's own currency: what the first load (no currency asked) answered in. Always offered in the picker,
  /// even with no spending in it, so switching away from it can be undone.
  Currency? _familyCurrency;
  FamilySpendingOverview? _data;
  String? _error;
  bool _loading = true;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    final now = (widget.now ?? DateTime.now)();
    _currentMonth = DateTime(now.year, now.month);
    _month = _currentMonth;
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await (widget.loader ?? ApiService.getFamilySpending)(_month, currency: _currency);
      if (!mounted || request != _request) return;
      setState(() {
        _data = data;
        _familyCurrency ??= data.currency;
        _currency = data.currency;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = e is ApiException ? e.message : AppLocalizations.of(context).genericErrorOccurred;
        _loading = false;
      });
    }
  }

  void _go(int months) {
    _month = DateTime(_month.year, _month.month + months);
    _load();
  }

  bool get _canGoBack {
    final first = _data?.firstMonth;
    return first != null && _month.isAfter(first);
  }

  bool get _canGoForward => _month.isBefore(_currentMonth);

  void _pickCurrency() {
    final l = AppLocalizations.of(context);
    final data = _data;
    final family = _familyCurrency;
    final current = _currency;
    final options = <Currency>{
      if (family != null) family,
      ...?data?.currencies,
      if (current != null) current,
    }.toList();
    if (options.isEmpty) options.add(Currency.mmk);
    showAppBottomSheet<void>(
      context: context,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.familySpendingCurrency, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final c in options)
            ListTile(
              key: Key('family-spending-currency-${c.name}'),
              contentPadding: EdgeInsets.zero,
              title: Text('${c.symbol} ${c.name.toUpperCase()} · ${c.displayName}'),
              trailing: c == _currency ? Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary) : null,
              onTap: () {
                Navigator.pop(sheet);
                if (c != _currency) {
                  _currency = c;
                  _load();
                }
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.familySpending)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _monthBar(l),
            const SizedBox(height: 12),
            ..._body(l),
          ],
        ),
      ),
    );
  }

  Widget _monthBar(AppLocalizations l) {
    final scheme = Theme.of(context).colorScheme;
    final currency = _currency;
    return Row(
      children: [
        IconButton(
          key: const Key('family-spending-prev'),
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: _canGoBack && !_loading ? () => _go(-1) : null,
        ),
        Expanded(
          child: Text(
            l.formatMonthYear(_month),
            key: const Key('family-spending-month'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          key: const Key('family-spending-next'),
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: _canGoForward && !_loading ? () => _go(1) : null,
        ),
        if (currency != null)
          TextButton.icon(
            key: const Key('family-spending-currency'),
            onPressed: _pickCurrency,
            icon: Icon(Icons.expand_more_rounded, size: 18, color: scheme.onSurfaceVariant),
            label: Text(currency.name.toUpperCase()),
          ),
      ],
    );
  }

  List<Widget> _body(AppLocalizations l) {
    final data = _data;
    // While a month or currency loads, never the previous figures: they'd sit under the new month's name.
    if (_loading) {
      return const [Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))];
    }
    if (_error != null) {
      return [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(key: const Key('family-spending-retry'), onPressed: _load, child: Text(l.tryAgain)),
          ]),
        ),
      ];
    }
    if (data == null) return const [];
    if (data.currencies.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            const Mascot(MascotPose.budgetpieHappy, size: 120),
            const SizedBox(height: 16),
            Text(l.familySpendingNoneYet, textAlign: TextAlign.center),
          ]),
        ),
      ];
    }
    final change = spendingChange(l, data.total, data.previousTotal);
    final previous = DateTime(data.month.year, data.month.month - 1);
    return [
      HeroCard(
        label: l.familySpendingTotal,
        value: formatMoney(data.total, data.currency),
        supporting: change == null ? null : '$change ${l.familySpendingVsLast(l.formatShortMonth(previous))}',
      ),
      const SizedBox(height: 16),
      if (data.rows.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l.familySpendingNoneThisMonth, textAlign: TextAlign.center),
        )
      else
        for (final row in data.rows) _row(l, row, data),
    ];
  }

  Widget _row(AppLocalizations l, FamilySpendingRow row, FamilySpendingOverview data) {
    final scheme = Theme.of(context).colorScheme;
    final name = row.isWholeFamily
        ? l.wholeFamily
        : row.isFormer
            ? l.familyFormerName(row.displayName)
            : row.displayName;
    final share = data.total > 0 ? row.amount / data.total : 0.0;
    final change = spendingChange(l, row.amount, row.previousAmount);
    return InkWell(
      key: Key('family-spending-row-${row.memberId ?? 'whole'}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openPerson(row, data),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                const SizedBox(width: 8),
                Text(formatMoney(row.amount, data.currency), style: AppTheme.money(14, weight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            ProgressMeter(value: share),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('${(share * 100).round()}%', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const Spacer(),
                if (change != null)
                  Text(change, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openPerson(FamilySpendingRow row, FamilySpendingOverview data) {
    final l = AppLocalizations.of(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FamilyPersonSpendingScreen(
          month: data.month,
          currency: data.currency,
          memberId: row.memberId,
          displayName: row.isWholeFamily ? l.wholeFamily : row.displayName,
          loader: widget.personLoader ?? ApiService.getFamilyPersonSpending,
        ),
      ),
    );
  }
}
