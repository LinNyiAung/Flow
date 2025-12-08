import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import 'package:frontend/services/responsive_helper.dart';

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
              authProvider.error ?? 'Failed to update profile',
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
    
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
        ),
        title: Text(
          'Discard Changes?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'You have unsaved changes. Are you sure you want to discard them?',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Keep Editing',
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
              'Discard',
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

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Edit Profile',
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
                    'Tap icon to change avatar',
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
                  'Full Name',
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
                    hintText: 'Enter your full name',
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
                      return 'Please enter your name';
                    }
                    if (value.trim().length < 2) {
                      return 'Name must be at least 2 characters';
                    }
                    return null;
                  },
                ),

                SizedBox(height: responsive.sp24),

                // Email Field (Read-only)
                Text(
                  'Email Address',
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
                    'Email cannot be changed',
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
                            'Save Changes',
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
                      'You have unsaved changes',
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs12,
                        color: Color(0xFFFF9800),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}