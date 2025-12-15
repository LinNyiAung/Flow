import 'package:flutter/material.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/screens/transactions/image_input_screen.dart';
import 'package:frontend/screens/transactions/voice_input_screen.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/transaction.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../services/api_service.dart';
import '../transactions/edit_transaction_screen.dart';
import '../transactions/add_transaction_screen.dart'; // Make sure to import this
import 'package:frontend/services/responsive_helper.dart';

class TransactionsListScreen extends StatefulWidget {
  @override
  _TransactionsListScreenState createState() => _TransactionsListScreenState();
}

class _TransactionsListScreenState extends State<TransactionsListScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController(); // ADD THIS

  // State variables for filters
  TransactionType? _selectedFilterType;
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;

  // State for filter section visibility
  bool _isFiltersExpanded = false;


  // ADD THESE PAGINATION VARIABLES
  int _currentLimit = 50;
  bool _isLoadingMore = false;
  bool _hasMoreData = true;

  Currency? _selectedCurrency;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchTransactionsWithFilter();
    });
    
    // ADD SCROLL LISTENER
    _scrollController.addListener(_onScroll);
  }


  // ADD THIS METHOD
  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMoreData) {
        _loadMoreTransactions();
      }
    }
  }



// REPLACE _loadMoreTransactions in transactions_list_screen.dart
Future<void> _loadMoreTransactions() async {
  if (_isLoadingMore) return;

  setState(() {
    _isLoadingMore = true;
  });

  final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
  final currentCount = transactionProvider.transactions.length;

  // Increase limit to load more
  _currentLimit += 50;

  // Use the new method that doesn't trigger full loading state
  await transactionProvider.loadMoreTransactions(
    type: _selectedFilterType,
    startDate: _selectedStartDate,
    endDate: _selectedEndDate,
    currency: _selectedCurrency, // ADD THIS LINE
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
  // RESET PAGINATION STATE
  setState(() {
    _currentLimit = 50;
    _hasMoreData = true;
  });

  await Provider.of<TransactionProvider>(context, listen: false).fetchTransactions(
    type: _selectedFilterType,
    startDate: _selectedStartDate,
    endDate: _selectedEndDate,
    currency: _selectedCurrency, // ADD THIS LINE
    limit: _currentLimit,
  );

  // Check if we have less than the limit, meaning no more data
  final loadedCount = Provider.of<TransactionProvider>(context, listen: false).transactions.length;
  setState(() {
    _hasMoreData = loadedCount >= _currentLimit;
  });
}


  @override
  void dispose() {
    _scrollController.dispose(); // ADD THIS
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
          data: ThemeData.light().copyWith(
            primaryColor: Color(0xFF667eea), // Primary purple
            appBarTheme: AppBarTheme(backgroundColor: Color(0xFF667eea)),
            colorScheme: ColorScheme.light(primary: Color(0xFF667eea)),
            buttonTheme: ButtonThemeData(textTheme: ButtonTextTheme.primary),
          ),
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
    _selectedCurrency = null; // ADD THIS LINE
  });
  _fetchTransactionsWithFilter();
}

  // Function to handle navigation to AddTransactionScreen
  void _navigateToAddTransaction() {
  _showAddTransactionOptions();
}

void _showAddTransactionOptions() {
  final localizations = AppLocalizations.of(context);
  final responsive = ResponsiveHelper(context);
  showModalBottomSheet(
    context: context,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext context) {
      return Container(
        padding: responsive.padding(all: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header (keep as is)
            Row(
              children: [
                Container(
                  padding: responsive.padding(all: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.add, color: Colors.white, size: responsive.icon20),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    localizations.addTransaction,
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF333333),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 24),

            // Manual Entry Option (NO CHANGES - not premium)
            _buildAddOption(
              icon: Icons.edit_outlined,
              title: localizations.manualEntry,
              subtitle: localizations.typeTransactionDetails,
              gradientColors: [Color(0xFF667eea), Color(0xFF764ba2)],
              isPremiumFeature: false, // ADD THIS
              onTap: () async {
                Navigator.pop(context);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AddTransactionScreen()),
                );
                if (result == true) {
                  _refreshData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        localizations.transactionAdded,
                        style: GoogleFonts.poppins(color: Colors.white),
                      ),
                      backgroundColor: Color(0xFF4CAF50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),
            SizedBox(height: 12),

            // Voice Input Option - MARK AS PREMIUM
            _buildAddOption(
              icon: Icons.mic,
              title: localizations.voiceInput,
              subtitle: localizations.speakYourTransaction,
              gradientColors: [Color(0xFF4CAF50), Color(0xFF45a049)],
              isPremiumFeature: true, // ADD THIS - marks as premium
              onTap: () async {
                Navigator.pop(context);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => VoiceInputScreen()),
                );
                if (result == true) {
                  _refreshData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        localizations.transactionAdded,
                        style: GoogleFonts.poppins(color: Colors.white),
                      ),
                      backgroundColor: Color(0xFF4CAF50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),
            SizedBox(height: 12),

            // Image Input Option - MARK AS PREMIUM
            _buildAddOption(
              icon: Icons.camera_alt,
              title: localizations.scanReceipt,
              subtitle: localizations.takeUploadPhoto,
              gradientColors: [Color(0xFFFF9800), Color(0xFFF57C00)],
              isPremiumFeature: true, // ADD THIS - marks as premium
              onTap: () async {
                Navigator.pop(context);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ImageInputScreen()),
                );
                if (result == true) {
                  _refreshData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        localizations.transactionAdded,
                        style: GoogleFonts.poppins(color: Colors.white),
                      ),
                      backgroundColor: Color(0xFF4CAF50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),
            SizedBox(height: 16),
          ],
        ),
      );
    },
  );
}

