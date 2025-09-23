import 'package:flutter/material.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/home/home_screen.dart';
import '../screens/transactions/transactions_list_screen.dart'; // We'll create this next

class AppDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Get the current user's data from AuthProvider
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;

    return Drawer(
      // Apply a subtle gradient to the drawer background
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF667eea).withOpacity(0.05), // Subtle purple tint
              Colors.white.withOpacity(0.9),
            ],
          ),
        ),
        child: ListView(
          padding: EdgeInsets.zero, // Remove default padding
          children: <Widget>[
            // Drawer Header
            DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)], // Purple gradient
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User Avatar
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white.withOpacity(0.8),
                    child: Text(
                      user?.name != null && user!.name.isNotEmpty
                          ? user.name[0].toUpperCase() // Display first initial
                          : 'U', // Default if name is null or empty
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF667eea), // Primary purple
                      ),
                    ),
                  ),
                  SizedBox(height: 12),
                  // User Name
                  Text(
                    user?.name ?? 'Welcome',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  // User Email
                  Text(
                    user?.email ?? '',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            // Navigation Items
            ListTile(
              leading: Icon(Icons.dashboard, color: Color(0xFF667eea)),
              title: Text(
                'Dashboard',
                style: GoogleFonts.poppins(fontSize: 16),
              ),
              onTap: () {
                Navigator.pop(context); // Close the drawer
                // Navigate to HomeScreen if not already there
                if (ModalRoute.of(context)?.settings.name != '/') {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => HomeScreen()),
                  );
                }
              },
            ),
            Divider(height: 1, thickness: 1, color: Colors.grey[200]), // Visual separator
            ListTile(
              leading: Icon(Icons.list_alt, color: Color(0xFF764ba2)),
              title: Text(
                'Transactions',
                style: GoogleFonts.poppins(fontSize: 16),
              ),
              onTap: () {
                Navigator.pop(context); // Close the drawer
                // Navigate to TransactionsListScreen
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => TransactionsListScreen()),
                );
              },
            ),
            Divider(height: 1, thickness: 1, color: Colors.grey[200]),
            ListTile(
              leading: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(Icons.smart_toy, color: Colors.white, size: 16),
              ),
              title: Text(
                'AI Assistant',
                style: GoogleFonts.poppins(fontSize: 16),
              ),
              onTap: () {
                Navigator.pop(context); // Close the drawer
                Navigator.pushNamed(context, '/ai-chat');
              },
            ),
            Divider(height: 1, thickness: 1, color: Colors.grey[200]),
            
            // Financial Insights option
            ListTile(
              leading: Icon(Icons.lightbulb_outline, color: Colors.orange),
              title: Text(
                'Financial Insights',
                style: GoogleFonts.poppins(fontSize: 16),
              ),
              onTap: () {
                Navigator.pop(context); // Close the drawer
                Navigator.pushNamed(context, '/insights');
              },
            ),
            Divider(height: 1, thickness: 1, color: Colors.grey[200]),
            // Add more navigation items here later if needed (e.g., Analytics, Settings)
            Divider(height: 1, thickness: 1, color: Colors.grey[200]),
            Spacer(), // Pushes the logout button to the bottom
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context); // Close drawer
                  // Show logout confirmation dialog
                  _showLogoutDialog(context);
                },
                icon: Icon(Icons.logout, color: Colors.white),
                label: Text(
                  'Logout',
                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w500),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, // Red logout button
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Function to show logout confirmation dialog
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Logout',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          content: Text(
            'Are you sure you want to logout?',
            style: GoogleFonts.poppins(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), // Close dialog
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(
                  color: Colors.grey[600],
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Provider.of<AuthProvider>(context, listen: false).logout(); // Perform logout
                // Navigate back to login screen and replace current route
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => LoginScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, // Red color for logout button
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Logout',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }
}