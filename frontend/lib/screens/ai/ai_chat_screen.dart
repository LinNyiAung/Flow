import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/widgets/app_bottom_sheet.dart';
import '../../providers/chat_provider.dart';
import '../../models/chat.dart';
import '../../widgets/app_drawer.dart';

class AiChatScreen extends StatefulWidget {
  @override
  _AiChatScreenState createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen>
    with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late AnimationController _typingAnimationController;

  List<String> _quickSuggestions(AppLocalizations localizations) => [
    localizations.suggestionCurrentBalance,
    localizations.suggestionSpendThisMonth,
    localizations.suggestionTopSpendingCategories,
    localizations.suggestionMoneySavingTips,
    localizations.suggestionIncomeVsExpenses,
    localizations.suggestionSpendOnFood,
  ];

  @override
  void initState() {
    super.initState();

    _typingAnimationController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      // ChatProvider lives at the app root and survives navigation, so a
      // conversation already in memory (e.g. from just before navigating
      // away and back) is the source of truth — re-fetching unconditionally
      // here would overwrite it with whatever the backend has saved, which
      // isn't guaranteed to be caught up yet.
      if (chatProvider.messages.isEmpty) {
        chatProvider.loadChatHistory();
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingAnimationController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final message = _messageController.text.trim();
    if (message.isNotEmpty) {
      _messageController.clear();
      Provider.of<ChatProvider>(context, listen: false).sendMessage(message);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Maps to the mockup's `var(--accent)` token — a lighter mint in dark
  /// mode, distinct from `--primary` (used for filled buttons). Neither
  /// light nor dark [ColorScheme] exposes this role directly, so it's
  /// derived from the theme's own accent constants.
  Color _accentColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? AppTheme.darkAccent : AppTheme.jade;

  void _autoScrollDuringStreaming() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      if (maxScroll - currentScroll < 100) {
        _scrollController.animateTo(
          maxScroll,
          duration: Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(),
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.forum_rounded, size: 20, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localizations.aiAssistant,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Consumer<ChatProvider>(
                    builder: (context, chatProvider, child) {
                      return Text(
                        chatProvider.isStreaming
                            ? localizations.thinking
                            : localizations.financialAdvisor,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: chatProvider.isStreaming ? scheme.primary : scheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Consumer<ChatProvider>(
            builder: (context, chatProvider, child) {
              if (chatProvider.isStreaming) {
                return IconButton(
                  onPressed: () => chatProvider.stopStreaming(),
                  icon: Icon(Icons.stop_circle_rounded, color: scheme.error),
                  tooltip: localizations.stopResponse,
                );
              }
              if (chatProvider.messages.isNotEmpty) {
                return IconButton(
                  onPressed: _showClearChatSheet,
                  icon: const Icon(Icons.delete_sweep_rounded),
                  tooltip: localizations.clearHistory,
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Consumer<ChatProvider>(
        builder: (context, chatProvider, child) => authProvider.isPremium
            ? _buildPremiumBody(chatProvider)
            : _buildLockedBody(chatProvider),
      ),
    );
  }

  // ── Premium ──────────────────────────────────────────────────────

  Widget _buildPremiumBody(ChatProvider chatProvider) {
    final localizations = AppLocalizations.of(context);

    if (chatProvider.isStreaming) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoScrollDuringStreaming();
      });
    }

    if (chatProvider.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(localizations.loadingChatHistory, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
    }

    return Column(
      children: [
        _responseStyleRow(chatProvider),
        if (chatProvider.error != null) _errorBanner(chatProvider),
        Expanded(
          child: chatProvider.messages.isEmpty
              ? _buildEmptyState(chatProvider)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: chatProvider.messages.length,
                  itemBuilder: (context, index) {
                    final message = chatProvider.messages[index];
                    final isLastMessage = index == chatProvider.messages.length - 1;
                    final isStreamingMessage =
                        isLastMessage && message.role == MessageRole.assistant && chatProvider.isStreaming;

                    return _buildMessageBubble(message, isStreamingMessage: isStreamingMessage);
                  },
                ),
        ),
        _buildMessageInput(chatProvider),
      ],
    );
  }

  Widget _responseStyleRow(ChatProvider chatProvider) {
    final scheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);

    Widget chip(ResponseStyle style) {
      final selected = chatProvider.responseStyle == style;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => chatProvider.setResponseStyle(style),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? scheme.primaryContainer : Colors.transparent,
              border: Border.all(color: selected ? scheme.primary : scheme.outline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              style.getDisplayName(context),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              localizations.answers,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            ...ResponseStyle.values.map(chip),
          ],
        ),
      ),
    );
  }

  Widget _errorBanner(ChatProvider chatProvider) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              chatProvider.error!,
              style: TextStyle(fontSize: 14, color: scheme.onErrorContainer),
            ),
          ),
          IconButton(
            onPressed: chatProvider.clearError,
            icon: Icon(Icons.close_rounded, color: scheme.error, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ChatProvider chatProvider) {
    final scheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
            child: Icon(Icons.forum_rounded, size: 32, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 14),
          Text(
            localizations.helloAi,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            localizations.aiChatDes,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant, height: 1.55),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              localizations.tryAskingMeSomething,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 8),
          ..._quickSuggestions(localizations).map((s) => _suggestionRow(s, chatProvider)),
        ],
      ),
    );
  }

  Widget _suggestionRow(String suggestion, ChatProvider chatProvider) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => chatProvider.addQuickMessage(suggestion),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    suggestion,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.north_east_rounded, size: 18, color: _accentColor(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, {bool isStreamingMessage = false}) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.role == MessageRole.user;
    final showBusy = isStreamingMessage && message.content.isEmpty;

    // The mockup renders chat bubbles alone, flush left/right — no avatar
    // circles alongside them (see "AI chat" markup's `sc-for` over
    // `chatMsgs`, lines 1332-1336 of the prototype).
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser ? scheme.primary : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isUser ? 18 : 6),
                      bottomRight: Radius.circular(isUser ? 6 : 18),
                    ),
                  ),
                  child: showBusy
                      ? _busyDots()
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Flexible(
                              child: Text(
                                message.content,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  height: 1.5,
                                  color: isUser ? scheme.onPrimary : scheme.onSurface,
                                ),
                              ),
                            ),
                            if (isStreamingMessage) ...[
                              const SizedBox(width: 3),
                              Container(width: 7, height: 15, color: _accentColor(context)),
                            ],
                          ],
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('HH:mm').format(message.timestamp),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _busyDots() {
    return AnimatedBuilder(
      animation: _typingAnimationController,
      builder: (context, child) {
        final colors = AppTheme.chartRampFor(context);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final animationValue = (_typingAnimationController.value - delay).clamp(0.0, 1.0);
            final scale = (sin(animationValue * 2 * pi) * 0.5 + 0.5) * 0.5 + 0.5;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors[(index + 2) % colors.length],
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildMessageInput(ChatProvider chatProvider) {
    final scheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);
    final busy = chatProvider.isSendingMessage || chatProvider.isStreaming;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? scheme.surface,
          border: Border.all(color: scheme.outline),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                enabled: !chatProvider.isStreaming,
                decoration: InputDecoration(
                  hintText: chatProvider.isStreaming
                      ? localizations.aiIsResponding
                      : localizations.askAboutFinances,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => busy ? null : _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: busy ? null : _sendMessage,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: _accentColor(context), shape: BoxShape.circle),
                child: busy
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(scheme.onPrimary),
                        ),
                      )
                    : Icon(Icons.send_rounded, size: 20, color: scheme.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showClearChatSheet() async {
    final scheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final count = chatProvider.messages.length;

    await showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: scheme.errorContainer, shape: BoxShape.circle),
              child: Icon(Icons.delete_sweep_rounded, color: scheme.error, size: 26),
            ),
            const SizedBox(height: 14),
            Text(localizations.clearThisConversation, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              '$count ${count == 1 ? localizations.chatMessageSingular : localizations.chatMessagePlural} ${localizations.clearChatConsequence}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant, height: 1.6),
            ),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: scheme.error),
              onPressed: () {
                Navigator.pop(sheetContext);
                chatProvider.clearChatHistory();
              },
              child: Text(localizations.clearHistory),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: Text(localizations.keepIt),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Locked (free) ────────────────────────────────────────────────

  Widget _buildLockedBody(ChatProvider chatProvider) {
    final scheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context);
    final messages = chatProvider.messages;

    ChatMessage? lastUser;
    ChatMessage? lastAssistant;
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (lastAssistant == null && m.role == MessageRole.assistant && m.content.trim().isNotEmpty) {
        lastAssistant = m;
      } else if (lastUser == null && m.role == MessageRole.user) {
        lastUser = m;
      }
      if (lastAssistant != null && lastUser != null) break;
    }
    final fallbackQuestion = localizations.fallbackQuestionTighterMonth;
    const fallbackAnswerHead = 'Restaurants. K134,000 this month against K92,000 last month.';
    const fallbackAnswerRest =
        'Nine late-evening orders account for K42,000 of it, and two of them fall on Thursdays after 9pm — the same pattern as August.';

    final questionText = lastUser?.content ?? fallbackQuestion;
    final answerHead = lastAssistant != null ? _firstLine(lastAssistant.content) : fallbackAnswerHead;
    final answerRest = lastAssistant != null ? _restOfContent(lastAssistant.content) : fallbackAnswerRest;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 130),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(alignment: Alignment.centerRight, child: _lockedBubble(questionText, filled: true)),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: _lockedBubble(answerHead, filled: false)),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                    child: _lockedBubble(answerRest, filled: false),
                  ),
                ),
                const Divider(height: 34),
                Text(
                  localizations.assistantAnswersFromRecords,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.4),
                ),
                const SizedBox(height: 6),
                Text(
                  localizations.spendingPaceCategoryComparisons,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant, height: 1.55),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/subscription'),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                  label: Text(localizations.tryOneMonthFree),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    localizations.noCardRequiredCancelAnyTime,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _lockedBubble(String text, {required bool filled}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: filled ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(filled ? 18 : 6),
          bottomRight: Radius.circular(filled ? 6 : 18),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.5,
          color: filled ? scheme.onPrimaryContainer : scheme.onSurface,
        ),
      ),
    );
  }

  String _stripHeadings(String content) =>
      content.replaceAll(RegExp(r'^#+\s*', multiLine: true), '').trim();

  String _firstLine(String content) {
    final clean = _stripHeadings(content);
    final idx = clean.indexOf('\n');
    final firstBlock = idx == -1 ? clean : clean.substring(0, idx);
    final sentenceEnd = firstBlock.indexOf('. ');
    if (sentenceEnd != -1 && sentenceEnd < 140) {
      return firstBlock.substring(0, sentenceEnd + 1);
    }
    return firstBlock.length > 140 ? '${firstBlock.substring(0, 140)}…' : firstBlock;
  }

  String _restOfContent(String content) {
    final clean = _stripHeadings(content);
    final first = _firstLine(content);
    final rest = clean.startsWith(first) ? clean.substring(first.length).trim() : clean;
    return rest.isEmpty ? content : rest;
  }
}
