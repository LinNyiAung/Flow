import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import 'register_screen.dart';
import '../home/home_screen.dart';
import 'package:frontend/services/responsive_helper.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    final responsive = ResponsiveHelper(context);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF667eea),
              Color(0xFF764ba2),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: responsive.padding(all: 24),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
                ),
                child: Padding(
                  padding: responsive.padding(all: 32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo and Title
                        Container(
                          width: responsive.iconSize(mobile: 80),
                          height: responsive.iconSize(mobile: 80),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                            ),
                            borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
                          ),
                          child: Icon(
                            Icons.account_balance_wallet,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                        SizedBox(height: responsive.sp16),
                        Text(
                          'Flow',
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs32,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF333333),
                          ),
                        ),
                        Text(
                          'Personal Finance AI',
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs16,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: responsive.sp32),

                        // Email Field
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
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
                        SizedBox(height: responsive.sp16),

                        // Password Field
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock_outlined),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your password';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: responsive.sp24),

                        // Error Message
                        Consumer<AuthProvider>(
                          builder: (context, authProvider, child) {
                            if (authProvider.error != null) {
                              return Container(
                                padding: responsive.padding(all: 12),
                                margin: responsive.padding(bottom: 16),
                                decoration: BoxDecoration(
                                  color: Colors.red[50],
                                  borderRadius: BorderRadius.circular(responsive.borderRadius(8)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline, color: Colors.red),
                                    SizedBox(width: responsive.sp8),
                                    Expanded(
                                      child: Text(
                                        authProvider.error!,
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return SizedBox.shrink();
                          },
                        ),

                        // Login Button
                        Consumer<AuthProvider>(
                          builder: (context, authProvider, child) {
                            return SizedBox(
                              width: double.infinity,
                              height: responsive.cardHeight(baseHeight: 50),
                              child: ElevatedButton(
                                onPressed: authProvider.isLoading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFF667eea),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                                  ),
                                ),
                                child: authProvider.isLoading
                                    ? CircularProgressIndicator(color: Colors.white)
                                    : Text(
                                  'Sign In',
                                  style: GoogleFonts.poppins(
                                    fontSize: responsive.fs16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        SizedBox(height: responsive.sp16),

                        // Register Link
                        Wrap(
                          alignment: WrapAlignment.center, // Centers the items when they wrap
                          spacing: 8.0, // Adds horizontal space between children
                          runSpacing: 4.0, // Adds vertical space between lines if they wrap
                          children: [
                            Text(
                              "Don't have an account? ",
                              style: GoogleFonts.poppins(color: Colors.grey[600]),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => RegisterScreen()),
                                );
                              },
                              child: Text(
                                'Sign Up',
                                style: GoogleFonts.poppins(
                                  color: Color(0xFF667eea),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _login() async {
    if (_formKey.currentState!.validate()) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (success) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen()),
        );
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}