Widget _buildAddOption({
  required IconData icon,
  required String title,
  required String subtitle,
  required List<Color> gradientColors,
  required VoidCallback onTap,
  bool isPremiumFeature = false, // NEW parameter
}) {
  // Get auth provider to check premium status
  final authProvider = Provider.of<AuthProvider>(context, listen: false);
  final isLocked = isPremiumFeature && !authProvider.isPremium;
  final localizations = AppLocalizations.of(context);
  final responsive = ResponsiveHelper(context);

  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      padding: responsive.padding(all: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLocked 
              ? Color(0xFFFFD700).withOpacity(0.3)
              : Colors.grey.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                padding: responsive.padding(all: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradientColors),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: responsive.icon24),
              ),
              if (isLocked)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Color(0xFFFFD700),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFFFFD700).withOpacity(0.3),
                          spreadRadius: 1,
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.lock,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF333333),
                      ),
                    ),
                    if (isLocked) ...[
                      SizedBox(width: responsive.sp8),
                      Container(
                        padding: responsive.padding(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Color(0xFFFFD700).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Color(0xFFFFD700),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          localizations.premium,
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFFD700),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_ios,
            size: responsive.icon16,
            color: Colors.grey[400],
          ),
        ],
      ),
    ),
  );
}


  @override
  Widget build(BuildContext context) {
    final transactionProvider = Provider.of<TransactionProvider>(context);
    final localizations = AppLocalizations.of(context);
    final responsive = ResponsiveHelper(context);
    
    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      drawerEnableOpenDragGesture: true,  // ADD THIS LINE
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        title: Text(
          localizations.allTransactionsTitle,
          style: GoogleFonts.poppins(
            fontSize: responsive.fs20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.menu),
          color: Color(0xFF333333),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          // Clear filter button - Now correctly wrapped in IconButton
          if (_selectedFilterType != null || _selectedStartDate != null || _selectedCurrency != null)
            IconButton(
              icon: Container( // Visual representation of the button for consistent styling
                padding: responsive.padding(all: 8),
                decoration: BoxDecoration(
                  color: Colors.white, // Keep white background for contrast
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.filter_list_off,
                  color: Color(0xFF667eea), // Use primary purple color
                ),
              ),
              tooltip: localizations.clearAllFiltersButton,
              onPressed: _clearAllFilters, // Use the dedicated clear function
            ),
          // Notification icon (keeping as is, similar to HomeScreen's actions)
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Consumer<NotificationProvider>(
              builder: (context, notificationProvider, child) {
                return Stack(
                  children: [
                    Container(
                      padding: responsive.padding(all: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            spreadRadius: 1,
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.notifications_outlined,
                          color: Color(0xFF667eea),
                        ),
                        onPressed: () {
                          Navigator.pushNamed(context, '/notifications').then((
                            _,
                          ) {
                            // Refresh data when returning from notifications
                            notificationProvider.fetchUnreadCount();
                          });
                        },
                      ),
                    ),
                    if (notificationProvider.unreadCount > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: BoxConstraints(
                            minWidth: responsive.iconSize(mobile: 20),
                            minHeight: responsive.iconSize(mobile: 20),
                          ),
                          child: Text(
                            '${notificationProvider.unreadCount > 9 ? '9+' : notificationProvider.unreadCount}',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: responsive.fs10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
        backgroundColor: Colors.transparent, // Match HomeScreen's transparent AppBar
        elevation: 0, // Match HomeScreen's elevation
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF667eea).withOpacity(0.1), // Subtle gradient
              Colors.white,
            ],
          ),
        ),
        child: Column(
          children: [
            // Filter Section with toggle functionality and gradient background
            Container(
              margin: responsive.padding(all: 10),
              padding: responsive.padding(all: 15),
              // APPLYING THE GRADIENT BACKGROUND HERE
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)], // Purple gradient from balance card
                ),
                borderRadius: BorderRadius.circular(responsive.borderRadius(20)), // Matching balance card's border radius
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 2,
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Filter Header with toggle icon
                  Row(
                    children: [
                      Icon(
                        Icons.filter_list,
                        color: Colors.white, // Changed icon color to white for contrast on gradient
                        size: responsive.icon20,
                      ),
                      SizedBox(width: responsive.sp8),
                      Text(
                        localizations.filtersSectionTitle,
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white, // Changed text color to white for contrast
                        ),
                      ),
                      Spacer(),
                      IconButton(
                        icon: Icon(
                          _isFiltersExpanded ? Icons.expand_less : Icons.expand_more,
                          color: Colors.white, // Changed icon color to white for contrast
                        ),
                        onPressed: () {
                          setState(() {
                            _isFiltersExpanded = !_isFiltersExpanded;
                          });
                        },
                      ),
                    ],
                  ),


                  // Animated content for filters
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: _isFiltersExpanded
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Transaction Type Filter
                              Text(
                                localizations.transactionTypeFilterLabel,
                                style: GoogleFonts.poppins(
                                  fontSize: responsive.fs14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withOpacity(0.9), // Adjusted color for contrast
                                ),
                              ),
                              SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildFilterChip(
                                    label: localizations.filterChipAll,
                                    type: null,
                                    isSelected: _selectedFilterType == null,
                                    onSelected: (selected) {
                                      setState(() { _selectedFilterType = null; });
                                      _fetchTransactionsWithFilter();
                                    },
                                  ),
                                  _buildFilterChip(
                                    label: localizations.inflow,
                                    type: TransactionType.inflow,
                                    isSelected: _selectedFilterType == TransactionType.inflow,
                                    onSelected: (selected) {
                                      setState(() { _selectedFilterType = TransactionType.inflow; });
                                      _fetchTransactionsWithFilter();
                                    },
                                  ),
                                  _buildFilterChip(
                                    label: localizations.outflow,
                                    type: TransactionType.outflow,
                                    isSelected: _selectedFilterType == TransactionType.outflow,
                                    onSelected: (selected) {
                                      setState(() { _selectedFilterType = TransactionType.outflow; });
                                      _fetchTransactionsWithFilter();
                                    },
                                  ),
                                ],
                              ),
                              SizedBox(height: 20),

                              // Currency Filter
                              Text(
                                localizations.currencyFilter,
                                style: GoogleFonts.poppins(
                                  fontSize: responsive.fs14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                              SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _buildCurrencyFilterChip(
                                    label: localizations.filterChipAll,
                                    currency: null,
                                    isSelected: _selectedCurrency == null,
                                    onSelected: (selected) {
                                      setState(() { _selectedCurrency = null; });
                                      _fetchTransactionsWithFilter();
                                    },
                                  ),
                                  ...Currency.values.map((currency) {
                                    return _buildCurrencyFilterChip(
                                      label: '${currency.symbol} ${currency.name.toUpperCase()}',
                                      currency: currency,
                                      isSelected: _selectedCurrency == currency,
                                      onSelected: (selected) {
                                        setState(() { _selectedCurrency = currency; });
                                        _fetchTransactionsWithFilter();
                                      },
                                    );
                                  }).toList(),
                                ],
                              ),
                              SizedBox(height: 20),

                              // Date Range Filter
                              Text(
                                localizations.dateRangeFilterLabel,
                                style: GoogleFonts.poppins(
                                  fontSize: responsive.fs14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withOpacity(0.9), // Adjusted color for contrast
                                ),
                              ),
                              SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: _selectedStartDate != null
                                            ? LinearGradient(
                                                colors: [Color(0xFF667eea), Color(0xFF764ba2)], // Purple gradient
                                              )
                                            : null,
                                        color: _selectedStartDate == null ? Colors.white.withOpacity(0.2) : null, // Lighter background if no date selected
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: ElevatedButton.icon(
                                        icon: Icon(
                                          Icons.calendar_today,
                                          size: responsive.icon18,
                                          color: Colors.white,
                                        ),
                                        label: Text(
                                          _selectedStartDate == null
                                              ? localizations.selectDateRangeButton
                                              : '${DateFormat('MMM dd').format(_selectedStartDate!)} - ${DateFormat('MMM dd, yyyy').format(_selectedEndDate!)}',
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          style: GoogleFonts.poppins(
                                            fontSize: responsive.fs13,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white,
                                          ),
                                        ),
                                        onPressed: _presentDateRangePicker,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.transparent, // Transparent to show gradient/color
                                          shadowColor: Colors.transparent,
                                          padding: responsive.padding(horizontal: 16, vertical: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          elevation: 0,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_selectedStartDate != null)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8.0),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: IconButton(
                                          icon: Icon(Icons.clear, color: Colors.red.shade400, size: responsive.icon20),
                                          tooltip: localizations.clearDateFilterTooltip,
                                          onPressed: _clearDateFilter,
                                          splashRadius: 20,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          )
                        : null, // Content is hidden when collapsed
                  ),

                  // Clear All Filters Button - conditionally shown and aligned to center
                  if (_isFiltersExpanded && (_selectedFilterType != null || _selectedStartDate != null || _selectedCurrency != null))
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Center(
                        child: TextButton.icon(
                          onPressed: _clearAllFilters,
                          icon: Icon(Icons.refresh, color: Colors.white, size: responsive.icon18), // White icon on gradient
                          label: Text(
                            localizations.clearAllFiltersButton,
                            style: GoogleFonts.poppins(
                              color: Colors.white, // White text on gradient
                              fontWeight: FontWeight.w500,
                              fontSize: responsive.fs13,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Transactions List with enhanced styling
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshData,
                color: Color(0xFF667eea), // Purple refresh indicator
                child: transactionProvider.isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
                        ),
                      )
                    : transactionProvider.transactions.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            controller: _scrollController, // ADD THIS
                            padding: responsive.padding(horizontal: 16, vertical: 8),
                            itemCount: transactionProvider.transactions.length + (_hasMoreData ? 1 : 0), // MODIFIED
                            itemBuilder: (context, index) {
                              // ADD LOADING INDICATOR AT THE END
                              if (index == transactionProvider.transactions.length) {
                                return Container(
                                  padding: responsive.padding(vertical: 24),
                                  child: Center(
                                    child: Column(
                                      children: [
                                        SizedBox(
                                          width: responsive.iconSize(mobile: 24),
                                          height: responsive.iconSize(mobile: 24),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
                                          ),
                                        ),
                                        SizedBox(height: 12),
                                        Text(
                                          localizations.loadingMoreIndicator,
                                          style: GoogleFonts.poppins(
                                            fontSize: responsive.fs12,
                                            color: Colors.grey[500],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              final transaction = transactionProvider.transactions[index];
                              return _buildTransactionCard(transaction);
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
      // Floating Action Button added here
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddTransaction, // Call the new function to add transaction
        backgroundColor: Color(0xFF667eea), // Primary color for FAB
        child: Icon(Icons.add, color: Colors.white, size: responsive.icon28),
        elevation: 8,
        tooltip: localizations.addTransactionFabTooltip,
      ),
    );
  }

  Widget _buildEmptyState() {
    final localizations = AppLocalizations.of(context);
    final responsive = ResponsiveHelper(context);

    return Center(
      child: Container(
        padding: responsive.padding(all: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: responsive.padding(all: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
                borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                size: responsive.icon48,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 24),
            Text(
              localizations.emptyStateTitle,
              style: GoogleFonts.poppins(
                fontSize: responsive.fs18,
                color: Color(0xFF333333),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              localizations.emptyStateSubtitle,
              style: GoogleFonts.poppins(
                fontSize: responsive.fs14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildCurrencyFilterChip({
  required String label,
  required Currency? currency,
  required bool isSelected,
  required ValueChanged<bool> onSelected,
}) {
  Color chipColor;
  Color labelColor;
  final responsive = ResponsiveHelper(context);

  if (isSelected) {
    chipColor = Color(0xFF667eea); // Primary purple color for selected
    labelColor = Colors.white;
  } else {
    chipColor = Colors.white.withOpacity(0.2); // Lighter transparent background for unselected
    labelColor = Colors.black.withOpacity(0.9); // White text for better contrast on gradient
  }

  return ChoiceChip(
    label: Text(
      label,
      style: GoogleFonts.poppins(
        fontSize: responsive.fs13,
        fontWeight: FontWeight.w500,
        color: labelColor,
      ),
    ),
    selected: isSelected,
    onSelected: onSelected,
    selectedColor: chipColor,
    backgroundColor: chipColor,
    padding: responsive.padding(horizontal: 16, vertical: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
      side: BorderSide(
        color: isSelected ? chipColor : Colors.transparent,
        width: 1,
      ),
    ),
    elevation: isSelected ? 4 : 0,
    shadowColor: chipColor.withOpacity(0.3),
  );
}

  Widget _buildFilterChip({
    required String label,
    required TransactionType? type,
    required bool isSelected,
    required ValueChanged<bool> onSelected,
  }) {
    Color chipColor;
    Color labelColor;
    final responsive = ResponsiveHelper(context);

    if (isSelected) {
      if (type == TransactionType.inflow) {
        chipColor = Color(0xFF4CAF50); // Green for inflow
        labelColor = Colors.white;
      } else if (type == TransactionType.outflow) {
        chipColor = Color(0xFFFF5722); // Red for outflow
        labelColor = Colors.white;
      } else {
        // Use primary purple color for "All" selection
        chipColor = Color(0xFF667eea);
        labelColor = Colors.white;
      }
    } else {
      chipColor = Colors.white.withOpacity(0.2); // Lighter transparent background for unselected
      labelColor = Colors.black.withOpacity(0.9); // White text for better contrast on gradient
    }

    return ChoiceChip(
      label: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: responsive.fs13,
          fontWeight: FontWeight.w500,
          color: labelColor,
        ),
      ),
      selected: isSelected,
      onSelected: onSelected,
      selectedColor: chipColor,
      backgroundColor: chipColor, // Use selected color as background for consistency
      padding: responsive.padding(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
        side: BorderSide(
          // Use slightly darker border color when selected for definition, or match chip color
          color: isSelected ? chipColor : Colors.transparent, // Changed border logic for consistency
          width: 1,
        ),
      ),
      elevation: isSelected ? 4 : 0, // Slightly higher elevation when selected
      shadowColor: chipColor.withOpacity(0.3),
    );
  }

  Widget _buildTransactionCard(Transaction transaction) {
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);
    return GestureDetector(
      onTap: () => _navigateToEditTransaction(transaction),
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: responsive.padding(all: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.08),
              spreadRadius: 1,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
          // Add subtle purple left border for visual interest
          border: Border(
            left: BorderSide(
              color: Color(0xFF667eea).withOpacity(0.3),
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: transaction.type == TransactionType.inflow
                    ? Color(0xFF4CAF50).withOpacity(0.1)
                    : Color(0xFFFF5722).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                transaction.type == TransactionType.inflow ? Icons.arrow_upward : Icons.arrow_downward,
                color: transaction.type == TransactionType.inflow ? Color(0xFF4CAF50) : Color(0xFFFF5722),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.subCategory,
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333),
                    ),
                  ),
                    if (transaction.recurrence?.enabled ?? false) ...[
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.repeat,
                          size: 14,
                          color: Color(0xFF667eea),
                        ),
                        SizedBox(width: 4),
                        Text(
                          transaction.recurrence!.config!.getDisplayText(),
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs11,
                            color: Color(0xFF667eea),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                  // Also show if it's auto-created
                  if (transaction.parentTransactionId != null) ...[
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 14,
                          color: Color(0xFFFF9800),
                        ),
                        SizedBox(width: 4),
                        Text(
                          localizations.autoCreated,
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs11,
                            color: Color(0xFFFF9800),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                  Text(
                    transaction.mainCategory,
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs12,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (transaction.description != null && transaction.description!.isNotEmpty) ...[
                    SizedBox(height: 2),
                    Text(
                      transaction.description!,
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs12,
                        color: Colors.grey[500],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${transaction.type == TransactionType.inflow ? '+' : '-'}${transaction.currency.symbol}${transaction.amount.toStringAsFixed(2)}', // UPDATED to include currency
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs16,
                    fontWeight: FontWeight.bold,
                    color: transaction.type == TransactionType.inflow ? Color(0xFF4CAF50) : Color(0xFFFF5722),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  DateFormat('MMM dd, yyyy').format(transaction.date),
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
            SizedBox(width: responsive.sp8),
            Icon(
              Icons.arrow_forward_ios,
              size: responsive.icon16,
              color: Color(0xFF667eea).withOpacity(0.6), // Purple arrow
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