import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/localization_service.dart';

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
  bool _isResending = false;
  String _registeredEmail = '';

  /// AuthProvider.error is shared with the login screen: only show it once
  /// this screen has made its own register attempt, so a login error (e.g.
  /// "Invalid credentials") never appears here.
  bool _showProviderError = false;

  @override
  void initState() {
    super.initState();
    // Drop the login screen's error (after the frame: notifying listeners
    // during build is not allowed).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Provider.of<AuthProvider>(context, listen: false).clearError();
    });
  }

  @override
  Widget build(BuildContext context) {
    // System back from the verify step behaves like "I've verified — sign
    // in" so the login screen still gets the registered address.
    return PopScope<Object?>(
      canPop: !_showVerify,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _showVerify) _backToSignIn();
      },
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 62, 24, 40),
            child: _showVerify ? _buildVerifyStep(context) : _buildFormStep(context),
          ),
        ),
      ),
    );
  }

  Widget _buildFormStep(BuildContext context) {
    final localizations = AppLocalizations.of(context);
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
          Text(localizations.createAnAccount, style: headingStyle),
          const SizedBox(height: 6),
          Text(
            localizations.registerTagline,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 26),

          // Name field
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: localizations.fullNameLabel,
              prefixIcon: const Icon(Icons.person_outline_rounded),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return localizations.pleaseEnterName;
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          // Email field
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: localizations.emailLabel,
              prefixIcon: const Icon(Icons.mail_outline_rounded),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return localizations.enterEmailError;
              }
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                return localizations.enterValidEmailError;
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
              labelText: localizations.passwordLabel,
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
                return localizations.enterPasswordError;
              }
              if (value.length < 6) {
                return localizations.passwordMinLengthError;
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
              labelText: localizations.confirmPasswordLabel,
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
                return localizations.confirmPasswordError;
              }
              if (value != _passwordController.text) {
                return localizations.passwordsNotMatch;
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
                          TextSpan(text: localizations.byContinuingAcceptPrefix),
                          TextSpan(
                            text: localizations.termsLinkText,
                            style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary),
                            recognizer: _tapGesture(_showTermsAndConditions),
                          ),
                          TextSpan(text: localizations.andConnector),
                          TextSpan(
                            text: localizations.privacyPolicyLinkText,
                            style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary),
                            recognizer: _tapGesture(_showPrivacyPolicy),
                          ),
                          TextSpan(text: localizations.neverSellDataSuffix),
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
              if (!_showProviderError || authProvider.error == null) {
                return const SizedBox.shrink();
              }
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
                      : Text(localizations.createAccountButton),
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
                    TextSpan(text: localizations.alreadyHaveAccountPrefix),
                    TextSpan(text: localizations.signIn, style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
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
    final localizations = AppLocalizations.of(context);
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
                localizations.oneTapLeft,
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
                    TextSpan(text: localizations.verificationLinkSentPrefix),
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
              Text(localizations.whyExtraStepTitle, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface)),
              const SizedBox(height: 6),
              Text(
                localizations.emailVerificationExplanation,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            // Back to the login screen this flow was opened from (the root
            // AuthWrapper) instead of stacking another LoginScreen; it
            // prefills the registered address.
            onPressed: _backToSignIn,
            child: Text(localizations.verifiedSignInButton),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isResending ? null : _resendVerification,
            icon: _isResending
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded, size: 18),
            label: Text(localizations.resendVerificationEmail),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant, height: 1.6),
              children: [
                TextSpan(text: localizations.nothingArrivedPrefix),
                TextSpan(
                  text: localizations.useDifferentAddressLink,
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
      setState(() => _showProviderError = true);
      final success = await authProvider.register(
        name: _nameController.text.trim(),
        email: email,
        password: _passwordController.text,
      );

      if (!mounted) return;
      if (success && authProvider.isAuthenticated) {
        // Already-verified account (e.g. verification disabled server-side).
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        return;
      }
      if (success) {
        setState(() {
          _registeredEmail = email;
          _showVerify = true;
        });
      }
    }
  }

  /// Leaves the verify step for the login screen, handing it the registered
  /// address. Clears any stale "not verified" notice there.
  void _backToSignIn() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.clearPendingVerification();
    authProvider.clearError();
    Navigator.pop(context, _registeredEmail);
  }

  Future<void> _resendVerification() async {
    setState(() => _isResending = true);
    final error = await Provider.of<AuthProvider>(context, listen: false)
        .resendVerificationEmail(_registeredEmail);
    if (!mounted) return;
    setState(() => _isResending = false);
    final localizations = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? localizations.verificationEmailResent
              : (error.isEmpty ? localizations.genericErrorOccurred : error),
        ),
        backgroundColor:
            error == null ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }

  GestureRecognizer _tapGesture(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    return recognizer;
  }

  void _showTermsAndConditions() {
    showDialog(
      context: context,
      builder: (context) {
        final localizations = AppLocalizations.of(context);
        final dialogScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.description_rounded, color: dialogScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  localizations.termsAndConditionsTitle,
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
                  localizations.welcomeToToePwarTagline,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: dialogScheme.onSurface),
                ),
                const SizedBox(height: 12),
                Text(
                  localizations.termsAndConditionsBody,
                  style: TextStyle(fontSize: 13, color: dialogScheme.onSurfaceVariant, height: 1.5),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(localizations.close),
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
        final localizations = AppLocalizations.of(context);
        final dialogScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.privacy_tip_rounded, color: dialogScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  localizations.privacyPolicyTitle,
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
                  localizations.yourPrivacyMattersTitle,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: dialogScheme.onSurface),
                ),
                const SizedBox(height: 12),
                Text(
                  localizations.privacyPolicyBody,
                  style: TextStyle(fontSize: 13, color: dialogScheme.onSurfaceVariant, height: 1.5),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(localizations.close),
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
