// models/chat.dart

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
  
  String getDescription (BuildContext context){
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
      timestamp: DateTime.parse(json['timestamp']),
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

class ChatRequest {
  final String message;
  final List<ChatMessage>? chatHistory;
  final ResponseStyle? responseStyle;  // NEW

  ChatRequest({
    required this.message,
    this.chatHistory,
    this.responseStyle,  // NEW
  });

  Map<String, dynamic> toJson() {
    return {
      'message': message,
      'chat_history': chatHistory?.map((msg) => msg.toJson()).toList(),
      if (responseStyle != null) 'response_style': responseStyle!.name,  // NEW
    };
  }
}

class ChatResponse {
  final String response;
  final DateTime timestamp;

  ChatResponse({
    required this.response,
    required this.timestamp,
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    return ChatResponse(
      response: json['response'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}