import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/notification_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../providers/insight_provider.dart';
import '../../widgets/app_drawer.dart';
import 'package:frontend/services/responsive_helper.dart';

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
  final responsive = ResponsiveHelper(context);
  
  // Show loading dialog
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return Center(
        child: Container(
          padding: responsive.padding(all: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
              ),
              SizedBox(height: responsive.sp16),
              Text(
                'Generating insights...',
                style: GoogleFonts.poppins(
                  fontSize: responsive.fs16,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(8))),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(8))),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

  @override
  Widget build(BuildContext context) {
    final insightProvider = Provider.of<InsightProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final responsive = ResponsiveHelper(context);

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
                fontSize: responsive.fs20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333),
              ),
            ),
            SizedBox(width: responsive.sp8),
            if (!authProvider.isPremium)
              Icon(Icons.lock, size: responsive.icon16, color: Color(0xFFFFD700)),
              SizedBox(width: responsive.sp8),
            if (!authProvider.isPremium)
              Container(
                padding: responsive.padding(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Color(0xFFFFD700).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
                  border: Border.all(color: Color(0xFFFFD700), width: 1),
                ),
                child: Text(
                  'PREMIUM',
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs10,
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
          //       padding: responsive.padding(all: 8),
          //       decoration: BoxDecoration(
          //         color: Colors.white,
          //         borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
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
            padding: responsive.padding(right: 16),
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
                          padding: responsive.padding(all: 4),
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
    final responsive = ResponsiveHelper(context);
  return Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(Icons.check_circle, color: Colors.white, size: responsive.icon20),
        SizedBox(width: responsive.sp12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: responsive.fs14,
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
    final responsive = ResponsiveHelper(context);
      if (!Provider.of<AuthProvider>(context).isPremium) {
    return SingleChildScrollView(
      child: Padding(
        padding: responsive.padding(all: 20),
        child: Column(
          children: [
            SizedBox(height: responsive.sp20),
            Container(
              width: double.infinity,
              padding: responsive.padding(all: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ),
                borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
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
                  Icon(Icons.lightbulb, color: Colors.white, size: responsive.icon64),
                  SizedBox(height: responsive.sp16),
                  Text(
                    'AI Insights',
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: responsive.sp8),
                  Text(
                    'Premium Feature',
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  SizedBox(height: responsive.sp24),
                  Container(
                    padding: responsive.padding(all: 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
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
                  SizedBox(height: responsive.sp24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pushNamed(context, '/subscription'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Color(0xFFFFD700),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
                        ),
                        elevation: 4,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.upgrade, size: responsive.icon24),
                          SizedBox(width: responsive.sp12),
                          Text(
                            'Upgrade to Premium',
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs18,
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
            SizedBox(height: responsive.sp24),
            Text(
              'Analyzing your financial data...',
              style: GoogleFonts.poppins(
                fontSize: responsive.fs16,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: responsive.sp8),
            Text(
              'This may take a few seconds',
              style: GoogleFonts.poppins(
                fontSize: responsive.fs14,
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
          padding: responsive.padding(all: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: responsive.padding(all: 24),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
                ),
                child: Icon(
                  Icons.error_outline,
                  size: responsive.icon48,
                  color: Colors.red,
                ),
              ),
              SizedBox(height: responsive.sp24),
              Text(
                'Failed to load insights',
                style: GoogleFonts.poppins(
                  fontSize: responsive.fs18,
                  color: Color(0xFF333333),
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: responsive.sp8),
              Text(
                insightProvider.error!,
                style: GoogleFonts.poppins(
                  fontSize: responsive.fs14,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: responsive.sp24),
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
                    borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
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
                  Icons.lightbulb_outline,
                  size: responsive.icon48,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: responsive.sp24),
              Text(
                'No insights available',
                style: GoogleFonts.poppins(
                  fontSize: responsive.fs18,
                  color: Color(0xFF333333),
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: responsive.sp8),
              Text(
                'Add transactions and goals to generate insights',
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

    // Display insights
    return ListView(
      padding: responsive.padding(all: 20),
      children: [
        // Info Card
        Container(
          padding: responsive.padding(all: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
            ),
            borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
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
                padding: responsive.padding(all: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: responsive.icon28,
                ),
              ),
              SizedBox(width: responsive.sp16),
              Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  flex: 5,
                  child: Text(
                    'AI-Generated Insights',
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                SizedBox(width: responsive.sp8),
                // Language badge
                Flexible(
                  flex: 2,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
                    ),
                    child: Text(
                      insightProvider.currentLanguage == 'mm' ? 'မြန်မာ' : 'English',
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Text(
              'Generated ${DateFormat('MMM dd, yyyy â€¢ hh:mm a').format(insightProvider.insight!.generatedAt)}',
              style: GoogleFonts.poppins(
                fontSize: responsive.fs12,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    ],
  ),
),

        SizedBox(height: responsive.sp20),

        // Insights Content
        Container(
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
          child: MarkdownBody(
            // Use the provider method to get content in current language
            data: insightProvider.getContentForLanguage() ?? insightProvider.insight!.content,
            styleSheet: MarkdownStyleSheet(
              h1: GoogleFonts.poppins(
                fontSize: responsive.fs24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333),
              ),
              h2: GoogleFonts.poppins(
                fontSize: responsive.fs20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF667eea),
              ),
              h3: GoogleFonts.poppins(
                fontSize: responsive.fs18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333),
              ),
              p: GoogleFonts.poppins(
                fontSize: responsive.fs14,
                color: Color(0xFF333333),
                height: 1.6,
              ),
              strong: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: Color(0xFF667eea),
              ),
              listBullet: GoogleFonts.poppins(
                fontSize: responsive.fs14,
                color: Color(0xFF667eea),
              ),
            ),
          ),
        ),
        

        SizedBox(height: responsive.sp20),

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
        //         fontSize: responsive.fs16,
        //       ),
        //     ),
        //     style: ElevatedButton.styleFrom(
        //       backgroundColor: Color(0xFF667eea),
        //       padding: responsive.padding(vertical: 16),
        //       shape: RoundedRectangleBorder(
        //         borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
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