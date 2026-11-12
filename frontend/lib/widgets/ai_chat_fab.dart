// widgets/ai_chat_fab.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/mascot.dart';

/// "Ask Ko Toe Pwar": opens the chat, with his face as the icon.
class AiChatFab extends StatelessWidget {
  final VoidCallback? onPressed;

  const AiChatFab({Key? key, this.onPressed}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return FloatingActionButton.extended(
      onPressed: onPressed ?? () => Navigator.pushNamed(context, '/ai-chat'),
      backgroundColor: Color(0xFF667eea),
      icon: const Mascot.face(size: 28),
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
