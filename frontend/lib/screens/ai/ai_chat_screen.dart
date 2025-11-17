// screens/ai/ai_chat_screen.dart - Updated with streaming UI and drawer

import 'package:flutter/material.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:math';
import '../../providers/chat_provider.dart';
import '../../models/chat.dart';
import '../../widgets/app_drawer.dart'; // Import the drawer widget

class AiChatScreen extends StatefulWidget {
  @override
  _AiChatScreenState createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late AnimationController _typingAnimationController;

  // Predefined quick suggestions
  final List<String> quickSuggestions = [
    "What's my current balance?",
    "How much did I spend this month?",
    "What are my top spending categories?",
    "Give me money-saving tips",
    "Show me my income vs expenses",
    "How much did I spend on food?",
  ];

  @override
  void initState() {
    super.initState();
    
    // Initialize animation controller for typing indicator
    _typingAnimationController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    
    // Load chat history when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ChatProvider>(context, listen: false).loadChatHistory();
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

  // Auto-scroll during streaming
  void _autoScrollDuringStreaming() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      // Only auto-scroll if user is near the bottom
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
    
    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(), 
      drawerEnableOpenDragGesture: true,  
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.15,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.menu),
          color: Color(0xFF333333),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.smart_toy, color: Colors.white, size: 20),
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Assistant',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                Consumer<ChatProvider>(
                  builder: (context, chatProvider, child) {
                    return Text(
                      chatProvider.isStreaming ? 'Thinking...' : 'Financial advisor',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: chatProvider.isStreaming ? Colors.green[600] : Colors.grey[600],
                      ),
                    );
                  },
                ),
              ],
            ),
            SizedBox(width: 8),
            if (!authProvider.isPremium)
              Icon(Icons.lock, size: 16, color: Color(0xFFFFD700)),
              SizedBox(width: 8),
            if (!authProvider.isPremium)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Color(0xFFFFD700).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Color(0xFFFFD700), width: 1),
                ),
                child: Text(
                  'PREMIUM',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFD700),
                  ),
                ),
              )
          ],
        ),
        actions: [
          // Add stop button during streaming
          Consumer<ChatProvider>(
            builder: (context, chatProvider, child) {
              if (chatProvider.isStreaming) {
                return IconButton(
                  onPressed: () => chatProvider.stopStreaming(),
                  icon: Icon(Icons.stop_circle, color: Colors.red),
                  tooltip: 'Stop response',
                );
              }
              return Container();
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear') {
                _showClearHistoryDialog();
              } 
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.clear_all, size: 20, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Clear History'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Consumer<ChatProvider>(
        builder: (context, chatProvider, child) {
          // Auto-scroll during streaming
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
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading chat history...',
                    style: GoogleFonts.poppins(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Error message
              if (chatProvider.error != null)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12),
                  margin: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          chatProvider.error!,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.red[800],
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: chatProvider.clearError,
                        icon: Icon(Icons.close, color: Colors.red, size: 18),
                      ),
                    ],
                  ),
                ),

              // Chat messages
              Expanded(
                child: chatProvider.messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: chatProvider.messages.length,
                        itemBuilder: (context, index) {
                          final message = chatProvider.messages[index];
                          final isLastMessage = index == chatProvider.messages.length - 1;
                          final isStreamingMessage = isLastMessage && 
                              message.role == MessageRole.assistant && 
                              chatProvider.isStreaming;
                          
                          return _buildMessageBubble(
                            message, 
                            isStreamingMessage: isStreamingMessage,
                          );
                        },
                      ),
              ),

              // Quick suggestions (show only when chat is empty)
              if (chatProvider.messages.isEmpty)
                Container(
                  height: 120,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    itemCount: quickSuggestions.length,
                    itemBuilder: (context, index) {
                      return _buildQuickSuggestion(quickSuggestions[index], chatProvider);
                    },
                  ),
                ),

              // Message input
              _buildMessageInput(chatProvider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
                borderRadius: BorderRadius.circular(40),
              ),
              child: Icon(Icons.smart_toy, color: Colors.white, size: 40),
            ),
            SizedBox(height: 24),
            Text(
              'Hello! I\'m your AI financial assistant',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12),
            Text(
              'I can help you analyze your spending, provide insights, and answer questions about your finances.',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 32),
            Text(
              'Try asking me something like:',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF667eea),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickSuggestion(String suggestion, ChatProvider chatProvider) {
    return Container(
      margin: EdgeInsets.only(right: 12, bottom: 16),
      child: GestureDetector(
        onTap: () => chatProvider.addQuickMessage(suggestion),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Color(0xFF667eea).withOpacity(0.3)),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 4,
              ),
            ],
          ),
          child: Text(
            suggestion,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Color(0xFF667eea),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, {bool isStreamingMessage = false}) {
    final isUser = message.role == MessageRole.user;
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.smart_toy, color: Colors.white, size: 16),
            ),
            SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser ? Color(0xFF667eea) : Colors.grey[100],
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.content,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: isUser ? Colors.white : Color(0xFF333333),
                          height: 1.4,
                        ),
                      ),
                      // Add typing indicator for streaming messages
                      if (isStreamingMessage) ...[
                        SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildTypingIndicator(),
                            SizedBox(width: 8),
                            Text(
                              'AI is typing...',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  DateFormat('HH:mm').format(message.timestamp),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          if (isUser) ...[
            SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFF667eea),
              child: Icon(Icons.person, color: Colors.white, size: 16),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return AnimatedBuilder(
      animation: _typingAnimationController,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final animationValue = (_typingAnimationController.value - delay).clamp(0.0, 1.0);
            final scale = (sin(animationValue * 2 * pi) * 0.5 + 0.5) * 0.5 + 0.5;
            
            return Container(
              margin: EdgeInsets.symmetric(horizontal: 1),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    shape: BoxShape.circle,
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
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: TextField(
                controller: _messageController,
                enabled: !chatProvider.isStreaming, // Disable input during streaming
                decoration: InputDecoration(
                  hintText: chatProvider.isStreaming 
                      ? 'AI is responding...' 
                      : 'Ask me about your finances...',
                  hintStyle: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                style: GoogleFonts.poppins(fontSize: 14),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => chatProvider.isStreaming ? null : _sendMessage(),
              ),
            ),
          ),
          SizedBox(width: 8),
          GestureDetector(
            onTap: (chatProvider.isSendingMessage || chatProvider.isStreaming) ? null : _sendMessage,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: chatProvider.isStreaming 
                      ? [Colors.grey, Colors.grey]
                      : [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: (chatProvider.isSendingMessage || chatProvider.isStreaming)
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  void _showClearHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Clear Chat History',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to clear all chat history? This action cannot be undone.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Provider.of<ChatProvider>(context, listen: false).clearChatHistory();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              'Clear',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  
}