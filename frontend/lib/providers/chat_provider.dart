import 'package:flutter/material.dart';
import '../models/chat.dart';
import '../services/api_service.dart';
import 'dart:async';

class ChatProvider with ChangeNotifier {
  static const String stoppedMarker = '[Response stopped by user]';

  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isSendingMessage = false;
  String? _error;

  bool _isStreaming = false;
  String _currentStreamingMessage = '';
  StreamSubscription<String>? _streamSubscription;

  /// Index of the assistant placeholder being streamed into.
  int? _streamingIndex;

  /// Bumped for every new request, stop and reset; callbacks of an older
  /// request are ignored (e.g. the error raised by aborting the connection).
  int _requestId = 0;

  ResponseStyle _responseStyle = ResponseStyle.normal;
  AIProvider _aiProvider = AIProvider.gemini;

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSendingMessage => _isSendingMessage;
  String? get error => _error;
  bool get isStreaming => _isStreaming;
  String get currentStreamingMessage => _currentStreamingMessage;
  ResponseStyle get responseStyle => _responseStyle;
  AIProvider get aiProvider => _aiProvider;

  /// Clears all per-user state (called on logout / user switch).
  void reset() {
    _requestId++;
    _streamSubscription?.cancel();
    _streamSubscription = null;
    ApiService.cancelChatStream();
    _messages = [];
    _isLoading = false;
    _isSendingMessage = false;
    _error = null;
    _isStreaming = false;
    _currentStreamingMessage = '';
    _streamingIndex = null;
    _responseStyle = ResponseStyle.normal;
    _aiProvider = AIProvider.gemini;
    notifyListeners();
  }

  void setAIProvider(AIProvider provider) {
    _aiProvider = provider;
    notifyListeners();
  }

  void setResponseStyle(ResponseStyle style) {
    _responseStyle = style;
    notifyListeners();
  }

  /// Appends a streamed chunk to the in-progress assistant message.
  void _updateStreamingMessage(String chunk) {
    _currentStreamingMessage += chunk;
    final index = _streamingIndex;
    if (index != null && index < _messages.length) {
      final placeholder = _messages[index];
      _messages[index] = ChatMessage(
        role: MessageRole.assistant,
        content: _currentStreamingMessage,
        timestamp: placeholder.timestamp,
      );
    }
    notifyListeners();
  }

  /// Ends the current stream state. Removes the assistant placeholder if
  /// nothing was received, so empty assistant messages never linger.
  void _finishStreaming() {
    final index = _streamingIndex;
    if (index != null &&
        index < _messages.length &&
        _messages[index].role == MessageRole.assistant &&
        _messages[index].content.trim().isEmpty) {
      _messages.removeAt(index);
    }
    _streamingIndex = null;
    _streamSubscription = null;
    _isStreaming = false;
    _isSendingMessage = false;
    _currentStreamingMessage = '';
    notifyListeners();
  }

  Future<bool> sendMessage(String message) async {
    if (message.trim().isEmpty) return false;

    await _abortActiveStream();
    final requestId = ++_requestId;

    _error = null;
    _currentStreamingMessage = '';
    _isSendingMessage = true;
    _isStreaming = true;

    // Never send empty assistant messages (e.g. placeholders of failed or
    // stopped requests) as chat history.
    final history = _messages
        .where((m) => m.content.trim().isNotEmpty)
        .toList();
    final chatHistoryToSend = history.length > 10
        ? history.sublist(history.length - 10)
        : history;

    _messages.add(ChatMessage(
      role: MessageRole.user,
      content: message,
      timestamp: DateTime.now(),
    ));
    _messages.add(ChatMessage(
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
    ));
    _streamingIndex = _messages.length - 1;
    notifyListeners();

    try {
      final stream = ApiService.streamChatMessage(
        message: message,
        chatHistory: chatHistoryToSend,
        responseStyle: _responseStyle,
        aiProvider: _aiProvider,
      );

      _streamSubscription = stream.listen(
        (chunk) {
          if (requestId != _requestId) return;
          _updateStreamingMessage(chunk);
        },
        onError: (Object error) {
          if (requestId != _requestId) return;
          // Surface the server's error frame / HTTP error and drop the
          // empty placeholder (partial text, if any, is kept).
          _error = error.toString().replaceAll('Exception: ', '');
          _finishStreaming();
        },
        onDone: () {
          if (requestId != _requestId) return;
          _finishStreaming();
        },
        cancelOnError: true,
      );
      return true;
    } catch (e) {
      if (requestId == _requestId) {
        _error = e.toString().replaceAll('Exception: ', '');
        _finishStreaming();
      }
      return false;
    }
  }

  /// Aborts the network request and detaches from the current stream.
  Future<void> _abortActiveStream() async {
    _requestId++;
    ApiService.cancelChatStream();
    final sub = _streamSubscription;
    _streamSubscription = null;
    if (sub != null) {
      try {
        await sub.cancel().timeout(const Duration(seconds: 2));
      } catch (_) {
        // Already torn down by closing the client.
      }
    }
  }

  /// Bumped for every history load; only the latest load may clear
  /// [_isLoading].
  int _historyLoadId = 0;

  Future<void> loadChatHistory() async {
    // Don't swap the list out from under an in-progress response.
    if (_isStreaming) return;
    final requestId = _requestId;
    final loadId = ++_historyLoadId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final history = await ApiService.getChatHistory(limit: 50);
      // Reset / new message meanwhile: discard the result, but still end
      // the loading state (below) unless a newer load is running.
      if (requestId == _requestId) {
        _messages = history
            .where((m) => m.content.trim().isNotEmpty)
            .toList();
      }
    } catch (e) {
      if (requestId == _requestId) {
        _error = e.toString().replaceAll('Exception: ', '');
      }
    }
    if (loadId != _historyLoadId) return; // a newer load owns the flag
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> clearChatHistory() async {
    try {
      await _abortActiveStream();
      _streamingIndex = null;
      _isStreaming = false;
      _isSendingMessage = false;
      await ApiService.clearChatHistory();
      _messages.clear();
      _currentStreamingMessage = '';
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshAiData() async {
    try {
      await ApiService.refreshAiData(aiProvider: _aiProvider);
    } catch (e) {
      debugPrint('Error refreshing AI data: $e');
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void addQuickMessage(String message) {
    sendMessage(message);
  }

  /// Stop button: closes the HTTP connection (so the server stops sending
  /// and no more tokens are billed) and marks the partial answer.
  Future<void> stopStreaming() async {
    if (!_isStreaming && _streamSubscription == null) return;
    final index = _streamingIndex;
    final partial = _currentStreamingMessage;

    await _abortActiveStream();

    if (index != null &&
        index < _messages.length &&
        _messages[index].role == MessageRole.assistant) {
      _messages[index] = ChatMessage(
        role: MessageRole.assistant,
        content: partial.trim().isEmpty
            ? stoppedMarker
            : '${partial.trimRight()} $stoppedMarker',
        timestamp: _messages[index].timestamp,
      );
    }
    _streamingIndex = null;
    _isStreaming = false;
    _isSendingMessage = false;
    _currentStreamingMessage = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _requestId++;
    _streamSubscription?.cancel();
    ApiService.cancelChatStream();
    super.dispose();
  }
}
