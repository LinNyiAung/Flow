import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/goal_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:frontend/screens/transactions/image_input_screen.dart';
import 'package:frontend/screens/transactions/transactions_list_screen.dart';
import 'package:frontend/screens/transactions/voice_input_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/services/notification_event_bus.dart';
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
import 'package:frontend/services/responsive_helper.dart';

final formatter = NumberFormat("#,##0.00", "en_US");

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription? _notificationSubscription;
  final GlobalKey<ScaffoldState> _scaffoldKey =
      GlobalKey<ScaffoldState>(); // Key for the Scaffold to open the drawer
  

  @override
  void initState() {
    super.initState();
    // Fetch initial data when the screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData(); // Fetch transactions and balance
      
      // NEW: Listen for notification events
      _notificationSubscription = NotificationEventBus()
          .onNotificationReceived
          .listen((_) {
        final notificationProvider = Provider.of<NotificationProvider>(
          context,
          listen: false,
        );
        notificationProvider.fetchUnreadCount();
      });
    });
  }


  // ADD THIS METHOD
  @override
  void dispose() {
    _notificationSubscription?.cancel();
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
  );
  final notificationProvider = Provider.of<NotificationProvider>(
    context,
    listen: false,
  );
  final authProvider = Provider.of<AuthProvider>(
    context,
    listen: false,
  );

  // Get the current default currency
  final defaultCurrency = authProvider.defaultCurrency;

  await Future.wait([
    transactionProvider.fetchTransactions(limit: 3),
    transactionProvider.fetchBalance(currency: defaultCurrency), // Pass default currency
    goalProvider.fetchSummary(),
    notificationProvider.fetchUnreadCount(),
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
    final localizations = AppLocalizations.of(context);
    final responsive = ResponsiveHelper(context);

    return Scaffold(
      key: _scaffoldKey, // Assign the scaffold key to the Scaffold
      drawer: AppDrawer(), // Add the navigation drawer to the scaffold
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        title: Text(
          localizations.dashboard, // Title for the Home Screen AppBar
          style: GoogleFonts.poppins(
            fontSize: responsive.fs20,
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
                      padding: responsive.padding(all: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
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
                    padding: responsive.padding(all: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localizations.welcomeBack,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs16,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              authProvider.user?.name ??
                                  'User', // Display user name or 'User' if null
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs24,
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
                  padding: responsive.padding(horizontal: 20),
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
                    ),
                    elevation: 8,
                    child: Container(
                      width: double.infinity,
                      padding: responsive.padding(all: 24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                        ),
                        borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    localizations.totalBalance,
                                    style: GoogleFonts.poppins(
                                      color: Colors.white.withOpacity(0.8),
                                      fontSize: responsive.fs16,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    authProvider.defaultCurrency.displayName,
                                    style: GoogleFonts.poppins(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: responsive.fs12,
                                    ),
                                  ),
                                ],
                              ),
                              Icon(
                                Icons.account_balance_wallet,
                                color: Colors.white,
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          // Primary Currency Balance
                          Text(
                            transactionProvider.balance != null
                                ? transactionProvider.balance!.displayBalance
                                : '${authProvider.defaultCurrency.symbol}0.00',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: responsive.fs32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '${localizations.available}: ${transactionProvider.balance != null ? '${transactionProvider.balance!.currency.symbol}${formatter.format(transactionProvider.balance!.availableBalance)}' : '${authProvider.defaultCurrency.symbol}0.00'}',
                            style: GoogleFonts.poppins(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: responsive.fs14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (transactionProvider.balance?.allocatedToGoals != null &&
                              transactionProvider.balance!.allocatedToGoals > 0) ...[
                            SizedBox(height: 2),
                            Text(
                              '${localizations.allocatedToGoals}: ${transactionProvider.balance!.currency.symbol}${formatter.format(transactionProvider.balance!.allocatedToGoals)}',
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: responsive.fs12,
                              ),
                            ),
                          ],
                          SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildBalanceInfo(
                                icon: Icons.arrow_upward,
                                label: localizations.inflow,
                                amount: transactionProvider.balance?.totalInflow ?? 0.0,
                                currency: transactionProvider.balance?.currency ?? authProvider.defaultCurrency,
                                color: Colors.green,
                              ),
                              Container(
                                height: 40,
                                width: 1,
                                color: Colors.white.withOpacity(0.3),
                              ),
                              _buildBalanceInfo(
                                icon: Icons.arrow_downward,
                                label: localizations.outflow,
                                amount: transactionProvider.balance?.totalOutflow ?? 0.0,
                                currency: transactionProvider.balance?.currency ?? authProvider.defaultCurrency,
                                color: Colors.red,
                              ),
                            ],
                          ),
                          
                          // Multi-Currency Expansion
                          SizedBox(height: 16),
                          GestureDetector(
                            onTap: () => _showMultiCurrencyBottomSheet(),
                            child: Container(
                              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.currency_exchange, color: Colors.white, size: responsive.icon18),
                                  SizedBox(width: responsive.sp8),
                                  Text(
                                    localizations.viewAllCurrencies,
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: responsive.fs13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(width: responsive.sp8),
                                  Icon(Icons.keyboard_arrow_down, color: Colors.white, size: responsive.icon18),
                                ],
                              ),
                            ),
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
                    padding: responsive.padding(horizontal: 20),
                    child: GestureDetector(
                      onTap: () => Navigator.pushNamed(context, '/ai-chat'),
                      child: Container(
                        width: double.infinity,
                        padding: responsive.padding(all: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
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
                              width: responsive.icon50,
                              height: responsive.icon50,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF667eea),
                                    Color(0xFF764ba2),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                              ),
                              child: Icon(
                                Icons.smart_toy,
                                color: Colors.white,
                                size: responsive.icon24,
                              ),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        localizations.aiAssistant,
                                        style: GoogleFonts.poppins(
                                          fontSize: responsive.fs16,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF333333),
                                        ),
                                      ),
                                      SizedBox(width: responsive.sp8),
                                      if (!authProvider.isPremium)
                                        Icon(Icons.lock, size: responsive.icon16, color: Color(0xFFFFD700)),
                                        SizedBox(width: responsive.sp8),
                                      if (!authProvider.isPremium)
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Color(0xFFFFD700).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Color(0xFFFFD700), width: 1),
                                          ),
                                          child: Text(
                                            localizations.premium,
                                            style: GoogleFonts.poppins(
                                              fontSize: responsive.fs10,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFFFD700),
                                            ),
                                          ),
                                        )
                                    ],
                                  ),
                                  Text(
                                    localizations.getPersonalizedInsights,
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
                              color: Colors.grey[400],
                              size: responsive.icon16,
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
                    padding: responsive.padding(horizontal: 20),
                    child: GestureDetector(
                      onTap: () => Navigator.pushNamed(context, '/insights'),
                      child: Container(
                        width: double.infinity,
                        padding: responsive.padding(all: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
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
                              width: responsive.icon50,
                              height: responsive.icon50,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFFFFB74D),
                                    Color(0xFFFF9800),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                              ),
                              child: Icon(
                                Icons.lightbulb,
                                color: Colors.white,
                                size: responsive.icon24,
                              ),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        localizations.aiInsights,
                                        style: GoogleFonts.poppins(
                                          fontSize: responsive.fs16,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF333333),
                                        ),
                                      ),
                                      SizedBox(width: responsive.sp8),
                                      if (!authProvider.isPremium)
                                        Icon(Icons.lock, size: responsive.icon16, color: Color(0xFFFFD700)),
                                        SizedBox(width: responsive.sp8),
                                      if (!authProvider.isPremium)
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Color(0xFFFFD700).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Color(0xFFFFD700), width: 1),
                                          ),
                                          child: Text(
                                            localizations.premium,
                                            style: GoogleFonts.poppins(
                                              fontSize: responsive.fs10,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFFFD700),
                                            ),
                                          ),
                                        )
                                    ],
                                  ),
                                  Text(
                                    localizations.viewComprehensiveAnalysis,
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
                              color: Colors.grey[400],
                              size: responsive.icon16,
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
                    padding: responsive.padding(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          localizations.recentTransactions,
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF333333),
                          ),
                        ),
                        // "See More" Text Button
                        GestureDetector(
                          onTap:
                              _navigateToTransactionsList, // Navigate to the full list
                          child: Text(
                            localizations.seeMore,
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs14,
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
                              size: responsive.icon64,
                              color: Colors.grey[300],
                            ),
                            SizedBox(height: 16),
                            Text(
                              localizations.noTransactions,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs18,
                                color: Colors.grey[500],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              localizations.tapToAddFirst,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs14,
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
        child: Icon(Icons.add, color: Colors.white, size: responsive.icon28),
        elevation: 8,
        tooltip: localizations.addTransactionFabTooltip,
      ),
    );
  }

  // Helper widget to display balance information (Inflow/Outflow)
  Widget _buildBalanceInfo({
  required IconData icon,
  required String label,
  required double amount,
  required Currency currency,
  required Color color,
}) {
  final responsive = ResponsiveHelper(context);

  return Column(
    children: [
      Row(
        children: [
          Icon(icon, color: Colors.white, size: responsive.icon16),
          SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white.withOpacity(0.8),
              fontSize: responsive.fs12,
            ),
          ),
        ],
      ),
      Text(
        '${currency.symbol}${formatter.format(amount)}', // Changed from toStringAsFixed(2)
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: responsive.fs18,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );
}

