import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../providers/insight_provider.dart';
import '../../widgets/app_drawer.dart';

class InsightsScreen extends StatefulWidget {
  @override
  _InsightsScreenState createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchInsights();
    });
  }


  Future<void> _fetchInsights() async {
  final locale = Localizations.localeOf(context);
  final language = locale.languageCode == 'my' ? 'mm' : 'en';
  
  await Provider.of<InsightProvider>(context, listen: false)
      .fetchInsights(language: language);
}


  Future<void> _regenerateInsights() async {
  final insightProvider = Provider.of<InsightProvider>(context, listen: false);
  final locale = Localizations.localeOf(context);
  final language = locale.languageCode == 'my' ? 'mm' : 'en';
  
  // Show loading dialog
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return Center(
        child: Container(
          padding: EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
              ),
              SizedBox(height: 16),
              Text(
                'Generating insights...',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  final success = await insightProvider.regenerateInsights(language: language);
  
  Navigator.pop(context); // Close loading dialog

  if (success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Insights regenerated successfully!',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        backgroundColor: Color(0xFF4CAF50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          insightProvider.error ?? 'Failed to regenerate insights',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        backgroundColor: Colors.red,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

  @override
  Widget build(BuildContext context) {
    final insightProvider = Provider.of<InsightProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      drawerEnableOpenDragGesture: true,  
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              'AI Insights',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333),
              ),
            ),
            SizedBox(width: 8),
            if (!authProvider.isPremium)
              Icon(Icons.lock, size: 16, color: Color(0xFFFFD700)),
              SizedBox(width: 8),
            if (!authProvider.isPremium)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Color(0xFFFFD700).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Color(0xFFFFD700), width: 1),
                ),
                child: Text(
                  'PREMIUM',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFD700),
                  ),
                ),
              )
          ],
        ),
        leading: IconButton(
          icon: Icon(Icons.menu),
          color: Color(0xFF333333),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          // Regenerate button
          // if (insightProvider.insight != null && !insightProvider.isLoading)
          //   IconButton(
          //     icon: Container(
          //       padding: EdgeInsets.all(8),
          //       decoration: BoxDecoration(
          //         color: Colors.white,
          //         borderRadius: BorderRadius.circular(12),
          //         boxShadow: [
          //           BoxShadow(
          //             color: Colors.grey.withOpacity(0.1),
          //             spreadRadius: 1,
          //             blurRadius: 4,
          //           ),
          //         ],
          //       ),
          //       child: Icon(
          //         Icons.refresh,
          //         color: Color(0xFF667eea),
          //       ),
          //     ),
          //     tooltip: 'Regenerate Insights',
          //     onPressed: _regenerateInsights,
          //   ),
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
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF667eea).withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _fetchInsights,
          color: Color(0xFF667eea),
          child: _buildBody(insightProvider),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String text) {
  return Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(Icons.check_circle, color: Colors.white, size: 20),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

  Widget _buildBody(InsightProvider insightProvider) {
      if (!Provider.of<AuthProvider>(context).isPremium) {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFFFFD700).withOpacity(0.3),
                    spreadRadius: 2,
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(Icons.lightbulb, color: Colors.white, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'AI Insights',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Premium Feature',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  SizedBox(height: 24),
                  Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildFeatureItem('Deep spending analysis'),
                        _buildFeatureItem('Personalized recommendations'),
                        _buildFeatureItem('Financial health score'),
                        _buildFeatureItem('Savings opportunities'),
                        _buildFeatureItem('Budget optimization tips'),
                      ],
                    ),
                  ),
                  SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pushNamed(context, '/subscription'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Color(0xFFFFD700),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.upgrade, size: 24),
                          SizedBox(width: 12),
                          Text(
                            'Upgrade to Premium',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
    if (insightProvider.isLoading || insightProvider.insight == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
            ),
            SizedBox(height: 24),
            Text(
              'Analyzing your financial data...',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 8),
            Text(
              'This may take a few seconds',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    if (insightProvider.error != null && insightProvider.insight == null) {
      return Center(
        child: Container(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Colors.red,
                ),
              ),
              SizedBox(height: 24),
              Text(
                'Failed to load insights',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  color: Color(0xFF333333),
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                insightProvider.error!,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchInsights,
                icon: Icon(Icons.refresh, color: Colors.white),
                label: Text(
                  'Try Again',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF667eea),
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (insightProvider.insight == null) {
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
                  Icons.lightbulb_outline,
                  size: 48,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 24),
              Text(
                'No insights available',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  color: Color(0xFF333333),
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Add transactions and goals to generate insights',
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

    // Display insights
    return ListView(
      padding: EdgeInsets.all(20),
      children: [
        // Info Card
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.2),
                spreadRadius: 2,
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 28,
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
                  'AI-Generated Insights',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 8),
                // Language badge
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    insightProvider.currentLanguage == 'mm' ? 'မြန်မာ' : 'English',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              'Generated ${DateFormat('MMM dd, yyyy â€¢ hh:mm a').format(insightProvider.insight!.generatedAt)}',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    ],
  ),
),

        SizedBox(height: 20),

        // Insights Content
        Container(
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
          child: MarkdownBody(
            // Use the provider method to get content in current language
            data: insightProvider.getContentForLanguage() ?? insightProvider.insight!.content,
            styleSheet: MarkdownStyleSheet(
              h1: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333),
              ),
              h2: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF667eea),
              ),
              h3: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333),
              ),
              p: GoogleFonts.poppins(
                fontSize: 14,
                color: Color(0xFF333333),
                height: 1.6,
              ),
              strong: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: Color(0xFF667eea),
              ),
              listBullet: GoogleFonts.poppins(
                fontSize: 14,
                color: Color(0xFF667eea),
              ),
            ),
          ),
        ),
        

        SizedBox(height: 20),

        // Regenerate Button
        // SizedBox(
        //   width: double.infinity,
        //   child: ElevatedButton.icon(
        //     onPressed: insightProvider.isLoading ? null : _regenerateInsights,
        //     icon: Icon(Icons.refresh, color: Colors.white),
        //     label: Text(
        //       'Regenerate Insights',
        //       style: GoogleFonts.poppins(
        //         color: Colors.white,
        //         fontWeight: FontWeight.w600,
        //         fontSize: 16,
        //       ),
        //     ),
        //     style: ElevatedButton.styleFrom(
        //       backgroundColor: Color(0xFF667eea),
        //       padding: EdgeInsets.symmetric(vertical: 16),
        //       shape: RoundedRectangleBorder(
        //         borderRadius: BorderRadius.circular(12),
        //       ),
        //       elevation: 4,
        //     ),
        //   ),
        // ),
        //
        // SizedBox(height: 100),
      ],
    );
  }
}