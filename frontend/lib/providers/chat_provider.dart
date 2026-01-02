import 'package:flutter/material.dart';
import '../models/chat.dart';
import '../services/api_service.dart';
import 'dart:async';

class ChatProvider with ChangeNotifier {
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isSendingMessage = false;
  String? _error;

  bool _isStreaming = false;
  String _currentStreamingMessage = '';
  StreamSubscription? _streamSubscription;

  // NEW: Response style state
  ResponseStyle _responseStyle = ResponseStyle.normal;

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSendingMessage => _isSendingMessage;
  String? get error => _error;
  bool get isStreaming => _isStreaming;
  String get currentStreamingMessage => _currentStreamingMessage;
  ResponseStyle get responseStyle => _responseStyle; // NEW

  // NEW: AI Provider state
  AIProvider _aiProvider = AIProvider.openai;

  // NEW: Getter
  AIProvider get aiProvider => _aiProvider;

  // NEW: Set AI provider
  void setAIProvider(AIProvider provider) {
    _aiProvider = provider;
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setSendingMessage(bool sending) {
    _isSendingMessage = sending;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  void _setStreaming(bool streaming) {
    _isStreaming = streaming;
    notifyListeners();
  }

  void _updateStreamingMessage(String chunk) {
    _currentStreamingMessage += chunk;
    notifyListeners();
  }

  void _resetStreamingMessage() {
    _currentStreamingMessage = '';
    notifyListeners();
  }

  // NEW: Set response style
  void setResponseStyle(ResponseStyle style) {
    _responseStyle = style;
    notifyListeners();
  }

  Future<bool> sendMessage(String message) async {
    if (message.trim().isEmpty) return false;

    await _cancelStream();

    _setSendingMessage(true);
    _setError(null);
    _resetStreamingMessage();

    try {
      _setStreaming(true);

      final chatHistoryToSend = _messages.length > 10
          ? _messages.sublist(_messages.length - 10)
          : List<ChatMessage>.from(_messages);

      final userMessage = ChatMessage(
        role: MessageRole.user,
        content: message,
        timestamp: DateTime.now(),
      );
      _messages.add(userMessage);
      notifyListeners();

      final aiMessageIndex = _messages.length;
      final aiMessage = ChatMessage(
        role: MessageRole.assistant,
        content: '',
        timestamp: DateTime.now(),
      );
      _messages.add(aiMessage);
      notifyListeners();

      // NEW: Pass AI provider to API
      final stream = ApiService.streamChatMessage(
        message: message,
        chatHistory: chatHistoryToSend,
        responseStyle: _responseStyle,
        aiProvider: _aiProvider, // NEW
      );

      String fullResponse = '';

      _streamSubscription = stream.listen(
        (chunk) {
          fullResponse += chunk;

          _messages[aiMessageIndex] = ChatMessage(
            role: MessageRole.assistant,
            content: fullResponse,
            timestamp: aiMessage.timestamp,
          );
          notifyListeners();
        },
        onError: (error) {
          _setError(error.toString().replaceAll('Exception: ', ''));
          _setStreaming(false);
          _setSendingMessage(false);

          if (aiMessageIndex < _messages.length) {
            _messages.removeAt(aiMessageIndex);
            notifyListeners();
          }
        },
        onDone: () {
          _setStreaming(false);
          _setSendingMessage(false);
          _resetStreamingMessage();

          if (aiMessageIndex < _messages.length && fullResponse.isNotEmpty) {
            _messages[aiMessageIndex] = ChatMessage(
              role: MessageRole.assistant,
              content: fullResponse,
              timestamp: aiMessage.timestamp,
            );
            notifyListeners();
          }
        },
      );

      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setStreaming(false);
      _setSendingMessage(false);
      _resetStreamingMessage();

      if (_messages.isNotEmpty &&
          _messages.last.role == MessageRole.assistant &&
          _messages.last.content.isEmpty) {
        _messages.removeLast();
        notifyListeners();
      }

      return false;
    }
  }

  Future<void> _cancelStream() async {
    if (_streamSubscription != null) {
      await _streamSubscription!.cancel();
      _streamSubscription = null;
      _setStreaming(false);
      _resetStreamingMessage();
    }
  }

  Future<void> loadChatHistory() async {
    _setLoading(true);
    _setError(null);

    try {
      _messages = await ApiService.getChatHistory(limit: 50);
      _setLoading(false);
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoading(false);
    }
  }

  Future<bool> clearChatHistory() async {
    try {
      await _cancelStream();
      await ApiService.clearChatHistory();
      _messages.clear();
      _resetStreamingMessage();
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      return false;
    }
  }

  Future<void> refreshAiData() async {
    try {
      await ApiService.refreshAiData(
        aiProvider: _aiProvider,
      ); // NEW: pass provider
    } catch (e) {
      print('Error refreshing AI data: $e');
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void addQuickMessage(String message) {
    sendMessage(message);
  }

  Future<void> stopStreaming() async {
    await _cancelStream();
    _setSendingMessage(false);

    if (_currentStreamingMessage.isNotEmpty && _messages.isNotEmpty) {
      final lastMessage = _messages.last;
      if (lastMessage.role == MessageRole.assistant) {
        _messages[_messages.length - 1] = ChatMessage(
          role: MessageRole.assistant,
          content: lastMessage.content + ' [Response stopped by user]',
          timestamp: lastMessage.timestamp,
        );
        notifyListeners();
      }
    }
    _resetStreamingMessage();
  }

  @override
  void dispose() {
    _cancelStream();
    super.dispose();
  }
}
