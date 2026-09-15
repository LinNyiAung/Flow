import 'package:flutter/material.dart';

class TermsAndConditionsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Terms and Conditions')),
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
                  Icon(Icons.description_rounded, color: scheme.onPrimaryContainer, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Terms and Conditions',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Last updated: January 2025',
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
              title: '1. Acceptance of Terms',
              content: 'By accessing and using Toe Pwar ("the App"), you accept and agree to be bound by these Terms and Conditions. If you do not agree to these terms, please do not use the App.',
            ),

            _buildSection(
              scheme: scheme,
              title: '2. Use of Service',
              content: 'Toe Pwar provides personal finance management tools, including:\n\n'
                  '• Transaction tracking and categorization\n'
                  '• AI-powered financial insights and recommendations\n'
                  '• Budget management and goal tracking\n'
                  '• Financial reports and analytics\n\n'
                  'You agree to use the App for personal financial management purposes only.',
            ),

            _buildSection(
              scheme: scheme,
              title: '3. Account Registration',
              content: 'You must provide accurate and complete information when creating an account. You are responsible for:\n\n'
                  '• Maintaining the confidentiality of your account credentials\n'
                  '• All activities that occur under your account\n'
                  '• Notifying us immediately of any unauthorized use',
            ),

            _buildSection(
              scheme: scheme,
              title: '4. User Responsibilities',
              content: 'You agree to:\n\n'
                  '• Provide accurate financial information\n'
                  '• Not misuse AI features or attempt to manipulate the system\n'
                  '• Not use the App for any illegal purposes\n'
                  '• Not share your account with others\n'
                  '• Comply with all applicable laws and regulations',
            ),

            _buildSection(
              scheme: scheme,
              title: '5. AI-Powered Features',
              content: 'Our AI features provide suggestions and insights based on your financial data. Please note:\n\n'
                  '• AI insights are suggestions, not professional financial advice\n'
                  '• You should verify all recommendations before taking action\n'
                  '• We are not liable for decisions made based on AI suggestions\n'
                  '• Results may vary based on your financial situation',
            ),

            _buildSection(
              scheme: scheme,
              title: '6. Premium Subscription',
              content: 'Premium features require an active subscription:\n\n'
                  '• Subscriptions are billed according to your chosen plan\n'
                  '• You can cancel at any time before the next billing cycle\n'
                  '• Refunds are provided according to our refund policy\n'
                  '• Access to premium features ends when subscription expires',
            ),

            _buildSection(
              scheme: scheme,
              title: '7. Data Processing',
              content: 'We process your financial data to:\n\n'
                  '• Provide personalized insights and recommendations\n'
                  '• Improve our services and AI algorithms\n'
                  '• Generate reports and analytics\n'
                  '• Ensure security and prevent fraud\n\n'
                  'All data processing complies with our Privacy Policy.',
            ),

            _buildSection(
              scheme: scheme,
              title: '8. Intellectual Property',
              content: 'All content, features, and functionality of the App are owned by Toe Pwar and protected by copyright, trademark, and other laws. You may not:\n\n'
                  '• Copy, modify, or distribute our content\n'
                  '• Reverse engineer or attempt to extract source code\n'
                  '• Use our trademarks without permission',
            ),

            _buildSection(
              scheme: scheme,
              title: '9. Limitation of Liability',
              content: 'Toe Pwar is provided "as is" without warranties. We are not liable for:\n\n'
                  '• Financial decisions made using the App\n'
                  '• Loss of data or service interruptions\n'
                  '• Indirect or consequential damages\n'
                  '• Third-party actions or content',
            ),

            _buildSection(
              scheme: scheme,
              title: '10. Termination',
              content: 'We reserve the right to:\n\n'
                  '• Suspend or terminate your account for violations\n'
                  '• Modify or discontinue services at any time\n'
                  '• Remove content that violates these terms\n\n'
                  'You may delete your account at any time from the app settings.',
            ),

            _buildSection(
              scheme: scheme,
              title: '11. Changes to Terms',
              content: 'We may update these Terms and Conditions periodically. Continued use of the App after changes constitutes acceptance of the new terms. We will notify users of significant changes.',
            ),

            _buildSection(
              scheme: scheme,
              title: '12. Contact Information',
              content: 'For questions about these Terms and Conditions, please contact us at:\n\n'
                  'Email: toepwarai@gmail.com\n'
                  'Website: www.toepwar.com',
            ),

            const SizedBox(height: 12),

            // Acceptance Notice
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, color: scheme.primary, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'By using Toe Pwar, you agree to these Terms and Conditions',
                      style: TextStyle(fontSize: 13, color: scheme.primary, fontWeight: FontWeight.w600),
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
