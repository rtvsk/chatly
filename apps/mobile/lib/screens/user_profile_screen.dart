import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/contact.dart';
import '../models/friend_request.dart';
import '../services/api_service.dart';
import '../services/friends_service.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    required this.user,
    this.friendsService = const FriendsService(),
    super.key,
  });

  final Contact user;
  final FriendsService friendsService;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  FriendshipState? _friendshipState;
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
      if (!mounted) return;
      setState(() => _friendshipState = state);
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
      FriendshipState.friends => const Chip(
        avatar: Icon(Icons.check),
        label: Text('Friends'),
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
