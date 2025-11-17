import 'package:flutter/material.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

class SubscriptionScreen extends StatefulWidget {
  @override
  _SubscriptionScreenState createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _isLoading = false;

  // Demo function to simulate premium upgrade
  // In production, this would integrate with a payment gateway
  Future<void> _upgradeToPremium() async {
    setState(() {
      _isLoading = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    // Set premium with 1 month expiration
    // In production, this would happen after successful payment
    final expiryDate = DateTime.now().add(Duration(days: 30));
    
    final success = await authProvider.updateSubscription(
      subscriptionType: SubscriptionType.premium,
      subscriptionExpiresAt: expiryDate,
    );

    setState(() {
      _isLoading = false;
    });

    if (success) {
      _showSuccessDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upgrade subscription'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.star, color: Colors.white, size: 48),
            ),
            SizedBox(height: 24),
            Text(
              'Welcome to Premium!',
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'You now have access to all premium features.',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF667eea),
              minimumSize: Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Get Started',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFD700).withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Consumer<AuthProvider>(
            builder: (context, authProvider, child) {
              final isPremium = authProvider.isPremium;
              
              return Column(
                children: [
                  // Header
                  Padding(
                    padding: EdgeInsets.all(20),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Container(
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
                            child: Icon(Icons.arrow_back, color: Color(0xFF333333)),
                          ),
                        ),
                        SizedBox(width: 16),
                        Text(
                          isPremium ? 'Premium Status' : 'Upgrade to Premium',
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF333333),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        children: [
                          // Current Status Card (if premium)
                          if (isPremium) ...[
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
                                  Icon(Icons.star, color: Colors.white, size: 48),
                                  SizedBox(height: 16),
                                  Text(
                                    'Premium Active',
                                    style: GoogleFonts.poppins(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (authProvider.subscriptionExpiresAt != null) ...[
                                    SizedBox(height: 8),
                                    Text(
                                      'Expires: ${DateFormat('MMM dd, yyyy').format(authProvider.subscriptionExpiresAt!)}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        color: Colors.white.withOpacity(0.9),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            SizedBox(height: 32),
                          ],

                          // Premium Features
                          Text(
                            'Premium Features',
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF333333),
                            ),
                          ),
                          SizedBox(height: 20),

                          _buildFeatureCard(
                            icon: Icons.auto_awesome,
                            title: 'AI Budget Suggestions',
                            description: 'Get smart budget recommendations based on your spending patterns',
                            gradient: [Color(0xFF667eea), Color(0xFF764ba2)],
                          ),
                          _buildFeatureCard(
                            icon: Icons.mic,
                            title: 'Voice Input',
                            description: 'Add transactions by simply speaking',
                            gradient: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                          ),
                          _buildFeatureCard(
                            icon: Icons.photo_camera,
                            title: 'Receipt Scanning',
                            description: 'Scan receipts and auto-extract transaction details',
                            gradient: [Color(0xFFFF9800), Color(0xFFF57C00)],
                          ),
                          _buildFeatureCard(
                            icon: Icons.smart_toy,
                            title: 'AI Financial Assistant',
                            description: 'Chat with AI for personalized financial advice',
                            gradient: [Color(0xFF2196F3), Color(0xFF1976D2)],
                          ),
                          _buildFeatureCard(
                            icon: Icons.lightbulb,
                            title: 'AI Insights',
                            description: 'Get deep insights into your spending habits',
                            gradient: [Color(0xFFFFB74D), Color(0xFFFF9800)],
                          ),
                          

                          SizedBox(height: 32),

                          // Pricing Card (if not premium)
                          if (!isPremium) ...[
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Color(0xFFFFD700),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.1),
                                    spreadRadius: 2,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'Premium Plan',
                                    style: GoogleFonts.poppins(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF333333),
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '\$',
                                        style: GoogleFonts.poppins(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFFFD700),
                                        ),
                                      ),
                                      Text(
                                        '9.99',
                                        style: GoogleFonts.poppins(
                                          fontSize: 48,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFFFD700),
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.only(top: 20),
                                        child: Text(
                                          '/month',
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 24),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 56,
                                    child: ElevatedButton(
                                      onPressed: _isLoading ? null : _upgradeToPremium,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Color(0xFFFFD700),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ),
                                      child: _isLoading
                                          ? CircularProgressIndicator(color: Colors.black)
                                          : Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.star, color: Colors.black),
                                                SizedBox(width: 8),
                                                Text(
                                                  'Upgrade Now',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'Try 30 days • Cancel anytime',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required List<Color> gradient,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
              gradient: LinearGradient(colors: gradient),
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
                SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}