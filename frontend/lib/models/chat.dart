// models/chat.dart

enum MessageRole { user, assistant }

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

  ChatRequest({
    required this.message,
    this.chatHistory,
  });

  Map<String, dynamic> toJson() {
    return {
      'message': message,
      'chat_history': chatHistory?.map((msg) => msg.toJson()).toList(),
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

class FinancialInsights {
  final String insights;
  final DateTime generatedAt;

  FinancialInsights({
    required this.insights,
    required this.generatedAt,
  });

  factory FinancialInsights.fromJson(Map<String, dynamic> json) {
    return FinancialInsights(
      insights: json['insights'],
      generatedAt: DateTime.parse(json['generated_at']),
    );
  }
}