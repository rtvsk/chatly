import 'dart:async';

import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/chat.dart';
import '../services/api_service.dart';
import '../services/chats_service.dart';
import '../services/chat_realtime_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.chat,
    this.chatsService = const ChatsService(),
    this.realtimeService,
    super.key,
  });

  final ChatSummary chat;
  final ChatsService chatsService;
  final ChatRealtime? realtimeService;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final Set<String> _messageIds = {};
  late final ChatRealtime _realtimeService;
  StreamSubscription<ChatMessage>? _messagesSubscription;
  StreamSubscription<TypingChangedEvent>? _typingChangesSubscription;
  StreamSubscription<void>? _connectedSubscription;
  StreamSubscription<Set<String>>? _onlineUserIdsSubscription;
  Timer? _typingInactivityTimer;
  Timer? _peerTypingWatchdog;
  late Set<String> _onlineUserIds;
  bool _isLoading = true;
  bool _isFetching = false;
  bool _catchUpRequested = false;
  bool _isSending = false;
  bool _isTyping = false;
  bool _isPeerTyping = false;
  String? _initialError;

  @override
  void initState() {
    super.initState();
    _realtimeService = widget.realtimeService ?? ChatRealtimeService.instance;
    _messagesSubscription = _realtimeService.messages.listen(
      _onRealtimeMessage,
    );
    _typingChangesSubscription = _realtimeService.typingChanges.listen((event) {
      if (event.userId == widget.chat.peer.id) _onTypingChanged(event);
    });
    _connectedSubscription = _realtimeService.connected.listen(
      (_) => unawaited(_fetchMessages()),
    );
    _onlineUserIds = _realtimeService.onlineUserIds;
    _onlineUserIdsSubscription = _realtimeService.onlineUserIdsChanges.listen((
      onlineUserIds,
    ) {
      if (!mounted) return;
      setState(() {
        _onlineUserIds = onlineUserIds;
        if (!_onlineUserIds.contains(widget.chat.peer.id)) {
          _clearPeerTyping();
        }
      });
    });
    _realtimeService.refreshPresence();
    unawaited(_fetchMessages(initial: true));
  }

  @override
  void dispose() {
    _typingInactivityTimer?.cancel();
    _peerTypingWatchdog?.cancel();
    _stopTyping();
    _messagesSubscription?.cancel();
    _typingChangesSubscription?.cancel();
    _connectedSubscription?.cancel();
    _onlineUserIdsSubscription?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onRealtimeMessage(ChatMessage message) {
    if (!mounted || message.chatId != widget.chat.id) return;

    final added = _appendMessages([message]);
    if (added) {
      setState(() {});
      _scrollToBottom();
    }
  }

  void _onTypingChanged(TypingChangedEvent event) {
    if (!mounted) return;

    if (!event.isTyping || !_onlineUserIds.contains(event.userId)) {
      setState(_clearPeerTyping);
      return;
    }

    _peerTypingWatchdog?.cancel();
    _peerTypingWatchdog = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(_clearPeerTyping);
    });
    if (!_isPeerTyping) setState(() => _isPeerTyping = true);
  }

  void _clearPeerTyping() {
    _peerTypingWatchdog?.cancel();
    _peerTypingWatchdog = null;
    _isPeerTyping = false;
  }

  void _onTextChanged(String value) {
    _typingInactivityTimer?.cancel();
    if (value.trim().isEmpty) {
      _stopTyping();
      return;
    }

    _isTyping = true;
    _realtimeService.setTyping(
      recipientUserId: widget.chat.peer.id,
      isTyping: true,
    );
    _typingInactivityTimer = Timer(const Duration(seconds: 2), _stopTyping);
  }

  void _stopTyping() {
    _typingInactivityTimer?.cancel();
    _typingInactivityTimer = null;
    if (!_isTyping) return;

    _isTyping = false;
    _realtimeService.setTyping(
      recipientUserId: widget.chat.peer.id,
      isTyping: false,
    );
  }

  Future<void> _fetchMessages({bool initial = false}) async {
    if (_isFetching) {
      _catchUpRequested = true;
      return;
    }
    _isFetching = true;

    if (initial && mounted) {
      setState(() {
        _isLoading = true;
        _initialError = null;
      });
    }

    try {
      final incoming = await widget.chatsService.getMessages(
        widget.chat.id,
        after: initial || _messages.isEmpty ? null : _messages.last.id,
      );
      if (!mounted) return;

      final added = _appendMessages(incoming);
      setState(() {
        _isLoading = false;
        _initialError = null;
      });
      if (initial || added) _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      if (initial) {
        setState(() {
          _isLoading = false;
          _initialError = 'Could not load messages';
        });
      }
      // Keep already-loaded content visible when a catch-up request fails.
    } finally {
      _isFetching = false;
      if (_catchUpRequested && mounted) {
        _catchUpRequested = false;
        unawaited(_fetchMessages());
      }
    }
  }

  bool _appendMessages(Iterable<ChatMessage> messages) {
    var added = false;
    for (final message in messages) {
      if (_messageIds.add(message.id)) {
        _messages.add(message);
        added = true;
      }
    }
    if (added) {
      _messages.sort((a, b) {
        final byDate = a.createdAt.compareTo(b.createdAt);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
    }
    return added;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    try {
      final message = await widget.chatsService.sendMessage(
        widget.chat.id,
        text,
      );
      if (!mounted) return;
      _textController.clear();
      _stopTyping();
      final added = _appendMessages([message]);
      setState(() {});
      if (added) _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not send message')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final peer = widget.chat.peer;
    final isPeerOnline = _onlineUserIds.contains(peer.id);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundImage: peer.avatarUrl == null
                  ? null
                  : NetworkImage(
                      '${Constants.baseUrl}${peer.avatarUrl}',
                      headers: ApiService.instance.authorizationHeaders,
                    ),
              onForegroundImageError: peer.avatarUrl == null ? null : (_, _) {},
              child: const Icon(Icons.person, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(peer.login, overflow: TextOverflow.ellipsis),
                  if (isPeerOnline)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          key: const Key('chat-peer-online-indicator'),
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isPeerTyping ? 'typing' : 'Online',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessages()),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_initialError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_initialError!),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => _fetchMessages(initial: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_messages.isEmpty) {
      return const Center(child: Text('No messages yet'));
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) => _MessageBubble(
        message: _messages[index],
        isMine: _messages[index].senderId != widget.chat.peer.id,
      ),
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('chat-message-field'),
              controller: _textController,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onChanged: _onTextChanged,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: 'Message',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            key: const Key('send-message-button'),
            tooltip: 'Send message',
            onPressed: _isSending ? null : _send,
            icon: _isSending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: Key('message-${message.id}'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: isMine ? colors.primary : colors.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isMine ? colors.onPrimary : colors.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}
