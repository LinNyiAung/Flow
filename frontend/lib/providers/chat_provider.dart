import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat.dart';
import '../services/api_service.dart';
import 'dart:async';

/// Starts the streamed answer to one chat message ([ApiService.streamChatMessage]).
typedef ChatStreamer = Stream<String> Function({
  required String message,
  List<ChatMessage>? chatHistory,
  ResponseStyle? responseStyle,
  ChatMode mode,
  void Function(ChatStreamMeta meta)? onMeta,
});

class ChatProvider with ChangeNotifier {
  static const String stoppedMarker = '[Response stopped by user]';

  /// Shared-preferences key of the Standard / Advanced choice.
  static const String modePrefsKey = 'chat_mode';

  /// Where answers come from; the real API unless a test supplies its own.
  final ChatStreamer _streamer;

  ChatProvider({ChatStreamer? streamer})
      : _streamer = streamer ?? ApiService.streamChatMessage;

  /// The Standard / Advanced choice (Pro only), remembered on the device.
  ChatMode _mode = ChatMode.standard;

  /// The signed-in user can use Advanced (Pro, and the owner left it in the
  /// plan). Set by the app root from the plan; until then every message is
  /// sent as Standard.
  bool _advancedAvailable = false;

  /// The last Advanced message was answered as Standard because the Advanced
  /// allowance is used up; the screen explains it (with the reset date).
  bool _advancedUsedUp = false;

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

  /// The plan refused the last message (locked, used up, monthly AI limit).
  /// The screen shows the limit sheet for it once, via [takePlanLimit].
  PlanLimitException? _planLimit;

  /// The question the plan refused, waiting to go back into the input field
  /// (see [takeRejectedQuestion]).
  String? _rejectedQuestion;

  /// Returns the pending plan refusal, if any, and clears it.
  PlanLimitException? takePlanLimit() {
    final limit = _planLimit;
    _planLimit = null;
    return limit;
  }

  /// Returns the text of the question the plan just refused, if any, and
  /// clears it. The bubble is gone, so the screen puts the text back into the
  /// input field to send later.
  String? takeRejectedQuestion() {
    final question = _rejectedQuestion;
    _rejectedQuestion = null;
    return question;
  }

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSendingMessage => _isSendingMessage;
  String? get error => _error;
  bool get isStreaming => _isStreaming;
  String get currentStreamingMessage => _currentStreamingMessage;
  ResponseStyle get responseStyle => _responseStyle;

  /// Whether the Standard / Advanced switch is offered (Pro).
  bool get advancedAvailable => _advancedAvailable;

  /// The model messages are sent with: Advanced only when the plan allows it.
  ChatMode get mode => _advancedAvailable ? _mode : ChatMode.standard;

  /// The last Advanced message fell back to Standard (Advanced used up).
  bool get advancedUsedUp => _advancedUsedUp;

  /// Called by the app root when the plan changes.
  void setAdvancedAvailable(bool available) {
    if (available == _advancedAvailable) return;
    _advancedAvailable = available;
    notifyListeners();
  }

  /// Reads the remembered Standard / Advanced choice.
  Future<void> loadMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = ChatMode.fromName(prefs.getString(modePrefsKey));
      if (saved != _mode) {
        _mode = saved;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Could not read the chat mode: $e');
    }
  }

  Future<void> setMode(ChatMode mode) async {
    _advancedUsedUp = false;
    if (mode != _mode) _mode = mode;
    notifyListeners();
    await _saveMode();
  }

  Future<void> _saveMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(modePrefsKey, _mode.name);
    } catch (e) {
      debugPrint('Could not save the chat mode: $e');
    }
  }

  void dismissAdvancedNote() {
    if (!_advancedUsedUp) return;
    _advancedUsedUp = false;
    notifyListeners();
  }

  /// The first frame of a stream says which model answered. An Advanced
  /// message answered by Standard because Advanced is used up flips the
  /// switch back to Standard and raises the note.
  void _onStreamMeta(ChatStreamMeta meta, ChatMode requested) {
    if (requested == ChatMode.advanced &&
        meta.modeUsed == ChatMode.standard &&
        meta.advancedExhausted) {
      _mode = ChatMode.standard;
      _advancedUsedUp = true;
      notifyListeners();
      unawaited(_saveMode());
    }
  }

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
    _planLimit = null;
    _rejectedQuestion = null;
    _responseStyle = ResponseStyle.normal;
    _mode = ChatMode.standard; // read again from the device for the next user
    _advancedAvailable = false;
    _advancedUsedUp = false;
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
    _advancedUsedUp = false;
    _currentStreamingMessage = '';
    _isSendingMessage = true;
    _isStreaming = true;
    final requestedMode = mode;

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
      final stream = _streamer(
        message: message,
        chatHistory: chatHistoryToSend,
        responseStyle: _responseStyle,
        mode: requestedMode,
        onMeta: (meta) {
          if (requestId != _requestId) return;
          _onStreamMeta(meta, requestedMode);
        },
      );

      _streamSubscription = stream.listen(
        (chunk) {
          if (requestId != _requestId) return;
          _updateStreamingMessage(chunk);
        },
        onError: (Object error) {
          if (requestId != _requestId) return;
          if (error is PlanLimitException) {
            // Refused before anything was answered: nothing was used, so the
            // question leaves the conversation (its text goes back into the
            // input field) and the limit sheet explains.
            _planLimit = error;
            _dropRejectedQuestion();
          } else {
            // Surface the server's error frame / HTTP error and drop the
            // empty placeholder (partial text, if any, is kept).
            _error = error.toString().replaceAll('Exception: ', '');
          }
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

  /// Removes the question and the empty answer placeholder just added by
  /// [sendMessage] (a plan refusal means the message was never processed) and
  /// keeps the question's text in [takeRejectedQuestion].
  void _dropRejectedQuestion() {
    final index = _streamingIndex;
    if (index == null ||
        index < 1 ||
        index >= _messages.length ||
        _messages[index].role != MessageRole.assistant ||
        _messages[index].content.isNotEmpty ||
        _messages[index - 1].role != MessageRole.user) {
      return;
    }
    _rejectedQuestion = _messages[index - 1].content;
    _messages.removeRange(index - 1, index + 1);
    _streamingIndex = null;
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
      await ApiService.refreshAiData();
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
