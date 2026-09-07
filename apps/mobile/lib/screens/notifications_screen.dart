import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/friend_request.dart';
import '../services/api_service.dart';
import '../services/friends_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    required this.onNotificationsChanged,
    this.friendsService = const FriendsService(),
    super.key,
  });

  final Future<void> Function() onNotificationsChanged;
  final FriendsService friendsService;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<FriendRequest>> _requests;
  final Set<String> _processing = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _requests = widget.friendsService.getIncomingRequests();
    });
  }

  Future<void> _respond(FriendRequest request, {required bool accept}) async {
    setState(() => _processing.add(request.friendshipId));

    try {
      if (accept) {
        await widget.friendsService.acceptRequest(request.friendshipId);
      } else {
        await widget.friendsService.rejectRequest(request.friendshipId);
      }
      if (!mounted) return;
      _reload();
      await widget.onNotificationsChanged();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept ? 'Could not accept request' : 'Could not reject request',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _processing.remove(request.friendshipId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: FutureBuilder<List<FriendRequest>>(
        future: _requests,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load notifications'),
                  TextButton(onPressed: _reload, child: const Text('Retry')),
                ],
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final requests = snapshot.data!;
          if (requests.isEmpty) {
            return const Center(child: Text('No notifications'));
          }

          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _requests;
              await widget.onNotificationsChanged();
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: requests.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final request = requests[index];
                final disabled = _processing.contains(request.friendshipId);
                return ListTile(
                  leading: CircleAvatar(
                    foregroundImage: request.user.avatarUrl == null
                        ? null
                        : NetworkImage(
                            '${Constants.baseUrl}${request.user.avatarUrl}',
                            headers: ApiService.instance.authorizationHeaders,
                          ),
                    onForegroundImageError: request.user.avatarUrl == null
                        ? null
                        : (_, _) {},
                    child: const Icon(Icons.person),
                  ),
                  title: Text(request.user.login),
                  subtitle: const Text('Wants to add you as a friend'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Reject',
                        onPressed: disabled
                            ? null
                            : () => _respond(request, accept: false),
                        icon: const Icon(Icons.close),
                      ),
                      IconButton.filled(
                        tooltip: 'Accept',
                        onPressed: disabled
                            ? null
                            : () => _respond(request, accept: true),
                        icon: const Icon(Icons.check),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
