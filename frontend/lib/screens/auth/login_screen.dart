import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/localization_service.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  /// True when rendered by AuthWrapper as the root route's body.
  final bool embedded;

  const LoginScreen({super.key, this.embedded = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isResending = false;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final headingStyle = theme.textTheme.titleLarge?.copyWith(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.2,
      color: scheme.onSurface,
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 56, 24, 40),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Icon(Icons.trending_up_rounded, size: 44, color: scheme.primary),
                  ),
                  const SizedBox(height: 18),
                  Text(localizations.toePwar, style: headingStyle),
                  const SizedBox(height: 4),
                  Text(
                    localizations.loginTagline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 34),

                  // Email field
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (value) {
                      // The "not verified" notice belongs to the address that
                      // was rejected; drop it once the user edits the e-mail.
                      final authProvider =
                          Provider.of<AuthProvider>(context, listen: false);
                      final pending = authProvider.pendingVerificationEmail;
                      if (pending != null && value.trim() != pending) {
                        authProvider.clearPendingVerification();
                      }
                    },
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
                      return null;
                    },
                  ),

                  // Forgot Password link
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ForgotPasswordScreen()),
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(localizations.forgotPasswordQuestion),
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Error message (the unverified-account notice is shown
                  // below the Sign in button instead, so it never pushes the
                  // button off-screen).
                  Consumer<AuthProvider>(
                    builder: (context, authProvider, child) {
                      if (authProvider.pendingVerificationEmail != null ||
                          authProvider.error == null) {
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
                                style: TextStyle(
                                  color: scheme.onErrorContainer,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  // Login Button
                  Consumer<AuthProvider>(
                    builder: (context, authProvider, child) {
                      return SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: authProvider.isLoading ? null : _login,
                          child: authProvider.isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(localizations.signIn),
                        ),
                      );
                    },
                  ),

                  // Unverified-account notice (only after an actual
                  // unverified login attempt).
                  Consumer<AuthProvider>(
                    builder: (context, authProvider, child) {
                      if (authProvider.pendingVerificationEmail == null) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _buildVerifyNotice(authProvider, scheme),
                      );
                    },
                  ),
                  const SizedBox(height: 18),

                  // Register link
                  GestureDetector(
                    onTap: _openRegister,
                    child: RichText(
                      text: TextSpan(
                        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        children: [
                          TextSpan(text: localizations.newHerePrefix),
                          TextSpan(
                            text: localizations.createAnAccount,
                            style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _login() async {
    if (_formKey.currentState!.validate()) {
      final authProvider =
          Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!success || !mounted) return;
      // When shown by AuthWrapper (the root route), AuthWrapper itself
      // switches to the force-update check / HomeScreen. When this login
      // screen was pushed on top of something else, go back to a single
      // fresh root so no duplicate HomeScreens pile up.
      if (!widget.embedded) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    }
  }

  /// Opens registration; when the user comes back from its "verify your
  /// e-mail" step, the registered address is prefilled here.
  Future<void> _openRegister() async {
    // AuthProvider.error is shared between Login and Register: clear it when
    // leaving for Register and again when coming back, so neither screen
    // shows the other's error.
    Provider.of<AuthProvider>(context, listen: false).clearError();
    final registeredEmail = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => RegisterScreen()),
    );
    if (!mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.clearError();
    if (registeredEmail == null || registeredEmail.isEmpty) return;
    authProvider.clearPendingVerification();
    setState(() {
      _emailController.text = registeredEmail;
      _passwordController.clear();
    });
  }

  Future<void> _resendVerification(String email) async {
    setState(() => _isResending = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final error = await authProvider.resendVerificationEmail(email);
    if (!mounted) return;
    setState(() => _isResending = false);
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? localizations.verificationEmailResent),
        backgroundColor: error == null ? null : scheme.error,
      ),
    );
  }

  Widget _buildVerifyNotice(AuthProvider authProvider, ColorScheme scheme) {
    final email = authProvider.pendingVerificationEmail;
    if (email == null) return const SizedBox.shrink();
    final localizations = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mark_email_unread_rounded, color: scheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  localizations.checkEmailToVerify,
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _isResending ? null : () => _resendVerification(email),
              icon: _isResending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(localizations.resendVerificationEmail),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
