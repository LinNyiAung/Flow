// widgets/ai_chat_fab.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/services/localization_service.dart';

class AiChatFab extends StatelessWidget {
  final VoidCallback? onPressed;

  const AiChatFab({Key? key, this.onPressed}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return FloatingActionButton.extended(
      onPressed: onPressed ?? () => Navigator.pushNamed(context, '/ai-chat'),
      backgroundColor: Color(0xFF667eea),
      icon: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white.withOpacity(0.3), Colors.white.withOpacity(0.1)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.smart_toy,
          color: Colors.white,
          size: 16,
        ),
      ),
      label: Text(
        localizations.askAi,
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevation: 8,
      tooltip: localizations.chatWithAiAssistant,
    );
  }
}