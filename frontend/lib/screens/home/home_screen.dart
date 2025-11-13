import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/providers/goal_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/screens/transactions/image_input_screen.dart';
import 'package:frontend/screens/transactions/transactions_list_screen.dart';
import 'package:frontend/screens/transactions/voice_input_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../models/transaction.dart';
import '../auth/login_screen.dart';
import '../transactions/add_transaction_screen.dart';
import '../transactions/edit_transaction_screen.dart'; // Import for editing
import '../../widgets/app_drawer.dart'; // Import the drawer widget

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey =
      GlobalKey<ScaffoldState>(); // Key for the Scaffold to open the drawer
  Timer? _notificationTimer;

  @override
  void initState() {
    super.initState();
    // Fetch initial data when the screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData(); // Fetch transactions and balance
      _startNotificationPolling();
    });
  }

  // ADD THIS METHOD
  void _startNotificationPolling() {
    final notificationProvider = Provider.of<NotificationProvider>(
      context,
      listen: false,
    );

    // Initial fetch
    notificationProvider.fetchUnreadCount();

    // Poll every 30 seconds
    _notificationTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      notificationProvider.fetchNotifications();
    });
  }

  // ADD THIS METHOD
  @override
  void dispose() {
    _notificationTimer?.cancel();
    super.dispose();
  }

  // Function to refresh data (pull-to-refresh and initial load)
  Future<void> _refreshData() async {
    final transactionProvider = Provider.of<TransactionProvider>(
      context,
      listen: false,
    );
    final goalProvider = Provider.of<GoalProvider>(
      context,
      listen: false,
    ); // ADD THIS
    final notificationProvider = Provider.of<NotificationProvider>(
      context,
      listen: false,
    ); // ADD THIS

    await Future.wait([
      transactionProvider.fetchTransactions(limit: 3),
      transactionProvider.fetchBalance(),
      goalProvider.fetchSummary(), // ADD THIS
      notificationProvider.fetchUnreadCount(), // ADD THIS
    ]);
  }

  // Function to navigate to the TransactionsListScreen
  void _navigateToTransactionsList() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TransactionsListScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen to AuthProvider for user details and TransactionProvider for data
    final authProvider = Provider.of<AuthProvider>(context);
    final transactionProvider = Provider.of<TransactionProvider>(context);

    return Scaffold(
      key: _scaffoldKey, // Assign the scaffold key to the Scaffold
      drawer: AppDrawer(), // Add the navigation drawer to the scaffold
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        title: Text(
          'Dashboard', // Title for the Home Screen AppBar
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.menu), // Menu icon
          color: Color(0xFF333333),
          onPressed: () => _scaffoldKey.currentState
              ?.openDrawer(), // Use the key to open the drawer
        ),
        actions: [
          // Notification Icon with Badge
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Consumer<NotificationProvider>(
              builder: (context, notificationProvider, child) {
                return Stack(
                  children: [
                    Container(
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
                            minWidth: 20,
                            minHeight: 20,
                          ),
                          child: Text(
                            '${notificationProvider.unreadCount > 9 ? '9+' : notificationProvider.unreadCount}',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 10,
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
        // AppBar theme from main.dart makes background transparent and removes elevation by default.
        // If you want a specific background color for Home and Transaction AppBar:
        // backgroundColor: Colors.white, // Or any color you prefer
        // elevation: 1,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(
                0xFF667eea,
              ).withOpacity(0.1), // Subtle gradient matching theme
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          // RefreshIndicator allows pull-to-refresh functionality
          child: RefreshIndicator(
            onRefresh: _refreshData,
            color: Color(0xFF667eea), // Purple refresh indicator
            child: CustomScrollView(
              // Use CustomScrollView for flexible layouts with slivers
              slivers: [
                // Header Section (Welcome message)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome back,',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              authProvider.user?.name ??
                                  'User', // Display user name or 'User' if null
                              style: GoogleFonts.poppins(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF333333),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Balance Card
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 8,
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total Balance',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 16,
                                  ),
                                ),
                                Icon(
                                  Icons.account_balance_wallet,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(
                              '\$${transactionProvider.balance?.balance.toStringAsFixed(2) ?? '0.00'}',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Available: \$${transactionProvider.balance?.availableBalance.toStringAsFixed(2) ?? '0.00'}',
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (transactionProvider.balance?.allocatedToGoals !=
                                    null &&
                                transactionProvider.balance!.allocatedToGoals >
                                    0) ...[
                              SizedBox(height: 2),
                              Text(
                                'Allocated to Goals: \$${transactionProvider.balance!.allocatedToGoals.toStringAsFixed(2)}',
                                style: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildBalanceInfo(
                                  icon: Icons.arrow_upward,
                                  label: 'Inflow',
                                  amount:
                                      transactionProvider
                                          .balance
                                          ?.totalInflow ??
                                      0.0,
                                  color: Colors.green,
                                ),
                                Container(
                                  height: 40,
                                  width: 1,
                                  color: Colors.white.withOpacity(0.3),
                                ),
                                _buildBalanceInfo(
                                  icon: Icons.arrow_downward,
                                  label: 'Outflow',
                                  amount:
                                      transactionProvider
                                          .balance
                                          ?.totalOutflow ??
                                      0.0,
                                  color: Colors.red,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                SliverToBoxAdapter(child: SizedBox(height: 30)), // Spacer
                // AI Assistant Card (Styled consistently)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: GestureDetector(
                      onTap: () => Navigator.pushNamed(context, '/ai-chat'),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              spreadRadius: 2,
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF667eea),
                                    Color(0xFF764ba2),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.smart_toy,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'AI Financial Assistant',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF333333),
                                    ),
                                  ),
                                  Text(
                                    'Get personalized insights',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.grey[400],
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                SliverToBoxAdapter(child: SizedBox(height: 16)), // Spacer
                // AI Insights Card
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: GestureDetector(
                      onTap: () => Navigator.pushNamed(context, '/insights'),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              spreadRadius: 2,
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFFFFB74D),
                                    Color(0xFFFF9800),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.lightbulb,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'AI Insights',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF333333),
                                    ),
                                  ),
                                  Text(
                                    'View comprehensive financial analysis',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.grey[400],
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                SliverToBoxAdapter(child: SizedBox(height: 30)), // Spacer
                // Recent Transactions Header with "See More" action
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Recent Transactions',
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF333333),
                          ),
                        ),
                        // "See More" Text Button
                        GestureDetector(
                          onTap:
                              _navigateToTransactionsList, // Navigate to the full list
                          child: Text(
                            'See More',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(
                                0xFF667eea,
                              ), // Use primary purple color
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(child: SizedBox(height: 16)),

                // Transactions List (only showing recent ones on Home screen)
                if (transactionProvider.isLoading) // Show loader while fetching
                  SliverToBoxAdapter(
                    child: Container(
                      height: 200, // Placeholder height
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF667eea),
                          ),
                        ),
                      ),
                    ),
                  )
                else if (transactionProvider
                    .transactions
                    .isEmpty) // Show empty state
                  SliverToBoxAdapter(
                    child: Container(
                      height: 200, // Placeholder height
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 64,
                              color: Colors.grey[300],
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No transactions yet',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                color: Colors.grey[500],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              'Tap the + button to add your first transaction',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else // Display the list of recent transactions
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        // Limit to showing only the first 3 recent transactions here
                        if (index >= 3)
                          return null; // Stop building items after the 3rd one
                        final transaction =
                            transactionProvider.transactions[index];
                        return Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 4,
                          ),
                          child: _buildTransactionCard(
                            transaction,
                          ), // Build card for each transaction
                        );
                      },
                      childCount: transactionProvider
                          .transactions
                          .length, // Total items available
                    ),
                  ),

                SliverToBoxAdapter(
                  child: SizedBox(height: 100),
                ), // Space at bottom for FAB
              ],
            ),
          ),
        ),
      ),
      // Floating Action Button to add new transactions
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToAddTransaction(),
        backgroundColor: Color(0xFF667eea), // Primary color for FAB
        child: Icon(Icons.add, color: Colors.white, size: 28),
        elevation: 8,
        tooltip: 'Add New Transaction',
      ),
    );
  }

  // Helper widget to display balance information (Inflow/Outflow)
  Widget _buildBalanceInfo({
    required IconData icon,
    required String label,
    required double amount,
    required Color color,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
              ),
            ),
          ],
        ),
        Text(
          '\$${amount.toStringAsFixed(2)}', // Formatted amount
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // Widget to build a card for each transaction (consistent with TransactionsListScreen)
  Widget _buildTransactionCard(Transaction transaction) {
    return GestureDetector(
      onTap: () => _navigateToEditTransaction(
        transaction,
      ), // Navigate to edit screen on tap
      child: Container(
        margin: EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(16),
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
        child: Row(
          children: [
            // Transaction Type Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: transaction.type == TransactionType.inflow
                    ? Color(0xFF4CAF50).withOpacity(0.1) // Light green
                    : Color(0xFFFF5722).withOpacity(0.1), // Light red
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                transaction.type == TransactionType.inflow
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
                color: transaction.type == TransactionType.inflow
                    ? Color(0xFF4CAF50)
                    : Color(0xFFFF5722),
              ),
            ),
            SizedBox(width: 16),
            // Transaction Details (Category, SubCategory, Description)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.subCategory, // Display sub-category
                    style: GoogleFonts.poppins(
                      fontSize: 16,
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
                            fontSize: 11,
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
                          'Auto-created',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Color(0xFFFF9800),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                  Text(
                    transaction.mainCategory, // Display main category
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  // Display description if available and not empty
                  if (transaction.description != null &&
                      transaction.description!.isNotEmpty) ...[
                    SizedBox(height: 2),
                    Text(
                      transaction.description!,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                      maxLines: 1, // Limit description to one line
                      overflow: TextOverflow
                          .ellipsis, // Add ellipsis if text is truncated
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  // Display amount with +/- sign and formatted to 2 decimal places
                  '${transaction.type == TransactionType.inflow ? '+' : '-'}\$${transaction.amount.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: transaction.type == TransactionType.inflow
                        ? Color(0xFF4CAF50)
                        : Color(0xFFFF5722),
                  ),
                ),
                SizedBox(height: 4), // Space between amount and date
                Text(
                  // Display transaction date formatted
                  DateFormat('yyyy-MM-dd').format(transaction.date),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
            SizedBox(width: 8),
            Icon(
              // Arrow icon to indicate tappable card
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  // Navigate to the AddTransactionScreen and handle results
  void _navigateToAddTransaction() {
    _showAddTransactionOptions();
  }

  void _showAddTransactionOptions() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.add, color: Colors.white, size: 20),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Add Transaction',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF333333),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24),

              // Manual Entry Option
              _buildAddOption(
                icon: Icons.edit_outlined,
                title: 'Manual Entry',
                subtitle: 'Type transaction details',
                gradientColors: [Color(0xFF667eea), Color(0xFF764ba2)],
                onTap: () async {
                  Navigator.pop(context);
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AddTransactionScreen()),
                  );
                  if (result == true) {
                    _refreshData();
                    _showSuccessSnackBar('Transaction added successfully!');
                  }
                },
              ),
              SizedBox(height: 12),

              // Voice Input Option
              _buildAddOption(
                icon: Icons.mic,
                title: 'Voice Input',
                subtitle: 'Speak your transaction',
                gradientColors: [Color(0xFF4CAF50), Color(0xFF45a049)],
                onTap: () async {
                  Navigator.pop(context);
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => VoiceInputScreen()),
                  );
                  if (result == true) {
                    _refreshData();
                    _showSuccessSnackBar('Transaction added successfully!');
                  }
                },
              ),
              SizedBox(height: 12),

              // Image Input Option
              _buildAddOption(
                icon: Icons.camera_alt,
                title: 'Scan Receipt',
                subtitle: 'Take or upload receipt photo',
                gradientColors: [Color(0xFFFF9800), Color(0xFFF57C00)],
                onTap: () async {
                  Navigator.pop(context);
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ImageInputScreen()),
                  );
                  if (result == true) {
                    _refreshData();
                    _showSuccessSnackBar('Transaction added successfully!');
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
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
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
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradientColors),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: Color(0xFF4CAF50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Navigate to the EditTransactionScreen and handle results
  void _navigateToEditTransaction(Transaction transaction) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditTransactionScreen(
          transaction: transaction,
        ), // Pass transaction data
      ),
    );

    if (result == true) {
      // Transaction updated
      _refreshData(); // Refresh data
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Transaction updated successfully!',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: Color(0xFF4CAF50), // Success green
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (result == 'deleted') {
      // Transaction deleted
      _refreshData(); // Refresh data
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Transaction deleted successfully!',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: Colors.red, // Error red
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Show logout confirmation dialog
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Logout',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to logout?',
            style: GoogleFonts.poppins(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), // Close dialog
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(color: Colors.grey[600]),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Provider.of<AuthProvider>(
                  context,
                  listen: false,
                ).logout(); // Perform logout
                // Navigate back to login screen and replace current route
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => LoginScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF667eea), // Primary purple color
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Logout',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }
}
