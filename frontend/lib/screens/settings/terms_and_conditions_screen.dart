import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/services/responsive_helper.dart';

class TermsAndConditionsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final responsive = ResponsiveHelper(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Terms and Conditions',
          style: GoogleFonts.poppins(
            fontSize: responsive.fs20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Color(0xFF333333)),
          onPressed: () => Navigator.pop(context),
        ),
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
        child: SingleChildScrollView(
          padding: responsive.padding(all: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Container(
                padding: responsive.padding(all: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                  ),
                  borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF667eea).withOpacity(0.3),
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
                        Icons.description,
                        color: Colors.white,
                        size: responsive.icon28,
                      ),
                    ),
                    SizedBox(width: responsive.sp16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Terms and Conditions',
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: responsive.sp4),
                          Text(
                            'Last updated: January 2025',
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

              SizedBox(height: responsive.sp24),

              // Content Sections
              _buildSection(
                context,
                title: '1. Acceptance of Terms',
                content: 'By accessing and using Flow Finance ("the App"), you accept and agree to be bound by these Terms and Conditions. If you do not agree to these terms, please do not use the App.',
              ),

              _buildSection(
                context,
                title: '2. Use of Service',
                content: 'Flow Finance provides personal finance management tools, including:\n\n'
                    '• Transaction tracking and categorization\n'
                    '• AI-powered financial insights and recommendations\n'
                    '• Budget management and goal tracking\n'
                    '• Financial reports and analytics\n\n'
                    'You agree to use the App for personal financial management purposes only.',
              ),

              _buildSection(
                context,
                title: '3. Account Registration',
                content: 'You must provide accurate and complete information when creating an account. You are responsible for:\n\n'
                    '• Maintaining the confidentiality of your account credentials\n'
                    '• All activities that occur under your account\n'
                    '• Notifying us immediately of any unauthorized use',
              ),

              _buildSection(
                context,
                title: '4. User Responsibilities',
                content: 'You agree to:\n\n'
                    '• Provide accurate financial information\n'
                    '• Not misuse AI features or attempt to manipulate the system\n'
                    '• Not use the App for any illegal purposes\n'
                    '• Not share your account with others\n'
                    '• Comply with all applicable laws and regulations',
              ),

              _buildSection(
                context,
                title: '5. AI-Powered Features',
                content: 'Our AI features provide suggestions and insights based on your financial data. Please note:\n\n'
                    '• AI insights are suggestions, not professional financial advice\n'
                    '• You should verify all recommendations before taking action\n'
                    '• We are not liable for decisions made based on AI suggestions\n'
                    '• Results may vary based on your financial situation',
              ),

              _buildSection(
                context,
                title: '6. Premium Subscription',
                content: 'Premium features require an active subscription:\n\n'
                    '• Subscriptions are billed according to your chosen plan\n'
                    '• You can cancel at any time before the next billing cycle\n'
                    '• Refunds are provided according to our refund policy\n'
                    '• Access to premium features ends when subscription expires',
              ),

              _buildSection(
                context,
                title: '7. Data Processing',
                content: 'We process your financial data to:\n\n'
                    '• Provide personalized insights and recommendations\n'
                    '• Improve our services and AI algorithms\n'
                    '• Generate reports and analytics\n'
                    '• Ensure security and prevent fraud\n\n'
                    'All data processing complies with our Privacy Policy.',
              ),

              _buildSection(
                context,
                title: '8. Intellectual Property',
                content: 'All content, features, and functionality of the App are owned by Flow Finance and protected by copyright, trademark, and other laws. You may not:\n\n'
                    '• Copy, modify, or distribute our content\n'
                    '• Reverse engineer or attempt to extract source code\n'
                    '• Use our trademarks without permission',
              ),

              _buildSection(
                context,
                title: '9. Limitation of Liability',
                content: 'Flow Finance is provided "as is" without warranties. We are not liable for:\n\n'
                    '• Financial decisions made using the App\n'
                    '• Loss of data or service interruptions\n'
                    '• Indirect or consequential damages\n'
                    '• Third-party actions or content',
              ),

              _buildSection(
                context,
                title: '10. Termination',
                content: 'We reserve the right to:\n\n'
                    '• Suspend or terminate your account for violations\n'
                    '• Modify or discontinue services at any time\n'
                    '• Remove content that violates these terms\n\n'
                    'You may delete your account at any time from the app settings.',
              ),

              _buildSection(
                context,
                title: '11. Changes to Terms',
                content: 'We may update these Terms and Conditions periodically. Continued use of the App after changes constitutes acceptance of the new terms. We will notify users of significant changes.',
              ),

              _buildSection(
                context,
                title: '12. Contact Information',
                content: 'For questions about these Terms and Conditions, please contact us at:\n\n'
                    'Email: support@flowfinance.com\n'
                    'Website: www.flowfinance.com',
              ),

              SizedBox(height: responsive.sp32),

              // Acceptance Notice
              Container(
                padding: responsive.padding(all: 16),
                decoration: BoxDecoration(
                  color: Color(0xFF4CAF50).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                  border: Border.all(
                    color: Color(0xFF4CAF50).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: Color(0xFF4CAF50),
                      size: responsive.icon24,
                    ),
                    SizedBox(width: responsive.sp12),
                    Expanded(
                      child: Text(
                        'By using Flow Finance, you agree to these Terms and Conditions',
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs13,
                          color: Color(0xFF4CAF50),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: responsive.sp32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, {
    required String title,
    required String content,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: responsive.fs16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF333333),
            ),
          ),
          SizedBox(height: responsive.sp12),
          Text(
            content,
            style: GoogleFonts.poppins(
              fontSize: responsive.fs14,
              color: Colors.grey[700],
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}