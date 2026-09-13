import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/chat.dart';
import '../models/contact.dart';
import '../models/friend_request.dart';
import '../services/api_service.dart';
import '../services/chats_service.dart';
import '../services/chat_realtime_service.dart';
import '../services/friends_service.dart';
import 'chat_screen.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    required this.user,
    this.friendsService = const FriendsService(),
    this.chatsService = const ChatsService(),
    this.realtimeService,
    super.key,
  });

  final Contact user;
  final FriendsService friendsService;
  final ChatsService chatsService;
  final ChatRealtime? realtimeService;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  FriendshipState? _friendshipState;
  ChatSummary? _directChat;
  bool _isSending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _error = null;
      _friendshipState = null;
    });

    try {
      final state = await widget.friendsService.getFriendshipStatus(
        widget.user.id,
      );
      ChatSummary? directChat;
      if (state == FriendshipState.friends) {
        try {
          directChat = await widget.chatsService.getDirectChat(widget.user.id);
        } catch (_) {
          // The friend action stays available if checking for a chat fails.
        }
      }
      if (!mounted) return;
      setState(() {
        _friendshipState = state;
        _directChat = directChat;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load friendship status');
    }
  }

  Future<void> _addFriend() async {
    setState(() => _isSending = true);

    try {
      await widget.friendsService.sendRequest(widget.user.id);
      if (!mounted) return;
      setState(() => _friendshipState = FriendshipState.outgoingPending);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Friend request sent')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not send request')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _removeFriend() async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove friend?'),
        content: const Text(
          'This will also delete your shared chat and its history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-remove-friend'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove friend'),
          ),
        ],
      ),
    );
    if (shouldRemove != true || !mounted) return;

    setState(() => _isSending = true);

    try {
      await widget.friendsService.removeFriend(widget.user.id);
      if (!mounted) return;
      setState(() => _friendshipState = FriendshipState.none);
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not remove friend')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _openChat() async {
    setState(() => _isSending = true);
    try {
      final chat =
          _directChat ??
          await widget.chatsService.createDirectChat(widget.user.id);
      if (!mounted) return;
      setState(() => _directChat = chat);
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chat: chat,
            realtimeService:
                widget.realtimeService ?? ChatRealtimeService.instance,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open chat')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User profile')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                key: const Key('user-profile-avatar'),
                radius: 76,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundImage: widget.user.avatarUrl == null
                    ? null
                    : NetworkImage(
                        '${Constants.baseUrl}${widget.user.avatarUrl}',
                        headers: ApiService.instance.authorizationHeaders,
                      ),
                onForegroundImageError: widget.user.avatarUrl == null
                    ? null
                    : (_, _) {},
                child: const Icon(Icons.person, size: 76),
              ),
              const SizedBox(height: 24),
              Text(
                widget.user.login,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 28),
              _buildFriendshipAction(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendshipAction() {
    if (_error != null) {
      return Column(
        children: [
          Text(_error!),
          TextButton(onPressed: _loadStatus, child: const Text('Retry')),
        ],
      );
    }

    final state = _friendshipState;
    if (state == null) return const CircularProgressIndicator();

    return switch (state) {
      FriendshipState.none => FilledButton.icon(
        onPressed: _isSending ? null : _addFriend,
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(_isSending ? 'Sending...' : 'Add friend'),
      ),
      FriendshipState.friends => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            key: const Key('open-chat-button'),
            onPressed: _isSending ? null : _openChat,
            icon: const Icon(Icons.chat),
            label: Text(
              _isSending
                  ? 'Opening chat...'
                  : _directChat == null
                  ? 'Start chat'
                  : 'Go to chat',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('remove-friend-button'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: _isSending ? null : _removeFriend,
            icon: const Icon(Icons.person_remove),
            label: Text(_isSending ? 'Removing...' : 'Remove friend'),
          ),
        ],
      ),
      FriendshipState.outgoingPending => const Chip(
        avatar: Icon(Icons.schedule),
        label: Text('Request sent'),
      ),
      FriendshipState.incomingPending => const Chip(
        avatar: Icon(Icons.notifications),
        label: Text('Friend request received'),
      ),
    };
  }
}
