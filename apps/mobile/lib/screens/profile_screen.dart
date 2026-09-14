import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../constants.dart';
import '../models/avatar.dart';
import '../services/api_service.dart';
import '../services/avatar_service.dart';
import '../services/friends_service.dart';
import '../services/friend_requests_controller.dart';
import 'notifications_screen.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({
    required this.login,
    required this.onAvatarsChanged,
    required this.onNotificationsChanged,
    required this.onSignOut,
    required this.friendRequests,
    this.friendsService = const FriendsService(),
    super.key,
  });

  final String login;
  final Future<void> Function() onAvatarsChanged;
  final Future<void> Function() onNotificationsChanged;
  final Future<void> Function() onSignOut;
  final FriendRequestsController friendRequests;
  final FriendsService friendsService;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(login, style: Theme.of(context).textTheme.headlineSmall),
        ),
        const SizedBox(height: 20),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: const Text('Set up avatars'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        SetUpAvatarsScreen(onAvatarsChanged: onAvatarsChanged),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Notifications'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NotificationsScreen(
                      friendsService: friendsService,
                      friendRequests: friendRequests,
                      onNotificationsChanged: onNotificationsChanged,
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('profile-sign-out'),
                leading: Icon(
                  Icons.logout,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Sign out',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Sign out?'),
                      content: const Text(
                        'Are you sure you want to sign out of Chatly?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          key: const Key('confirm-sign-out'),
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true) await onSignOut();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SetUpAvatarsScreen extends StatefulWidget {
  const SetUpAvatarsScreen({required this.onAvatarsChanged, super.key});

  final Future<void> Function() onAvatarsChanged;

  @override
  State<SetUpAvatarsScreen> createState() => _SetUpAvatarsScreenState();
}

class _SetUpAvatarsScreenState extends State<SetUpAvatarsScreen> {
  final AvatarService _avatarService = const AvatarService();
  final ImagePicker _imagePicker = ImagePicker();

  late Future<List<Avatar>> _avatars;
  bool _isMutating = false;

  @override
  void initState() {
    super.initState();
    _avatars = _avatarService.getAvatars();
  }

  void _reload() {
    setState(() {
      _avatars = _avatarService.getAvatars();
    });
  }

  Future<void> _addAvatar() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 2048,
      maxHeight: 2048,
    );

    if (image == null || !mounted) return;

    await _runMutation(
      () => _avatarService.uploadAvatar(image),
      successMessage: 'Avatar added',
    );
  }

  Future<void> _selectAvatar(Avatar avatar) async {
    if (avatar.isSelected) return;

    await _runMutation(
      () => _avatarService.selectAvatar(avatar.id),
      successMessage: 'Current avatar updated',
    );
  }

  Future<void> _deleteAvatar(Avatar avatar) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete avatar?'),
        content: const Text('The image will be removed permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !mounted) return;

    await _runMutation(
      () => _avatarService.deleteAvatar(avatar.id),
      successMessage: 'Avatar deleted',
    );
  }

  Future<void> _runMutation(
    Future<Object?> Function() action, {
    required String successMessage,
  }) async {
    setState(() {
      _isMutating = true;
    });

    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
      _reload();
      await widget.onAvatarsChanged();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isMutating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up avatars')),
      body: RefreshIndicator(
        onRefresh: () async {
          _reload();
          await _avatars;
          await widget.onAvatarsChanged();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tap an avatar to make it current.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isMutating ? null : _addAvatar,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Add avatar'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            FutureBuilder<List<Avatar>>(
              future: _avatars,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: _ErrorState(onRetry: _reload),
                  );
                }

                if (!snapshot.hasData) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final avatars = snapshot.data!;
                if (avatars.isEmpty) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('No avatars yet')),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                        ),
                    itemCount: avatars.length,
                    itemBuilder: (context, index) {
                      final avatar = avatars[index];
                      return _AvatarTile(
                        avatar: avatar,
                        disabled: _isMutating,
                        onSelect: () => _selectAvatar(avatar),
                        onDelete: () => _deleteAvatar(avatar),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarTile extends StatelessWidget {
  const _AvatarTile({
    required this.avatar,
    required this.disabled,
    required this.onSelect,
    required this.onDelete,
  });

  final Avatar avatar;
  final bool disabled;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: avatar.isSelected
              ? colorScheme.primary
              : colorScheme.outlineVariant,
          width: avatar.isSelected ? 3 : 1,
        ),
      ),
      child: InkWell(
        onTap: disabled ? null : onSelect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              '${Constants.baseUrl}${avatar.url}',
              headers: ApiService.instance.authorizationHeaders,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(
                color: Color(0xFFE8DEF8),
                child: Icon(Icons.broken_image_outlined, size: 42),
              ),
            ),
            if (avatar.isSelected)
              Positioned(
                left: 8,
                top: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(5),
                    child: Icon(Icons.check, color: Colors.white, size: 18),
                  ),
                ),
              ),
            Positioned(
              right: 4,
              top: 4,
              child: IconButton.filledTonal(
                tooltip: 'Delete avatar',
                onPressed: disabled ? null : onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Could not load avatars'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
