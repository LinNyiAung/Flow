// providers/chat_provider.dart - Updated with streaming support

import 'package:flutter/material.dart';
import '../models/chat.dart';
import '../services/api_service.dart';
import 'dart:async';

class ChatProvider with ChangeNotifier {
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isSendingMessage = false;
  String? _error;
  FinancialInsights? _insights;
  bool _isLoadingInsights = false;
  
  // Add streaming-specific state
  bool _isStreaming = false;
  String _currentStreamingMessage = '';
  StreamSubscription? _streamSubscription;

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSendingMessage => _isSendingMessage;
  String? get error => _error;
  FinancialInsights? get insights => _insights;
  bool get isLoadingInsights => _isLoadingInsights;
  bool get isStreaming => _isStreaming;
  String get currentStreamingMessage => _currentStreamingMessage;

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setSendingMessage(bool sending) {
    _isSendingMessage = sending;
    notifyListeners();
  }

  void _setLoadingInsights(bool loading) {
    _isLoadingInsights = loading;
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

  // Updated sendMessage method with streaming
  Future<bool> sendMessage(String message) async {
    if (message.trim().isEmpty) return false;

    // Cancel any existing stream
    await _cancelStream();

    _setSendingMessage(true);
    _setError(null);
    _resetStreamingMessage();

    // Add user message to the chat immediately
    final userMessage = ChatMessage(
      role: MessageRole.user,
      content: message,
      timestamp: DateTime.now(),
    );
    _messages.add(userMessage);
    notifyListeners();

    try {
      _setStreaming(true);
      
      // Create a placeholder AI message that will be updated as we stream
      final aiMessageIndex = _messages.length;
      final aiMessage = ChatMessage(
        role: MessageRole.assistant,
        content: '', // Start empty
        timestamp: DateTime.now(),
      );
      _messages.add(aiMessage);
      notifyListeners();

      // Start streaming
      final stream = ApiService.streamChatMessage(
        message: message,
        chatHistory: _messages.length > 12 
            ? _messages.sublist(_messages.length - 12, _messages.length - 1) // Exclude the empty AI message we just added
            : _messages.sublist(0, _messages.length - 1),
      );

      String fullResponse = '';
      
      _streamSubscription = stream.listen(
        (chunk) {
          fullResponse += chunk;
          
          // Update the AI message in place
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
          
          // Remove the empty AI message on error
          if (aiMessageIndex < _messages.length) {
            _messages.removeAt(aiMessageIndex);
            notifyListeners();
          }
        },
        onDone: () {
          _setStreaming(false);
          _setSendingMessage(false);
          _resetStreamingMessage();
          
          // Ensure the final message is properly set
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
      
      // Remove the empty AI message if there was an error
      if (_messages.isNotEmpty && _messages.last.role == MessageRole.assistant && _messages.last.content.isEmpty) {
        _messages.removeLast();
        notifyListeners();
      }
      
      return false;
    }
  }

  // Helper method to cancel streaming
  Future<void> _cancelStream() async {
    if (_streamSubscription != null) {
      await _streamSubscription!.cancel();
      _streamSubscription = null;
      _setStreaming(false);
      _resetStreamingMessage();
    }
  }

  // Load chat history from server
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

  // Clear chat history
  Future<bool> clearChatHistory() async {
    try {
      await _cancelStream(); // Cancel any ongoing stream
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

  // Get financial insights
  Future<void> getFinancialInsights() async {
    _setLoadingInsights(true);
    _setError(null);

    try {
      _insights = await ApiService.getFinancialInsights();
      _setLoadingInsights(false);
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      _setLoadingInsights(false);
    }
  }

  // Refresh AI data (call this after adding/updating transactions)
  Future<void> refreshAiData() async {
    try {
      await ApiService.refreshAiData();
    } catch (e) {
      print('Error refreshing AI data: $e');
    }
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Add a quick suggestion message
  void addQuickMessage(String message) {
    sendMessage(message);
  }

  // Stop current streaming (for user-initiated cancellation)
  Future<void> stopStreaming() async {
    await _cancelStream();
    _setSendingMessage(false);
    
    // Complete the current message if there's partial content
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