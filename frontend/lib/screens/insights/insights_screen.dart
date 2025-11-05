import 'package:flutter/material.dart';
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
    await Provider.of<InsightProvider>(context, listen: false).fetchInsights();
  }

  Future<void> _regenerateInsights() async {
    final insightProvider = Provider.of<InsightProvider>(context, listen: false);
    
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

    final success = await insightProvider.regenerateInsights();
    
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

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      drawerEnableOpenDragGesture: true,  
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        title: Text(
          'AI Insights',
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

  Widget _buildBody(InsightProvider insightProvider) {
    if (insightProvider.isLoading && insightProvider.insight == null) {
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
                    Text(
                      'AI-Generated Insights',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Generated ${DateFormat('MMM dd, yyyy • hh:mm a').format(insightProvider.insight!.generatedAt)}',
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
            data: insightProvider.insight!.content,
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