import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import 'package:frontend/services/responsive_helper.dart';

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
          SnackBar(
            content: Text(
              authProvider.error ?? localizations.failedUpdateProfile,
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'An error occurred: ${e.toString()}',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);

    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
        ),
        title: Text(
          localizations.discardChanges,
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Text(
          localizations.discardChangesAlert,
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              localizations.keepEditing,
              style: GoogleFonts.poppins(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
              ),
            ),
            child: Text(
              localizations.discard,
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            localizations.editProfile,
            style: GoogleFonts.poppins(
              fontSize: responsive.fs20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF333333),
            ),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Color(0xFF333333)),
            onPressed: () async {
              if (await _onWillPop()) {
                Navigator.pop(context);
              }
            },
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
          child: Form(
            key: _formKey,
            child: ListView(
              padding: responsive.padding(all: 20),
              children: [
                // Profile Avatar Section
                Center(
                  child: Stack(
                    children: [
                      Container(
                        padding: responsive.padding(all: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 60,
                          backgroundColor: Colors.white,
                          child: Text(
                            user?.name != null && user!.name.isNotEmpty
                                ? user.name[0].toUpperCase()
                                : 'U',
                            style: GoogleFonts.poppins(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF667eea),
                            ),
                          ),
                        ),
                      ),
                      if (authProvider.isPremium)
                        Positioned(
                          bottom: 5,
                          right: 5,
                          child: Container(
                            padding: responsive.padding(all: 8),
                            decoration: BoxDecoration(
                              color: Color(0xFFFFD700),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                            child: Icon(
                              Icons.star,
                              color: Colors.white,
                              size: responsive.icon20,
                            ),
                          ),
                        ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: responsive.padding(all: 8),
                          decoration: BoxDecoration(
                            color: Color(0xFF667eea),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF667eea).withOpacity(0.3),
                                spreadRadius: 2,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: responsive.icon20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: responsive.sp12),
                Center(
                  child: Text(
                    localizations.tapIconChangeAvatar,
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),

                SizedBox(height: responsive.sp32),

                // Name Field
                Text(
                  localizations.fullName,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                SizedBox(height: responsive.sp8),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: localizations.enterFullName,
                    prefixIcon: Icon(Icons.person_outline, color: Color(0xFF667eea)),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                      borderSide: BorderSide(color: Color(0xFF667eea), width: 2),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                      borderSide: BorderSide(color: Colors.red),
                    ),
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

                SizedBox(height: responsive.sp24),

                // Email Field (Read-only)
                Text(
                  localizations.emailAddress,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                SizedBox(height: responsive.sp8),
                Container(
                  padding: responsive.padding(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.email_outlined,
                        color: Colors.grey[600],
                      ),
                      SizedBox(width: responsive.sp12),
                      Expanded(
                        child: Text(
                          user?.email ?? '',
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs14,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                      Icon(
                        Icons.lock_outline,
                        color: Colors.grey[400],
                        size: responsive.icon18,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: responsive.sp8),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    localizations.emailCannotChanged,
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs11,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),

                SizedBox(height: responsive.sp32),

                // Save Button
                SizedBox(
                  height: responsive.cardHeight(baseHeight: 50),
                  child: ElevatedButton(
                    onPressed: _isLoading || !_hasChanges ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF667eea),
                      disabledBackgroundColor: Colors.grey[300],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                      ),
                      elevation: _hasChanges ? 4 : 0,
                    ),
                    child: _isLoading
                        ? SizedBox(
                            height: responsive.sp20,
                            width: responsive.sp20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            localizations.saveChanges,
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs16,
                              fontWeight: FontWeight.w600,
                              color: _hasChanges ? Colors.white : Colors.grey[600],
                            ),
                          ),
                  ),
                ),

                if (_hasChanges) ...[
                  SizedBox(height: responsive.sp12),
                  Center(
                    child: Text(
                      localizations.haveUnsavedChanges,
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs12,
                        color: Color(0xFFFF9800),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],

                SizedBox(height: responsive.sp32),

                // Danger Zone
                Container(
                  padding: responsive.padding(all: 16),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.red, size: responsive.icon20),
                          SizedBox(width: responsive.sp8),
                          Text(
                            localizations.dangerZone,
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs16,
                              fontWeight: FontWeight.bold,
                              color: Colors.red[900],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: responsive.sp12),
                      Text(
                        localizations.dangerZoneDes,
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs12,
                          color: Colors.red[800],
                        ),
                      ),
                      SizedBox(height: responsive.sp16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : () => _showDeleteAccountDialog(context),
                          icon: Icon(Icons.delete_forever, color: Colors.red),
                          label: Text(
                            localizations.deleteAccount,
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs14,
                              fontWeight: FontWeight.w600,
                              color: Colors.red,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.red, width: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
                            ),
                            padding: responsive.padding(vertical: 12),
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
      ),
    );
  }


Future<void> _showDeleteAccountDialog(BuildContext context) async {
  final responsive = ResponsiveHelper(context);
  final localizations = AppLocalizations.of(context);

  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
      ),
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red, size: responsive.icon24),
          SizedBox(width: responsive.sp8),
          Text(
            localizations.deleteAccountQ,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: Colors.red,
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
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: responsive.fs14,
            ),
          ),
          SizedBox(height: responsive.sp8),
          _buildDeleteItem(responsive, '• ${localizations.allYourTransactions}'),
          _buildDeleteItem(responsive, '• ${localizations.allYourFinancialGoals}'),
          _buildDeleteItem(responsive, '• ${localizations.allYourBudgets}'),
          _buildDeleteItem(responsive, '• ${localizations.allYourAiInsights}'),
          _buildDeleteItem(responsive, '• ${localizations.allYourChatHistory}'),
          _buildDeleteItem(responsive, '• ${localizations.yourAccountInformation}'),
          SizedBox(height: responsive.sp16),
          Container(
            padding: responsive.padding(all: 12),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Text(
              localizations.actionCannotBeUndone,
              style: GoogleFonts.poppins(
                fontSize: responsive.fs12,
                color: Colors.red[900],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            localizations.dialogCancel,
            style: GoogleFonts.poppins(color: Colors.grey[600]),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
            ),
          ),
          child: Text(
            localizations.deleteAccount,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    await _deleteAccount(context);
  }
}

Widget _buildDeleteItem(ResponsiveHelper responsive, String text) {
  return Padding(
    padding: responsive.padding(vertical: 4),
    child: Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: responsive.fs13,
        color: Colors.grey[700],
      ),
    ),
  );
}

Future<void> _deleteAccount(BuildContext context) async {
  final localizations = AppLocalizations.of(context);
  
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
        SnackBar(
          content: Text(
            'Account deleted successfully',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authProvider.error ?? 'Failed to delete account',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } catch (e) {
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'An error occurred: ${e.toString()}',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
}