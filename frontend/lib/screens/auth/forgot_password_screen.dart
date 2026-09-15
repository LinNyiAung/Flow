import 'dart:async'; // Required for Timer
import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';
import 'login_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({Key? key}) : super(key: key);

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _error;

  Future<void> _requestOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ApiService.requestPasswordResetOtp(
        email: _emailController.text.trim(),
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            email: _emailController.text.trim(),
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Scaffold(
      body: _AuthShell(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BackArrow(onTap: () => Navigator.pop(context)),
              _StepHeader(
                icon: Icons.lock_reset_rounded,
                title: localizations.resetPasswordTitle,
                subtitle: localizations.resetPasswordSubtitle,
              ),
              const SizedBox(height: 24),

              // Email field
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: localizations.emailAddressLabel,
                  prefixIcon: const Icon(Icons.mail_outline_rounded),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return localizations.enterEmailError;
                  if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v)) {
                    return localizations.enterValidEmailError;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              if (_error != null) _ErrorBanner(message: _error!),

              const SizedBox(height: 4),

              _PrimaryButton(
                label: localizations.sendCodeButton,
                isLoading: _isLoading,
                onPressed: _requestOtp,
              ),
              const SizedBox(height: 16),

              const _BackToLoginButton(),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 2 – OTP entry + resend
// ─────────────────────────────────────────────────────────────────────────────
class OtpVerificationScreen extends StatefulWidget {
  final String email;
  const OtpVerificationScreen({Key? key, required this.email}) : super(key: key);

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final pinController = TextEditingController();
  final focusNode = FocusNode();

  bool _isLoading = false;
  bool _isResending = false;
  String? _error;

  // Timer Variables
  Timer? _timer;
  int _secondsLeft = 60;

  @override
  void initState() {
    super.initState();
    _startTimer(); // Start the countdown when the screen loads
  }

  void _startTimer() {
    _timer?.cancel(); // Cancel any existing timer
    setState(() => _secondsLeft = 60);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        timer.cancel(); // Stop timer when it hits 0
      }
    });
  }

  String get _otp => pinController.text;

  Future<void> _verify() async {
    if (_otp.length < 6) {
      setState(() => _error = AppLocalizations.of(context).enterAllSixDigitsError);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final resetToken = await ApiService.verifyPasswordResetOtp(
        email: widget.email,
        otp: _otp,
      );
      if (!mounted) return;

      _timer?.cancel(); // Cancel timer before navigating away

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResetPasswordScreen(
            email: widget.email,
            resetToken: resetToken,
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
      pinController.clear();
      focusNode.requestFocus();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _isResending = true;
      _error = null;
    });

    try {
      await ApiService.requestPasswordResetOtp(email: widget.email);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).newCodeSentMessage)),
      );

      _startTimer(); // Restart the timer only on success
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel(); // Crucial: prevent memory leaks
    pinController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final defaultPinTheme = PinTheme(
      width: 48,
      height: 56,
      textStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline),
      ),
    );
    // A box with a digit already committed reads with a jade-tinted border;
    // focused gets the full jade ring; a failed verification turns every
    // box's border error-red until the next edit clears it.
    final submittedPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration!.copyWith(
        border: Border.all(color: scheme.primary.withValues(alpha: 0.45)),
      ),
    );
    final errorPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration!.copyWith(
        border: Border.all(color: scheme.error, width: 1.5),
      ),
    );

    return Scaffold(
      body: _AuthShell(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BackArrow(onTap: () => Navigator.pop(context)),
            _StepHeader(
              icon: Icons.mark_email_read_rounded,
              title: localizations.enterTheCodeTitle,
              subtitle: '${localizations.sentCodeToPrefix} ${widget.email}. ${localizations.expiresInTenMinutes}',
            ),
            const SizedBox(height: 24),

            Pinput(
              length: 6,
              controller: pinController,
              focusNode: focusNode,
              defaultPinTheme: defaultPinTheme,
              focusedPinTheme: defaultPinTheme.copyWith(
                decoration: defaultPinTheme.decoration!.copyWith(
                  border: Border.all(color: scheme.primary, width: 1.5),
                ),
              ),
              submittedPinTheme: submittedPinTheme,
              followingPinTheme: defaultPinTheme,
              errorPinTheme: errorPinTheme,
              forceErrorState: _error != null,
              onChanged: (value) => setState(() => _error = null),
              onCompleted: (pin) => _verify(),
            ),

            const SizedBox(height: 16),

            if (_error != null) _ErrorBanner(message: _error!),

            const SizedBox(height: 4),

            _PrimaryButton(
              label: localizations.verifyCodeButton,
              isLoading: _isLoading,
              onPressed: _verify,
            ),

            const SizedBox(height: 18),

            // Resend row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  localizations.didntGetItPrefix,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                ),
                _secondsLeft > 0
                    ? Text(
                        '${localizations.resendInPrefix} ${_secondsLeft}s',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                      )
                    : _isResending
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
                          )
                        : GestureDetector(
                            onTap: _resend,
                            child: Text(
                              localizations.sendNewCodeButton,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.primary),
                            ),
                          ),
              ],
            ),

            const SizedBox(height: 8),
            const _BackToLoginButton(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 3 – New password entry
// ─────────────────────────────────────────────────────────────────────────────
class ResetPasswordScreen extends StatefulWidget {
  final String email;
  final String resetToken;

  const ResetPasswordScreen({
    Key? key,
    required this.email,
    required this.resetToken,
  }) : super(key: key);

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _error;

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ApiService.resetPassword(
        email: widget.email,
        resetToken: widget.resetToken,
        newPassword: _newPasswordController.text,
        confirmPassword: _confirmPasswordController.text,
      );
      if (!mounted) return;

      final scheme = Theme.of(context).colorScheme;
      final localizations = AppLocalizations.of(context);

      // Show success dialog then go to login
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                child: Icon(Icons.check_circle_rounded, color: scheme.primary, size: 40),
              ),
              const SizedBox(height: 16),
              Text(
                localizations.passwordResetTitle,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                localizations.passwordResetSuccessMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(); // close dialog
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => LoginScreen()),
                      (route) => false,
                    );
                  },
                  child: Text(localizations.backToLogin),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Scaffold(
      body: _AuthShell(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StepHeader(
                icon: Icons.lock_outline_rounded,
                title: localizations.chooseNewPasswordTitle,
                subtitle: localizations.codeAcceptedSubtitle,
              ),
              const SizedBox(height: 22),

              // New password
              TextFormField(
                controller: _newPasswordController,
                obscureText: _obscureNew,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: localizations.newPasswordLabel,
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureNew ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return localizations.pleaseEnterAPasswordError;
                  if (v.length < 6) return localizations.minimumSixCharactersError;
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Confirm password
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: localizations.confirmItLabel,
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return localizations.confirmPasswordError;
                  if (v != _newPasswordController.text) return localizations.passwordsNotMatch;
                  return null;
                },
              ),
              const SizedBox(height: 16),

              if (_error != null) _ErrorBanner(message: _error!),

              const SizedBox(height: 4),

              _PrimaryButton(
                label: localizations.saveAndSignInButton,
                isLoading: _isLoading,
                onPressed: _resetPassword,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared private widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Full-bleed auth screen layout — no card, no gradient. The theme's
/// scaffold background (surface) shows straight through, matching the
/// register / login screens.
class _AuthShell extends StatelessWidget {
  final Widget child;
  const _AuthShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: child,
      ),
    );
  }
}

class _BackArrow extends StatelessWidget {
  final VoidCallback onTap;
  const _BackArrow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _StepHeader({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
          child: Icon(icon, size: 30, color: scheme.primary),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  const _PrimaryButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
            )
          : Text(label),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
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
              message,
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackToLoginButton extends StatelessWidget {
  const _BackToLoginButton();

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Center(
      child: TextButton.icon(
        onPressed: () {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => LoginScreen()),
            (route) => false,
          );
        },
        icon: const Icon(Icons.arrow_back_rounded, size: 16),
        label: Text(localizations.backToLogin),
      ),
    );
  }
}
