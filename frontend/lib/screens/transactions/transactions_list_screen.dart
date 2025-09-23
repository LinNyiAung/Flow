import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/transaction.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../services/api_service.dart';
import '../transactions/edit_transaction_screen.dart';
import '../transactions/add_transaction_screen.dart'; // Make sure to import this

class TransactionsListScreen extends StatefulWidget {
  @override
  _TransactionsListScreenState createState() => _TransactionsListScreenState();
}

class _TransactionsListScreenState extends State<TransactionsListScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // State variables for filters
  TransactionType? _selectedFilterType;
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;

  // State for filter section visibility
  bool _isFiltersExpanded = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchTransactionsWithFilter();
    });
  }

  Future<void> _fetchTransactionsWithFilter() async {
    await Provider.of<TransactionProvider>(context, listen: false).fetchTransactions(
      type: _selectedFilterType,
      startDate: _selectedStartDate,
      endDate: _selectedEndDate,
    );
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
    });
    _fetchTransactionsWithFilter();
  }

  // Function to handle navigation to AddTransactionScreen
  void _navigateToAddTransaction() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddTransactionScreen()),
    );

    // If a new transaction was added successfully, refresh the list
    if (result == true) {
      _refreshData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Transaction added successfully!',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: Color(0xFF4CAF50), // Success green
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final transactionProvider = Provider.of<TransactionProvider>(context);

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      appBar: AppBar(
        title: Text(
          'All Transactions',
          style: GoogleFonts.poppins(
            fontSize: 20,
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
          if (_selectedFilterType != null || _selectedStartDate != null)
            IconButton(
              icon: Container( // Visual representation of the button for consistent styling
                padding: EdgeInsets.all(8),
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
              tooltip: 'Clear All Filters',
              onPressed: _clearAllFilters, // Use the dedicated clear function
            ),
          // Notification icon (keeping as is, similar to HomeScreen's actions)
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Container(
              padding: EdgeInsets.all(8),
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
              child: Icon(
                Icons.notifications_outlined,
                color: Color(0xFF667eea),
              ),
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
              margin: EdgeInsets.all(10.0),
              padding: EdgeInsets.all(15.0),
              // APPLYING THE GRADIENT BACKGROUND HERE
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)], // Purple gradient from balance card
                ),
                borderRadius: BorderRadius.circular(20), // Matching balance card's border radius
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
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Filters',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
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
                                'Transaction Type:',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withOpacity(0.9), // Adjusted color for contrast
                                ),
                              ),
                              SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildFilterChip(
                                    label: 'All',
                                    type: null,
                                    isSelected: _selectedFilterType == null,
                                    onSelected: (selected) {
                                      setState(() { _selectedFilterType = null; });
                                      _fetchTransactionsWithFilter();
                                    },
                                  ),
                                  _buildFilterChip(
                                    label: 'Inflow',
                                    type: TransactionType.inflow,
                                    isSelected: _selectedFilterType == TransactionType.inflow,
                                    onSelected: (selected) {
                                      setState(() { _selectedFilterType = TransactionType.inflow; });
                                      _fetchTransactionsWithFilter();
                                    },
                                  ),
                                  _buildFilterChip(
                                    label: 'Outflow',
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

                              // Date Range Filter
                              Text(
                                'Date Range:',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
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
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                        label: Text(
                                          _selectedStartDate == null
                                              ? 'Select Date Range'
                                              : '${DateFormat('MMM dd').format(_selectedStartDate!)} - ${DateFormat('MMM dd, yyyy').format(_selectedEndDate!)}',
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white,
                                          ),
                                        ),
                                        onPressed: _presentDateRangePicker,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.transparent, // Transparent to show gradient/color
                                          shadowColor: Colors.transparent,
                                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                                          icon: Icon(Icons.clear, color: Colors.red.shade400, size: 20),
                                          tooltip: 'Clear Date Filter',
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
                  if (_isFiltersExpanded && (_selectedFilterType != null || _selectedStartDate != null))
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Center(
                        child: TextButton.icon(
                          onPressed: _clearAllFilters,
                          icon: Icon(Icons.refresh, color: Colors.white, size: 18), // White icon on gradient
                          label: Text(
                            'Clear All Filters',
                            style: GoogleFonts.poppins(
                              color: Colors.white, // White text on gradient
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
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
                            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            itemCount: transactionProvider.transactions.length,
                            itemBuilder: (context, index) {
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
        child: Icon(Icons.add, color: Colors.white, size: 28),
        elevation: 8,
        tooltip: 'Add New Transaction',
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                size: 48,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 24),
            Text(
              'No transactions found',
              style: GoogleFonts.poppins(
                fontSize: 18,
                color: Color(0xFF333333),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Try adjusting your filters or adding a transaction.',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
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
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: labelColor,
        ),
      ),
      selected: isSelected,
      onSelected: onSelected,
      selectedColor: chipColor,
      backgroundColor: chipColor, // Use selected color as background for consistency
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
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
    return GestureDetector(
      onTap: () => _navigateToEditTransaction(transaction),
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(16),
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
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333),
                    ),
                  ),
                  Text(
                    transaction.mainCategory,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (transaction.description != null && transaction.description!.isNotEmpty) ...[
                    SizedBox(height: 2),
                    Text(
                      transaction.description!,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
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
                  '${transaction.type == TransactionType.inflow ? '+' : '-'}\$${transaction.amount.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: transaction.type == TransactionType.inflow ? Color(0xFF4CAF50) : Color(0xFFFF5722),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  DateFormat('MMM dd, yyyy').format(transaction.date),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
            SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
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