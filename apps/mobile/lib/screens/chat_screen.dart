import 'dart:async';

import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/chat.dart';
import '../services/api_service.dart';
import '../services/chats_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.chat,
    this.chatsService = const ChatsService(),
    super.key,
  });

  final ChatSummary chat;
  final ChatsService chatsService;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _pollInterval = Duration(seconds: 15);

  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final Set<String> _messageIds = {};
  Timer? _pollTimer;
  bool _isLoading = true;
  bool _isFetching = false;
  bool _isSending = false;
  String? _initialError;

  @override
  void initState() {
    super.initState();
    unawaited(_fetchMessages(initial: true));
    _pollTimer = Timer.periodic(
      _pollInterval,
      (_) => unawaited(_fetchMessages()),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages({bool initial = false}) async {
    if (_isFetching) return;
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
      // Polling failures intentionally keep already-loaded content visible.
    } finally {
      _isFetching = false;
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
            Expanded(child: Text(peer.login, overflow: TextOverflow.ellipsis)),
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
