import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/localization_service.dart';

class PremiumBadge extends StatelessWidget {
  final bool small;

  const PremiumBadge({this.small = false});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 8,
        vertical: small ? 2 : 4,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star,
            color: Colors.white,
            size: small ? 12 : 16,
          ),
          SizedBox(width: 4),
          Text(
            localizations.premium,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: small ? 10 : 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class PremiumFeatureOverlay extends StatelessWidget {
  final Widget child;
  final bool isPremiumFeature;
  final VoidCallback? onUpgradeTap;

  const PremiumFeatureOverlay({
    required this.child,
    this.isPremiumFeature = false,
    this.onUpgradeTap,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    if (!isPremiumFeature) {
      return child;
    }

    return Stack(
      children: [
        child,
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock,
                    color: Color(0xFFFFD700),
                    size: 48,
                  ),
                  SizedBox(height: 8),
                  Text(
                    localizations.premiumFeatureTitle,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: onUpgradeTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFFFD700),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      localizations.upgradeNowButton,
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}