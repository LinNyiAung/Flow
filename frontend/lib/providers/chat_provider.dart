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

  // FIXED: Send chat history BEFORE adding the new user message
  Future<bool> sendMessage(String message) async {
    if (message.trim().isEmpty) return false;

    await _cancelStream();

    _setSendingMessage(true);
    _setError(null);
    _resetStreamingMessage();

    try {
      _setStreaming(true);
      
      // IMPORTANT: Get chat history BEFORE adding the new user message
      final chatHistoryToSend = _messages.length > 10 
          ? _messages.sublist(_messages.length - 10)
          : List<ChatMessage>.from(_messages);
      
      // NOW add user message to UI
      final userMessage = ChatMessage(
        role: MessageRole.user,
        content: message,
        timestamp: DateTime.now(),
      );
      _messages.add(userMessage);
      notifyListeners();
      
      // Create placeholder AI message
      final aiMessageIndex = _messages.length;
      final aiMessage = ChatMessage(
        role: MessageRole.assistant,
        content: '',
        timestamp: DateTime.now(),
      );
      _messages.add(aiMessage);
      notifyListeners();

      // Start streaming with the OLD chat history (before we added the new message)
      final stream = ApiService.streamChatMessage(
        message: message,
        chatHistory: chatHistoryToSend, // Use the history from before we added the message
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
      
      if (_messages.isNotEmpty && _messages.last.role == MessageRole.assistant && _messages.last.content.isEmpty) {
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

  Future<void> refreshAiData() async {
    try {
      await ApiService.refreshAiData();
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