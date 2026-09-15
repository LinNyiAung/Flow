import 'package:flutter/material.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/screens/transactions/image_input_screen.dart';
import 'package:frontend/screens/transactions/voice_input_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/utils/category_icons.dart';
import 'package:frontend/widgets/app_list_row.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import 'package:frontend/widgets/status_pill.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/transaction.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/app_drawer.dart';
import '../transactions/edit_transaction_screen.dart';
import '../transactions/add_transaction_screen.dart'; // Make sure to import this

class TransactionsListScreen extends StatefulWidget {
  @override
  _TransactionsListScreenState createState() => _TransactionsListScreenState();
}

class _TransactionsListScreenState extends State<TransactionsListScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();

  // State variables for filters
  TransactionType? _selectedFilterType;
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;

  // PAGINATION VARIABLES
  int _currentLimit = 50;
  bool _isLoadingMore = false;
  bool _hasMoreData = true;

  Currency? _selectedCurrency;

  final formatter = NumberFormat("#,##0.00", "en_US");

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchTransactionsWithFilter();
    });
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMoreData) {
        _loadMoreTransactions();
      }
    }
  }

  Future<void> _loadMoreTransactions() async {
    if (_isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
    final currentCount = transactionProvider.transactions.length;

    _currentLimit += 50;

    await transactionProvider.loadMoreTransactions(
      type: _selectedFilterType,
      startDate: _selectedStartDate,
      endDate: _selectedEndDate,
      currency: _selectedCurrency,
      limit: _currentLimit,
      currentCount: currentCount,
    );

    final newCount = transactionProvider.transactions.length;

    setState(() {
      _isLoadingMore = false;
      _hasMoreData = newCount > currentCount;
    });
  }

  Future<void> _fetchTransactionsWithFilter() async {
    setState(() {
      _currentLimit = 50;
      _hasMoreData = true;
    });

    await Provider.of<TransactionProvider>(context, listen: false).fetchTransactions(
      type: _selectedFilterType,
      startDate: _selectedStartDate,
      endDate: _selectedEndDate,
      currency: _selectedCurrency,
      limit: _currentLimit,
    );

    final loadedCount = Provider.of<TransactionProvider>(context, listen: false).transactions.length;
    setState(() {
      _hasMoreData = loadedCount >= _currentLimit;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    await _fetchTransactionsWithFilter();
  }

  Future<void> _presentDateRangePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: (_selectedStartDate != null && _selectedEndDate != null)
          ? DateTimeRange(start: _selectedStartDate!, end: _selectedEndDate!)
          : null,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(Duration(days: 365)),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedStartDate = picked.start;
        _selectedEndDate = picked.end;
      });
      _fetchTransactionsWithFilter();
    }
  }

  void _clearDateFilter() {
    setState(() {
      _selectedStartDate = null;
      _selectedEndDate = null;
    });
    _fetchTransactionsWithFilter();
  }

  void _clearAllFilters() {
    setState(() {
      _selectedFilterType = null;
      _selectedStartDate = null;
      _selectedEndDate = null;
      _selectedCurrency = null;
    });
    _fetchTransactionsWithFilter();
  }

  // Function to handle navigation to AddTransactionScreen
  void _navigateToAddTransaction() {
    _showAddTransactionOptions();
  }

  void _showAddTransactionOptions() {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    showAppBottomSheet(
      context: context,
      builder: (sheetContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(localizations.addTransaction, style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: 16),
            AppListRow(
              icon: Icons.edit_rounded,
              iconBg: scheme.secondaryContainer,
              title: localizations.manualEntry,
              subtitle: localizations.typeTransactionDetails,
              onTap: () async {
                Navigator.pop(sheetContext);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AddTransactionScreen()),
                );
                if (result == true) {
                  _refreshData();
                  _showAddedSnackBar();
                }
              },
            ),
            _buildPremiumOptionRow(
              icon: Icons.mic_rounded,
              title: localizations.voiceInput,
              subtitle: localizations.speakYourTransaction,
              onTap: () async {
                Navigator.pop(sheetContext);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => VoiceInputScreen()),
                );
                if (result == true) {
                  _refreshData();
                  _showAddedSnackBar();
                }
              },
            ),
            _buildPremiumOptionRow(
              icon: Icons.document_scanner_rounded,
              title: localizations.scanReceipt,
              subtitle: localizations.takeUploadPhoto,
              onTap: () async {
                Navigator.pop(sheetContext);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ImageInputScreen()),
                );
                if (result == true) {
                  _refreshData();
                  _showAddedSnackBar();
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showAddedSnackBar() {
    final localizations = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(localizations.transactionAdded)),
    );
  }

  Widget _buildPremiumOptionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isLocked = !authProvider.isPremium;
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return AppListRow(
      icon: icon,
      iconBg: scheme.secondaryContainer,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      trailing: isLocked
          ? Padding(
              padding: const EdgeInsets.only(left: 8),
              child: StatusPill(
                label: localizations.premium,
                background: scheme.tertiaryContainer,
                foreground: scheme.tertiary,
              ),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final transactionProvider = Provider.of<TransactionProvider>(context);
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final hasActiveFilters = _selectedFilterType != null || _selectedStartDate != null || _selectedCurrency != null;

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        title: Text(localizations.allTransactionsTitle),
        leading: IconButton(
          icon: Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          if (hasActiveFilters)
            IconButton(
              icon: Icon(Icons.filter_alt_off_rounded),
              tooltip: localizations.clearAllFiltersButton,
              onPressed: _clearAllFilters,
            ),
          Consumer<NotificationProvider>(
            builder: (context, notificationProvider, child) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: Icon(Icons.notifications_rounded),
                    onPressed: () {
                      Navigator.pushNamed(context, '/notifications').then((_) {
                        notificationProvider.fetchUnreadCount();
                      });
                    },
                  ),
                  if (notificationProvider.unreadCount > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: EdgeInsets.all(3),
                        decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                        constraints: BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          notificationProvider.unreadCount > 9 ? '9+' : '${notificationProvider.unreadCount}',
                          style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          _buildCountRow(transactionProvider, localizations, scheme),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshData,
              color: scheme.primary,
              child: transactionProvider.isLoading
                  ? Center(child: CircularProgressIndicator())
                  : transactionProvider.transactions.isEmpty
                      ? _buildEmptyState(localizations)
                      : ListView(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardTheme.color,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(color: const Color(0x14101815), blurRadius: 3, offset: Offset(0, 1)),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  for (final t in transactionProvider.transactions) ...[
                                    _buildTransactionRow(t),
                                    if (t != transactionProvider.transactions.last) Divider(height: 1),
                                  ],
                                ],
                              ),
                            ),
                            if (_hasMoreData)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                  child: Column(
                                    children: [
                                      SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
                                      ),
                                      SizedBox(height: 12),
                                      Text(
                                        localizations.loadingMoreIndicator,
                                        style: Theme.of(context).textTheme.labelMedium,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            SizedBox(height: 100),
                          ],
                        ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddTransaction,
        tooltip: localizations.addTransactionFabTooltip,
        child: Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Column(
      children: [
        SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _typeFilterChip(),
              SizedBox(width: 8),
              _dateChip(),
              SizedBox(width: 8),
              _currencyFilterChip(),
            ],
          ),
        ),
      ],
    );
  }

  // One dropdown chip for transaction type — matches _currencyFilterChip()'s
  // pattern — rather than three separate All/Inflow/Outflow choice chips.
  Widget _typeFilterChip() {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final label = switch (_selectedFilterType) {
      null => localizations.filterChipAll,
      TransactionType.inflow => localizations.inflow,
      TransactionType.outflow => localizations.outflow,
    };

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _pickTypeFilter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_vert_rounded, size: 16, color: scheme.onSurfaceVariant),
            SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface)),
            SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  void _pickTypeFilter() {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final options = <TransactionType?>[null, TransactionType.inflow, TransactionType.outflow];

    showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(localizations.transactionTypeFilterLabel, style: Theme.of(context).textTheme.titleLarge),
          SizedBox(height: 12),
          for (final type in options)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(switch (type) {
                null => localizations.filterChipAll,
                TransactionType.inflow => localizations.inflow,
                TransactionType.outflow => localizations.outflow,
              }),
              trailing: _selectedFilterType == type
                  ? Icon(Icons.check_circle_rounded, color: scheme.primary)
                  : null,
              onTap: () {
                setState(() => _selectedFilterType = type);
                Navigator.pop(sheetContext);
                _fetchTransactionsWithFilter();
              },
            ),
        ],
      ),
    );
  }

  // One dropdown chip for currency — matches _dateChip()'s pattern — rather
  // than a whole second row of per-currency choice chips.
  Widget _currencyFilterChip() {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final label = _selectedCurrency == null
        ? localizations.filterChipAll
        : '${_selectedCurrency!.symbol} ${_selectedCurrency!.name.toUpperCase()}';

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _pickCurrencyFilter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.currency_exchange_rounded, size: 16, color: scheme.onSurfaceVariant),
            SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface),
            ),
            SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  void _pickCurrencyFilter() {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final options = <Currency?>[null, ...Currency.values];

    showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(localizations.currency, style: Theme.of(context).textTheme.titleLarge),
          SizedBox(height: 12),
          for (final currency in options)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                currency == null
                    ? localizations.filterChipAll
                    : '${currency.symbol} ${currency.name.toUpperCase()} · ${currency.displayName}',
              ),
              trailing: _selectedCurrency == currency
                  ? Icon(Icons.check_circle_rounded, color: scheme.primary)
                  : null,
              onTap: () {
                setState(() => _selectedCurrency = currency);
                Navigator.pop(sheetContext);
                _fetchTransactionsWithFilter();
              },
            ),
        ],
      ),
    );
  }

  Widget _dateChip() {
    final localizations = AppLocalizations.of(context);
    final hasDate = _selectedStartDate != null && _selectedEndDate != null;
    final label = hasDate
        ? '${DateFormat('MMM dd').format(_selectedStartDate!)} - ${DateFormat('MMM dd').format(_selectedEndDate!)}'
        : localizations.selectDateRangeButton;

    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _presentDateRangePicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_rounded, size: 16, color: scheme.onSurfaceVariant),
            SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface),
            ),
            if (hasDate) ...[
              SizedBox(width: 4),
              GestureDetector(
                onTap: _clearDateFilter,
                child: Icon(Icons.close_rounded, size: 16, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCountRow(TransactionProvider provider, AppLocalizations localizations, ColorScheme scheme) {
    final count = provider.transactions.length;
    final countLabel = count == 1
        ? localizations.oneTransactionLabel
        : '$count ${localizations.transactionsCountSuffix}';

    // A total is only meaningful in a single currency. If the user hasn't
    // filtered to one but every visible entry happens to share one anyway
    // (the common case), use that — only fall back to a placeholder when
    // the list is genuinely mixed-currency.
    final currencies = provider.transactions.map((t) => t.currency).toSet();
    final totalCurrency = _selectedCurrency ?? (currencies.length == 1 ? currencies.first : null);

    String totalLabel;
    if (totalCurrency != null) {
      double net = 0;
      for (final t in provider.transactions) {
        if (t.currency != totalCurrency) continue;
        net += t.type == TransactionType.inflow ? t.amount : -t.amount;
      }
      final sign = net >= 0 ? '+' : '-';
      totalLabel = '$sign${totalCurrency.symbol}${formatter.format(net.abs())}';
    } else {
      totalLabel = count == 0 ? '' : localizations.mixedCurrenciesLabel;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              countLabel,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: 8),
          Text(totalLabel, style: AppTheme.money(13, weight: FontWeight.w700, color: scheme.onSurface)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations localizations) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
              child: Icon(Icons.receipt_long_rounded, size: 48, color: scheme.primary),
            ),
            SizedBox(height: 24),
            Text(localizations.emptyStateTitle, style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: 8),
            Text(
              localizations.emptyStateSubtitle,
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionRow(Transaction transaction) {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isInflow = transaction.type == TransactionType.inflow;
    final amountColor = isInflow ? scheme.primary : scheme.error;
    // Per the component spec: outflow amounts stay neutral onSurface, only
    // inflow is coloured — colouring both halves makes every row read like
    // an alert. The icon tint above still signals direction.
    final moneyColor = isInflow ? scheme.primary : scheme.onSurface;

    var subtitle = transaction.mainCategory;
    if (transaction.recurrence?.enabled ?? false) {
      subtitle += ' · ${transaction.recurrence!.config!.getDisplayText()}';
    } else if (transaction.parentTransactionId != null) {
      subtitle += ' · ${localizations.autoCreated}';
    }

    return AppListRow(
      icon: iconForCategoryName(transaction.mainCategory),
      iconBg: isInflow ? scheme.primaryContainer : scheme.errorContainer,
      iconColor: amountColor,
      title: transaction.subCategory,
      subtitle: subtitle,
      onTap: () => _navigateToEditTransaction(transaction),
      trailing: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${isInflow ? '+' : '-'}${transaction.currency.symbol}${formatter.format(transaction.amount)}',
              style: AppTheme.money(15, weight: FontWeight.w700, color: moneyColor),
            ),
            SizedBox(height: 2),
            Text(
              DateFormat('MMM dd').format(transaction.date),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToEditTransaction(Transaction transaction) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditTransactionScreen(transaction: transaction),
      ),
    );

    if (result == true || result == 'deleted') {
      _refreshData();
    }
  }
}
