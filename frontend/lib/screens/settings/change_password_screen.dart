import 'package:flutter/material.dart';
import 'package:frontend/widgets/progress_meter.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

import '../../services/localization_service.dart';

class ChangePasswordScreen extends StatefulWidget {
  @override
  _ChangePasswordScreenState createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _newPasswordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  double get _strength {
    final pw = _newPasswordController.text;
    if (pw.isEmpty) return 0;
    var score = 0;
    if (pw.length >= 6) score++;
    if (pw.length >= 10) score++;
    if (RegExp(r'[0-9]').hasMatch(pw)) score++;
    if (RegExp(r'[A-Z]').hasMatch(pw)) score++;
    if (RegExp(r'[^a-zA-Z0-9]').hasMatch(pw)) score++;
    return (score / 5).clamp(0.0, 1.0);
  }

  String _strengthLabel(AppLocalizations localizations) {
    final s = _strength;
    if (_newPasswordController.text.isEmpty) return '';
    if (s < 0.4) return localizations.passwordStrengthWeak;
    if (s < 0.7) return localizations.passwordStrengthFair;
    if (s < 0.9) return localizations.passwordStrengthGood;
    return localizations.passwordStrengthStrong;
  }

  Color get _strengthColor {
    final scheme = Theme.of(context).colorScheme;
    final s = _strength;
    if (s < 0.4) return scheme.error;
    if (s < 0.7) return scheme.tertiary;
    return scheme.primary;
  }

  Future<void> _changePassword() async {
    final localizations = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
        confirmPassword: _confirmPasswordController.text,
      );

      setState(() => _isLoading = false);

      if (success) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(authProvider.error ?? localizations.failedToChangePassword)),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${localizations.errorOccurred} ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(localizations.changePassword)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_rounded, color: scheme.onSurfaceVariant, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      localizations.passwordSixCharacters,
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Current Password
            Text(
              localizations.currentPassword,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _currentPasswordController,
              obscureText: _obscureCurrentPassword,
              decoration: InputDecoration(
                hintText: localizations.enterCurrentPassword,
                prefixIcon: const Icon(Icons.lock_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscureCurrentPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  onPressed: () {
                    setState(() {
                      _obscureCurrentPassword = !_obscureCurrentPassword;
                    });
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return localizations.pleaseEnterCurrentPassword;
                }
                return null;
              },
            ),

            const SizedBox(height: 24),

            // New Password
            Text(
              localizations.newPassword,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _newPasswordController,
              obscureText: _obscureNewPassword,
              decoration: InputDecoration(
                hintText: localizations.enterNewPassword,
                prefixIcon: const Icon(Icons.lock_reset_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscureNewPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  onPressed: () {
                    setState(() {
                      _obscureNewPassword = !_obscureNewPassword;
                    });
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return localizations.pleaseEnterNewPassword;
                }
                if (value.length < 6) {
                  return localizations.passwordSixCharacters;
                }
                if (value == _currentPasswordController.text) {
                  return localizations.newPasswordDifferentCurrentPassword;
                }
                return null;
              },
            ),

            if (_newPasswordController.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: ProgressMeter(value: _strength, overrideColor: _strengthColor)),
                  const SizedBox(width: 10),
                  Text(
                    _strengthLabel(localizations),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _strengthColor),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Confirm Password
            Text(
              localizations.confirmNewPassword,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              decoration: InputDecoration(
                hintText: localizations.confirmYourNewPassword,
                prefixIcon: const Icon(Icons.check_circle_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirmPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  onPressed: () {
                    setState(() {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    });
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return localizations.pleaseConfirmNewPassword;
                }
                if (value != _newPasswordController.text) {
                  return localizations.passwordsNotMatch;
                }
                return null;
              },
            ),

            const SizedBox(height: 20),

            // Consequence notice
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                localizations.passwordChangeSignOutNotice,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ),

            const SizedBox(height: 28),

            // Change Password Button
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _isLoading ? null : _changePassword,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(localizations.changePassword),
              ),
            ),

            const SizedBox(height: 12),

            // Cancel Button
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: _isLoading ? null : () => Navigator.pop(context),
                child: Text(localizations.dialogCancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
