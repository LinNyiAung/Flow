import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // After a successful registration we show an in-flow "verify your email"
  // step instead of the form — mirrors the old confirmation dialog, but as
  // a screen state (there's no dedicated route/API for this step).
  bool _showVerify = false;
  String _registeredEmail = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 62, 24, 40),
          child: _showVerify ? _buildVerifyStep(context) : _buildFormStep(context),
        ),
      ),
    );
  }

  Widget _buildFormStep(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final headingStyle = theme.textTheme.titleLarge?.copyWith(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.2,
      color: scheme.onSurface,
    );

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(height: 20),
          Text('Create an account', style: headingStyle),
          const SizedBox(height: 6),
          Text(
            'Two minutes now, and the app starts learning what your money does.',
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 26),

          // Name field
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Full name',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your name';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          // Email field
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your email';
              }
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                return 'Please enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          // Password field
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your password';
              }
              if (value.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          // Confirm password field
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            decoration: InputDecoration(
              labelText: 'Confirm password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                ),
                onPressed: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please confirm your password';
              }
              if (value != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 18),

          // Consent line — replaces the old checkbox. Nothing about consent
          // is sent to the API either way, so this is a visual-only change.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_user_rounded, size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () {},
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant, height: 1.55),
                        children: [
                          const TextSpan(text: 'By continuing you accept the '),
                          TextSpan(
                            text: 'terms',
                            style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary),
                            recognizer: _tapGesture(_showTermsAndConditions),
                          ),
                          const TextSpan(text: ' and '),
                          TextSpan(
                            text: 'privacy policy',
                            style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary),
                            recognizer: _tapGesture(_showPrivacyPolicy),
                          ),
                          const TextSpan(text: '. We never sell your data.'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Error message
          Consumer<AuthProvider>(
            builder: (context, authProvider, child) {
              if (authProvider.error == null) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: scheme.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        authProvider.error!,
                        style: TextStyle(color: scheme.onErrorContainer, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // Register button
          Consumer<AuthProvider>(
            builder: (context, authProvider, child) {
              return SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: authProvider.isLoading ? null : _register,
                  child: authProvider.isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : const Text('Create account'),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          Center(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  children: [
                    const TextSpan(text: 'Already have one? '),
                    TextSpan(text: 'Sign in', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyStep(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => setState(() => _showVerify = false),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        Center(
          child: Column(
            children: [
              const SizedBox(height: 6),
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                child: Icon(Icons.mark_email_unread_rounded, size: 42, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 20),
              Text(
                'One tap left',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.6),
                  children: [
                    const TextSpan(text: 'We sent a verification link to\n'),
                    TextSpan(
                      text: _registeredEmail,
                      style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: theme.cardTheme.shadowColor ?? Colors.black12, blurRadius: 3, offset: const Offset(0, 1))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Why the extra step', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface)),
              const SizedBox(height: 6),
              Text(
                'Your email is the only way back into the account if you forget the password — so it has to be an address you really hold. '
                'Nothing is charged and no other email follows.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
            child: const Text("I've verified — sign in"),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant, height: 1.6),
              children: [
                const TextSpan(text: "Nothing arrived? Check spam, or "),
                TextSpan(
                  text: 'use a different address',
                  style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary),
                  recognizer: _tapGesture(() => setState(() => _showVerify = false)),
                ),
                const TextSpan(text: '.'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  void _register() async {
    if (_formKey.currentState!.validate()) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final email = _emailController.text.trim();
      final success = await authProvider.register(
        name: _nameController.text.trim(),
        email: email,
        password: _passwordController.text,
      );

      if (success) {
        setState(() {
          _registeredEmail = email;
          _showVerify = true;
        });
      }
    }
  }

  GestureRecognizer _tapGesture(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    return recognizer;
  }

  void _showTermsAndConditions() {
    showDialog(
      context: context,
      builder: (context) {
        final dialogScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.description_rounded, color: dialogScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Terms and Conditions',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Welcome to Toe Pwar - Personal Finance AI',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: dialogScheme.onSurface),
                ),
                const SizedBox(height: 12),
                Text(
                  'By using Toe Pwar, you agree to:\n\n'
                  '1. Use the app for personal financial management only\n\n'
                  '2. Provide accurate information when creating transactions\n\n'
                  '3. Keep your account credentials secure\n\n'
                  '4. Not misuse AI features or attempt to manipulate the system\n\n'
                  '5. Understand that financial insights are suggestions, not professional advice\n\n'
                  '6. Accept that premium features require an active subscription\n\n'
                  '7. Allow us to process your financial data to provide personalized insights',
                  style: TextStyle(fontSize: 13, color: dialogScheme.onSurfaceVariant, height: 1.5),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (context) {
        final dialogScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.privacy_tip_rounded, color: dialogScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Privacy Policy',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Your Privacy Matters',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: dialogScheme.onSurface),
                ),
                const SizedBox(height: 12),
                Text(
                  'We collect and use your data to:\n\n'
                  '• Provide personalized financial insights\n'
                  '• Improve our AI recommendations\n'
                  '• Secure your account and transactions\n'
                  '• Send important notifications about your finances\n\n'
                  'We protect your data by:\n\n'
                  '• Encrypting all sensitive information\n'
                  '• Never sharing your data with third parties without consent\n'
                  '• Allowing you to delete your data at any time\n'
                  '• Following industry-standard security practices\n\n'
                  'Your financial data is stored securely and used only to enhance your experience with Toe Pwar.',
                  style: TextStyle(fontSize: 13, color: dialogScheme.onSurfaceVariant, height: 1.5),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
