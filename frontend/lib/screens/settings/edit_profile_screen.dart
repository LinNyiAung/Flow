import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

import '../../services/localization_service.dart';

class EditProfileScreen extends StatefulWidget {
  @override
  _EditProfileScreenState createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  bool _isLoading = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _nameController.text = authProvider.user?.name ?? '';

    // Listen for changes
    _nameController.addListener(_checkForChanges);
  }

  void _checkForChanges() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    setState(() {
      _hasChanges = _nameController.text != authProvider.user?.name;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final localizations = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (!_hasChanges) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.updateProfile(
        name: _nameController.text.trim(),
      );

      setState(() => _isLoading = false);

      if (success) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(authProvider.error ?? localizations.failedUpdateProfile)),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An error occurred: ${e.toString()}')),
      );
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;
    final localizations = AppLocalizations.of(context);

    return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(localizations.discardChanges, style: const TextStyle(fontWeight: FontWeight.bold)),
            content: Text(localizations.discardChangesAlert),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(localizations.keepEditing),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                child: Text(localizations.discard),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final scheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(localizations.editProfile),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () async {
              if (await _onWillPop()) {
                Navigator.pop(context);
              }
            },
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Profile Avatar Section
              Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 56,
                      backgroundColor: scheme.primaryContainer,
                      child: Text(
                        user?.name != null && user!.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                        style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer),
                      ),
                    ),
                    if (authProvider.isPremium)
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: scheme.tertiary,
                            shape: BoxShape.circle,
                            border: Border.all(color: scheme.surface, width: 3),
                          ),
                          child: const Icon(Icons.star_rounded, color: Colors.white, size: 16),
                        ),
                      ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.surface, width: 3),
                        ),
                        child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  localizations.tapIconChangeAvatar,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                ),
              ),

              const SizedBox(height: 32),

              // Name Field
              Text(
                localizations.fullName,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: localizations.enterFullName,
                  prefixIcon: const Icon(Icons.person_rounded),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return localizations.pleaseEnterName;
                  }
                  if (value.trim().length < 2) {
                    return localizations.nameTwoCharacters;
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Email Field (Read-only)
              Text(
                localizations.emailAddress,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outline),
                ),
                child: Row(
                  children: [
                    Icon(Icons.email_rounded, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        user?.email ?? '',
                        style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.lock_rounded, color: scheme.onSurfaceVariant, size: 18),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  localizations.emailCannotChanged,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                ),
              ),

              const SizedBox(height: 32),

              // Save Button
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _isLoading || !_hasChanges ? null : _saveProfile,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(localizations.saveChanges),
                ),
              ),

              if (_hasChanges) ...[
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    localizations.haveUnsavedChanges,
                    style: TextStyle(fontSize: 12, color: scheme.tertiary, fontWeight: FontWeight.w600),
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Danger Zone
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: scheme.error, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          localizations.dangerZone,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: scheme.onErrorContainer),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      localizations.dangerZoneDes,
                      style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : () => _showDeleteAccountDialog(context),
                        icon: Icon(Icons.delete_forever_rounded, color: scheme.error),
                        label: Text(
                          localizations.deleteAccount,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.error),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: scheme.error, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountDialog(BuildContext context) async {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: scheme.error, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                localizations.deleteAccountQ,
                style: TextStyle(fontWeight: FontWeight.bold, color: scheme.error),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizations.willPermanentlyDelete,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            _buildDeleteItem('• ${localizations.allYourTransactions}'),
            _buildDeleteItem('• ${localizations.allYourFinancialGoals}'),
            _buildDeleteItem('• ${localizations.allYourBudgets}'),
            _buildDeleteItem('• ${localizations.allYourAiInsights}'),
            _buildDeleteItem('• ${localizations.allYourChatHistory}'),
            _buildDeleteItem('• ${localizations.yourAccountInformation}'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                localizations.actionCannotBeUndone,
                style: TextStyle(fontSize: 12, color: scheme.onErrorContainer, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(localizations.dialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            child: Text(localizations.deleteAccount),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteAccount(context);
    }
  }

  Widget _buildDeleteItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(text, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.deleteAccount();

      setState(() => _isLoading = false);

      if (success) {
        // Navigate to login screen
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/login',
          (route) => false,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account deleted successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(authProvider.error ?? 'Failed to delete account')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An error occurred: ${e.toString()}')),
      );
    }
  }
}
