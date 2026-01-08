import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/services/responsive_helper.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final responsive = ResponsiveHelper(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Privacy Policy',
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
                    colors: [Color(0xFF9C27B0), Color(0xFF7B1FA2)],
                  ),
                  borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF9C27B0).withOpacity(0.3),
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
                        Icons.privacy_tip,
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
                            'Privacy Policy',
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: responsive.sp4),
                          Text(
                            'Your privacy matters to us',
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
                title: '1. Introduction',
                content: 'Flow Finance ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application.',
              ),

              _buildSection(
                context,
                title: '2. Information We Collect',
                content: 'We collect several types of information:\n\n'
                    'Personal Information:\n'
                    '• Name and email address\n'
                    '• Account credentials\n'
                    '• Profile information\n\n'
                    'Financial Data:\n'
                    '• Transaction details (amount, category, date)\n'
                    '• Budget information\n'
                    '• Financial goals\n'
                    '• Account balances\n\n'
                    'Usage Information:\n'
                    '• App usage patterns\n'
                    '• Feature interactions\n'
                    '• Device information',
              ),

              _buildSection(
                context,
                title: '3. How We Use Your Information',
                content: 'We use your information to:\n\n'
                    '• Provide and maintain our services\n'
                    '• Generate personalized financial insights using AI\n'
                    '• Create budget recommendations\n'
                    '• Send notifications about your finances\n'
                    '• Improve our app and AI algorithms\n'
                    '• Ensure security and prevent fraud\n'
                    '• Communicate with you about updates and features',
              ),

              _buildSection(
                context,
                title: '4. Data Security',
                content: 'We implement industry-standard security measures:\n\n'
                    '• Encryption of sensitive data in transit and at rest\n'
                    '• Secure authentication mechanisms\n'
                    '• Regular security audits\n'
                    '• Access controls and monitoring\n'
                    '• Secure data storage practices\n\n'
                    'However, no method of transmission over the internet is 100% secure. We cannot guarantee absolute security.',
              ),

              _buildSection(
                context,
                title: '5. Data Sharing',
                content: 'We do not sell your personal information. We may share data only in these limited circumstances:\n\n'
                    '• With your explicit consent\n'
                    '• To comply with legal obligations\n'
                    '• To protect our rights and prevent fraud\n'
                    '• With service providers who assist our operations (under strict confidentiality agreements)\n\n'
                    'Third-party service providers are contractually obligated to protect your data.',
              ),

              _buildSection(
                context,
                title: '6. AI and Data Processing',
                content: 'Our AI features process your financial data to:\n\n'
                    '• Analyze spending patterns\n'
                    '• Generate personalized insights\n'
                    '• Provide budget recommendations\n'
                    '• Predict future trends\n\n'
                    'All AI processing is done with your data privacy in mind. We use aggregated and anonymized data to improve our AI models.',
              ),

              _buildSection(
                context,
                title: '7. Your Rights',
                content: 'You have the right to:\n\n'
                    '• Access your personal information\n'
                    '• Correct inaccurate data\n'
                    '• Delete your account and data\n'
                    '• Export your data\n'
                    '• Opt-out of certain data processing\n'
                    '• Withdraw consent at any time\n\n'
                    'To exercise these rights, contact us or use the app settings.',
              ),

              _buildSection(
                context,
                title: '8. Data Retention',
                content: 'We retain your information for as long as:\n\n'
                    '• Your account is active\n'
                    '• Necessary to provide services\n'
                    '• Required by law\n\n'
                    'When you delete your account, we will permanently delete your data within 30 days, except where required by law to retain it.',
              ),

              _buildSection(
                context,
                title: '9. Children\'s Privacy',
                content: 'Flow Finance is not intended for users under 18 years of age. We do not knowingly collect information from children. If you believe we have collected information from a child, please contact us immediately.',
              ),

              _buildSection(
                context,
                title: '10. International Data Transfers',
                content: 'Your information may be transferred to and processed in countries other than your own. We ensure appropriate safeguards are in place to protect your data in accordance with this Privacy Policy.',
              ),

              _buildSection(
                context,
                title: '11. Changes to Privacy Policy',
                content: 'We may update this Privacy Policy periodically. We will notify you of significant changes through the app or email. Your continued use after changes indicates acceptance of the updated policy.',
              ),

              _buildSection(
                context,
                title: '12. Contact Us',
                content: 'If you have questions about this Privacy Policy or our data practices:\n\n'
                    'Email: privacy@flowfinance.com\n'
                    'Website: www.flowfinance.com\n\n'
                    'We will respond to your inquiry within 30 days.',
              ),

              SizedBox(height: responsive.sp32),

              // Security Notice
              Container(
                padding: responsive.padding(all: 16),
                decoration: BoxDecoration(
                  color: Color(0xFF2196F3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                  border: Border.all(
                    color: Color(0xFF2196F3).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.security,
                      color: Color(0xFF2196F3),
                      size: responsive.icon24,
                    ),
                    SizedBox(width: responsive.sp12),
                    Expanded(
                      child: Text(
                        'Your data is encrypted and protected with industry-standard security measures',
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs13,
                          color: Color(0xFF2196F3),
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