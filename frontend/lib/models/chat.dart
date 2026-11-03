// models/chat.dart

import 'package:frontend/utils/date_parsing.dart';
import 'package:flutter/material.dart';

import '../services/localization_service.dart';

enum MessageRole { user, assistant }

// NEW: Response style enum
enum ResponseStyle {
  normal,
  concise,
  explanatory;

  String getDisplayName(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    switch (this) {
      case ResponseStyle.normal:
        return localizations.normal;
      case ResponseStyle.concise:
        return localizations.concise;
      case ResponseStyle.explanatory:
        return localizations.detailed;
    }
  }

  String getDescription(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    switch (this) {
      case ResponseStyle.normal:
        return localizations.balancedResponses;
      case ResponseStyle.concise:
        return localizations.briefDirect;
      case ResponseStyle.explanatory:
        return localizations.thoroughExplanations;
    }
  }

  IconData get icon {
    switch (this) {
      case ResponseStyle.normal:
        return Icons.chat_bubble_outline;
      case ResponseStyle.concise:
        return Icons.speed;
      case ResponseStyle.explanatory:
        return Icons.article_outlined;
    }
  }
}

class ChatMessage {
  final MessageRole role;
  final String content;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'] == 'user' ? MessageRole.user : MessageRole.assistant,
      content: json['content'],
      timestamp: parseInstant(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'role': role.name,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Which model answers a chat message (Pro only: Advanced). The name is the
/// value the server's `mode` field takes.
enum ChatMode {
  standard,
  advanced;

  static ChatMode fromName(String? name) =>
      ChatMode.values.where((m) => m.name == name).firstOrNull ?? ChatMode.standard;
}

/// The first frame of the chat stream: which model really answers, and
/// whether an Advanced request fell back to Standard because the Advanced
/// allowance is used up.
class ChatStreamMeta {
  final ChatMode modeUsed;
  final bool advancedExhausted;

  const ChatStreamMeta({required this.modeUsed, this.advancedExhausted = false});

  factory ChatStreamMeta.fromFrame(Map<dynamic, dynamic> frame) => ChatStreamMeta(
        modeUsed: ChatMode.fromName(
            frame['mode_used'] is String ? frame['mode_used'] as String : null),
        advancedExhausted: frame['advanced_exhausted'] == true,
      );
}

class ChatRequest {
  final String message;
  final List<ChatMessage>? chatHistory;
  final ResponseStyle? responseStyle;
  final ChatMode mode;

  ChatRequest({
    required this.message,
    this.chatHistory,
    this.responseStyle,
    this.mode = ChatMode.standard,
  });

  Map<String, dynamic> toJson() {
    return {
      'message': message,
      'chat_history': chatHistory?.map((msg) => msg.toJson()).toList(),
      if (responseStyle != null) 'response_style': responseStyle!.name,
      'mode': mode.name,
    };
  }
}

class ChatResponse {
  final String response;
  final DateTime timestamp;

  ChatResponse({required this.response, required this.timestamp});

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    return ChatResponse(
      response: json['response'],
      timestamp: parseInstant(json['timestamp']),
    );
  }
}
