import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:frontend/services/responsive_helper.dart';

import '../../services/localization_service.dart';

class SubscriptionScreen extends StatefulWidget {
  @override
  _SubscriptionScreenState createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {

  @override
  Widget build(BuildContext context) {
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);
    
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
                    padding: responsive.padding(all: 20),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Container(
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
                            child: Icon(Icons.arrow_back, color: Color(0xFF333333)),
                          ),
                        ),
                        SizedBox(width: responsive.sp16),
                        Text(
                          isPremium ? localizations.premiumStatus : localizations.upgradeToPremium,
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF333333),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: responsive.padding(all: 20),
                      child: Column(
                        children: [
                          // Current Status Card (if premium)
                          if (isPremium) ...[
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
                                  Icon(Icons.star, color: Colors.white, size: responsive.iconSize(mobile: 48)),
                                  SizedBox(height: responsive.sp16),
                                  Text(
                                    localizations.premiumActive,
                                    style: GoogleFonts.poppins(
                                      fontSize: responsive.fs24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (authProvider.subscriptionExpiresAt != null) ...[
                                    SizedBox(height: 8),
                                    Text(
                                      'Expires: ${DateFormat('MMM dd, yyyy').format(authProvider.subscriptionExpiresAt!)}',
                                      style: GoogleFonts.poppins(
                                        fontSize: responsive.fs14,
                                        color: Colors.white.withOpacity(0.9),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            SizedBox(height: responsive.sp32),
                          ],

                          // Premium Features List
                          Text(
                            localizations.premiumFeatures,
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF333333),
                            ),
                          ),
                          SizedBox(height: responsive.sp20),

                          _buildFeatureCard(
                            icon: Icons.auto_awesome,
                            title: localizations.aiBudgetSuggestions,
                            description: localizations.aiBudgetSuggestionsDes,
                            gradient: [Color(0xFF667eea), Color(0xFF764ba2)],
                          ),
                          _buildFeatureCard(
                            icon: Icons.mic,
                            title: localizations.voiceInput,
                            description: localizations.voiceInputDes,
                            gradient: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                          ),
                          _buildFeatureCard(
                            icon: Icons.photo_camera,
                            title: localizations.receiptScanning,
                            description: localizations.receiptScanningDes,
                            gradient: [Color(0xFFFF9800), Color(0xFFF57C00)],
                          ),
                          _buildFeatureCard(
                            icon: Icons.smart_toy,
                            title: localizations.aiFinancialAssistant,
                            description: localizations.aiFinancialAssistantDes,
                            gradient: [Color(0xFF2196F3), Color(0xFF1976D2)],
                          ),
                          _buildFeatureCard(
                            icon: Icons.lightbulb,
                            title: localizations.aiInsights,
                            description: localizations.aiInsightsDes,
                            gradient: [Color(0xFFFFB74D), Color(0xFFFF9800)],
                          ),

                          SizedBox(height: responsive.sp32),

                          // Contact Admin / Info Card (if not premium)
                          if (!isPremium) ...[
                            Container(
                              width: double.infinity,
                              padding: responsive.padding(all: 24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.3),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.05),
                                    spreadRadius: 2,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    localizations.premiumPlan,
                                    style: GoogleFonts.poppins(
                                      fontSize: responsive.fs24,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF333333),
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  // Optional: Keep price visible or remove if irrelevant
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '\$',
                                        style: GoogleFonts.poppins(
                                          fontSize: responsive.fs24,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFFFD700),
                                        ),
                                      ),
                                      Text(
                                        '9.99',
                                        style: GoogleFonts.poppins(
                                          fontSize: responsive.iconSize(mobile: 48),
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFFFD700),
                                        ),
                                      ),
                                      Padding(
                                        padding: responsive.padding(top: 20),
                                        child: Text(
                                          '/month',
                                          style: GoogleFonts.poppins(
                                            fontSize: responsive.fs16,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: responsive.sp24),
                                  
                                  // REPLACED BUTTON WITH CONTACT INFO
                                  Container(
                                    width: double.infinity,
                                    padding: EdgeInsets.symmetric(
                                      vertical: responsive.sp16,
                                      horizontal: responsive.sp20
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
                                      border: Border.all(color: Colors.grey[300]!),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(Icons.lock_outline, color: Colors.grey[600], size: 28),
                                        SizedBox(height: 8),
                                        Text(
                                          localizations.contactAdmin,
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.poppins(
                                            fontSize: responsive.fs16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey[800],
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          localizations.contactSupport,
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.poppins(
                                            fontSize: responsive.fs12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
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
    final responsive = ResponsiveHelper(context);
    return Container(
      margin: responsive.padding(bottom: 16),
      padding: responsive.padding(all: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
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
            padding: responsive.padding(all: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
            ),
            child: Icon(icon, color: Colors.white, size: responsive.icon24),
          ),
          SizedBox(width: responsive.sp16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                SizedBox(height: responsive.sp4),
                Text(
                  description,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs13,
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