// ADD this new method to show multi-currency bottom sheet
void _showMultiCurrencyBottomSheet() async {
  final localizations = AppLocalizations.of(context);
  final responsive = ResponsiveHelper(context);
  
  // Fetch all balances
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
      ),
    ),
  );
  
  try {
    final multiBalances = await ApiService.getAllBalances();
    Navigator.pop(context); // Close loading dialog
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: responsive.padding(all: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: responsive.padding(all: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                    ),
                    borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                  ),
                  child: Icon(Icons.currency_exchange, color: Colors.white, size: responsive.icon20),
                ),
                SizedBox(width: 12),
                Text(
                  localizations.allCurrencyBalances,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF333333),
                  ),
                ),
              ],
            ),
            SizedBox(height: 24),
            
            // Display all currency balances
            ...multiBalances.currencies.map((currency) {
              final balance = multiBalances.getBalanceForCurrency(currency);
              if (balance == null) return SizedBox.shrink();
              
              return Container(
                margin: responsive.padding(bottom: 16),
                padding: responsive.padding(all: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF667eea).withOpacity(0.1), Color(0xFF764ba2).withOpacity(0.1)],
                  ),
                  borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
                  border: Border.all(
                    color: Color(0xFF667eea).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: responsive.padding(all: 8),
                              decoration: BoxDecoration(
                                color: Color(0xFF667eea),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                currency.symbol,
                                style: GoogleFonts.poppins(
                                  fontSize: responsive.fs18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              currency.displayName,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF333333),
                              ),
                            ),
                          ],
                        ),
                        if (currency == Provider.of<AuthProvider>(context, listen: false).defaultCurrency)
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Color(0xFF4CAF50),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              localizations.defaultBalance,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 16),
                    Text(
                      balance.displayBalance,
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF333333),
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localizations.available,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs12,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              '${currency.symbol}${formatter.format(balance.availableBalance)}',
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF333333),
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              localizations.allocatedToGoals,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs12,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              '${currency.symbol}${formatter.format(balance.allocatedToGoals)}',
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFF9800),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Divider(),
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.arrow_upward, size: responsive.icon16, color: Colors.green),
                            SizedBox(width: 4),
                            Text(
                              '${currency.symbol}${formatter.format(balance.totalInflow)}',
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs13,
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Icon(Icons.arrow_downward, size: responsive.icon16, color: Colors.red),
                            SizedBox(width: 4),
                            Text(
                              '${currency.symbol}${formatter.format(balance.totalOutflow)}',
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs13,
                                color: Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
            
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  } catch (e) {
    Navigator.pop(context); // Close loading dialog
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Failed to load currency balances: ${e.toString().replaceAll('Exception: ', '')}',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

  // Widget to build a card for each transaction (consistent with TransactionsListScreen)
  Widget _buildTransactionCard(Transaction transaction) {
    final localizations = AppLocalizations.of(context);
    final responsive = ResponsiveHelper(context);

    return GestureDetector(
      onTap: () => _navigateToEditTransaction(
        transaction,
      ), // Navigate to edit screen on tap
      child: Container(
        margin: EdgeInsets.only(bottom: 8),
        padding: responsive.padding(all: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
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
              width: responsive.icon48,
              height: responsive.icon48,
              decoration: BoxDecoration(
                color: transaction.type == TransactionType.inflow
                    ? Color(0xFF4CAF50).withOpacity(0.1) // Light green
                    : Color(0xFFFF5722).withOpacity(0.1), // Light red
                borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
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
                          size: responsive.icon16,
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
                          size: responsive.icon16,
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
                    transaction.mainCategory, // Display main category
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs12,
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
                        fontSize: responsive.fs12,
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
                  '${transaction.type == TransactionType.inflow ? '+' : '-'}${transaction.currency.symbol}${formatter.format(transaction.amount)}',
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs16,
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
                    fontSize: responsive.fs12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
            SizedBox(width: responsive.sp8),
            Icon(
              // Arrow icon to indicate tappable card
              Icons.arrow_forward_ios,
              size: responsive.icon16,
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
                    borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
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
                  _showSuccessSnackBar(localizations.transactionAdded);
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
                  _showSuccessSnackBar(localizations.transactionAdded);// Show success message...
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
                  _showSuccessSnackBar(localizations.transactionAdded);
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
    borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
    child: Container(
      padding: responsive.padding(all: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
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
                  borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
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
                      size: responsive.fs12,
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
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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


void _showSuccessSnackBar(String message) {
  final localizations = AppLocalizations.of(context);
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
    final localizations = AppLocalizations.of(context);
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
            localizations.transactionUpdated,
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: Color(0xFF4CAF50),
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
            localizations.transactionDeleted,
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Show logout confirmation dialog
  void _showLogoutDialog(BuildContext context) {
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
          ),
          title: Text(
            localizations.drawerLogout,
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: Text(
            localizations.dialogLogoutConfirm,
            style: GoogleFonts.poppins(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), // Close dialog
              child: Text(
                localizations.dialogCancel,
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
                localizations.drawerLogout,
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }
}