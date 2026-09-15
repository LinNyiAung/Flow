import 'package:flutter/material.dart';
import 'package:frontend/theme/app_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.privacy_tip_rounded, color: scheme.onPrimaryContainer, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Privacy Policy',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your privacy matters to us · Last updated Jan 2025',
                          style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer.withValues(alpha: 0.85)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Content Sections
            _buildSection(
              scheme: scheme,
              title: '1. Introduction',
              content: 'Toe Pwar ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application.',
            ),

            _buildSection(
              scheme: scheme,
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
              scheme: scheme,
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
              scheme: scheme,
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
              scheme: scheme,
              title: '5. Data Sharing',
              content: 'We do not sell your personal information. We may share data only in these limited circumstances:\n\n'
                  '• With your explicit consent\n'
                  '• To comply with legal obligations\n'
                  '• To protect our rights and prevent fraud\n'
                  '• With service providers who assist our operations (under strict confidentiality agreements)\n\n'
                  'Third-party service providers are contractually obligated to protect your data.',
            ),

            _buildSection(
              scheme: scheme,
              title: '6. AI and Data Processing',
              content: 'Our AI features process your financial data to:\n\n'
                  '• Analyze spending patterns\n'
                  '• Generate personalized insights\n'
                  '• Provide budget recommendations\n'
                  '• Predict future trends\n\n'
                  'When you ask the assistant a question or generate a budget, the relevant records are sent for that request. All AI processing is done with your data privacy in mind — we use aggregated and anonymized data to improve our AI models, and your records are not used to train anything beyond that request.',
            ),

            _buildSection(
              scheme: scheme,
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
              scheme: scheme,
              title: '8. Data Retention',
              content: 'We retain your information for as long as:\n\n'
                  '• Your account is active\n'
                  '• Necessary to provide services\n'
                  '• Required by law\n\n'
                  'When you delete your account, we will permanently delete your data within 30 days, except where required by law to retain it.',
            ),

            _buildSection(
              scheme: scheme,
              title: '9. Children\'s Privacy',
              content: 'Toe Pwar is not intended for users under 18 years of age. We do not knowingly collect information from children. If you believe we have collected information from a child, please contact us immediately.',
            ),

            _buildSection(
              scheme: scheme,
              title: '10. International Data Transfers',
              content: 'Your information may be transferred to and processed in countries other than your own. We ensure appropriate safeguards are in place to protect your data in accordance with this Privacy Policy.',
            ),

            _buildSection(
              scheme: scheme,
              title: '11. Changes to Privacy Policy',
              content: 'We may update this Privacy Policy periodically. We will notify you of significant changes through the app or email. Your continued use after changes indicates acceptance of the updated policy.',
            ),

            _buildSection(
              scheme: scheme,
              title: '12. Contact Us',
              content: 'If you have questions about this Privacy Policy or our data practices:\n\n'
                  'Email: toepwarai@gmail.com\n'
                  'Website: www.toepwar.com\n\n'
                  'We will respond to your inquiry within 30 days.',
            ),

            const SizedBox(height: 12),

            // Security Notice
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.infoContainerFor(context),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.security_rounded, color: AppTheme.infoFor(context), size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your data is encrypted and protected with industry-standard security measures',
                      style: TextStyle(fontSize: 13, color: AppTheme.infoFor(context), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required ColorScheme scheme, required String title, required String content}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(
                content,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
