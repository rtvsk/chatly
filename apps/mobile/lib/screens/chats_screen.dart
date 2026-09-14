import 'dart:async';

import 'package:chatly/services/api_service.dart';
import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/avatar.dart';
import '../models/chat.dart';
import '../models/contact.dart';
import '../services/avatar_service.dart';
import '../services/chat_realtime_service.dart';
import '../services/chats_service.dart';
import '../services/contacts_service.dart';
import '../services/friend_requests_controller.dart';
import '../services/friends_service.dart';
import '../storage/token_storage.dart';
import '../widgets/chatly_bottom_navigation_bar.dart';
import './profile_screen.dart';
import './signin_screen.dart';
import './chat_screen.dart';
import './user_profile_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({
    super.key,
    this.realtimeService,
    this.contactsService = const ContactsService(),
    this.chatsService = const ChatsService(),
    this.friendsService = const FriendsService(),
    this.avatarService = const AvatarService(),
    this.userLoginLoader,
    this.sessionClearer,
  });

  final ChatRealtime? realtimeService;
  final ContactsService contactsService;
  final ChatsService chatsService;
  final FriendsService friendsService;
  final AvatarService avatarService;
  final Future<String?> Function()? userLoginLoader;
  final Future<void> Function()? sessionClearer;
  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> with WidgetsBindingObserver {
  late final FriendsService _friendsService;
  final GlobalKey<_ContactsTabState> _contactsKey = GlobalKey();
  final GlobalKey<_ChatsTabState> _chatsKey = GlobalKey();
  late final ChatRealtime _realtimeService;
  late final FriendRequestsController _friendRequests;
  StreamSubscription<void>? _connectedSubscription;
  StreamSubscription<FriendshipChangedEvent>? _friendshipChangesSubscription;
  String? login;
  Avatar? currentAvatar;
  int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _realtimeService = widget.realtimeService ?? ChatRealtimeService.instance;
    _friendsService = widget.friendsService;
    _friendRequests = FriendRequestsController(friendsService: _friendsService);
    _connectedSubscription = _realtimeService.connected.listen(
      (_) => unawaited(_syncFriendships()),
    );
    _friendshipChangesSubscription = _realtimeService.friendshipChanges.listen(
      (event) => unawaited(_onFriendshipChanged(event)),
    );
    unawaited(_realtimeService.connect());
    _loadLogin();
    unawaited(_friendRequests.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectedSubscription?.cancel();
    _friendshipChangesSubscription?.cancel();
    _friendRequests.dispose();
    _realtimeService.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_realtimeService.connect());
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _realtimeService.disconnect();
    }
  }

  Future<void> _loadLogin() async {
    final savedLogin =
        await (widget.userLoginLoader ?? TokenStorage.instance.getUserLogin)
            .call();

    if (!mounted) return;

    final selectedAvatar = await _getCurrentAvatar();

    setState(() {
      login = savedLogin;
      currentAvatar = selectedAvatar;
    });
  }

  Future<Avatar?> _getCurrentAvatar() async {
    try {
      final avatars = await widget.avatarService.getAvatars();

      for (final avatar in avatars) {
        if (avatar.isSelected) return avatar;
      }
    } catch (_) {
      // The rest of the authenticated screen remains usable without an avatar.
    }

    return null;
  }

  Future<void> _refreshCurrentAvatar() async {
    final selectedAvatar = await _getCurrentAvatar();

    if (!mounted) return;

    setState(() {
      currentAvatar = selectedAvatar;
    });
  }

  Future<void> _refreshFriendshipLists() async {
    await _refreshContactsAndChats();
  }

  Future<void> _syncFriendships() async {
    await Future.wait([_friendRequests.refresh(), _refreshContactsAndChats()]);
  }

  Future<void> _onFriendshipChanged(FriendshipChangedEvent event) async {
    await _friendRequests.refresh();
    if (event.type == FriendshipChangeType.requestAccepted ||
        event.type == FriendshipChangeType.friendRemoved) {
      await _refreshContactsAndChats();
    }
  }

  Future<void> _refreshContactsAndChats() async {
    await _contactsKey.currentState?._loadContacts(refreshPresence: false);
    await _chatsKey.currentState?._loadChats();
    _realtimeService.refreshPresence();
  }

  Future<void> _logout() async {
    _realtimeService.disconnect();
    await (widget.sessionClearer ?? TokenStorage.instance.clearSession).call();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SigninScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final userLogin = login ?? 'Loading...';

    final pages = [
      ContactsTab(
        key: _contactsKey,
        contactsService: widget.contactsService,
        friendsService: _friendsService,
        realtimeService: _realtimeService,
      ),
      ChatsTab(
        key: _chatsKey,
        chatsService: widget.chatsService,
        realtimeService: _realtimeService,
      ),
      ProfileTab(
        login: userLogin,
        friendsService: _friendsService,
        friendRequests: _friendRequests,
        onAvatarsChanged: _refreshCurrentAvatar,
        onNotificationsChanged: _refreshFriendshipLists,
        onSignOut: _logout,
      ),
    ];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: false,
            // expandedHeight: 160,
            title: Row(
              children: [
                if (currentAvatar != null) ...[
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    foregroundImage: NetworkImage(
                      '${Constants.baseUrl}${currentAvatar!.url}',
                      headers: ApiService.instance.authorizationHeaders,
                    ),
                    onForegroundImageError: (_, _) {},
                    child: const Icon(Icons.person, size: 20),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(userLogin, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            // flexibleSpace: LayoutBuilder(
            //   builder: (context, constraints) {
            //     final collapsed =
            //         constraints.biggest.height <= kToolbarHeight + 40;

            //     return FlexibleSpaceBar(
            //       centerTitle: true,
            //       title: collapsed ? null : Text(userLogin),
            //       background: SafeArea(
            //         child: Padding(
            //           padding: const EdgeInsets.only(top: 48),
            //           child: Align(
            //             alignment: Alignment.topCenter,
            //             child: Column(
            //               mainAxisSize: MainAxisSize.min,
            //               children: const [
            //                 CircleAvatar(
            //                   radius: 34,
            //                   child: Icon(Icons.person, size: 38),
            //                 ),
            //               ],
            //             ),
            //           ),
            //         ),
            //       ),
            //     );
            //   },
            // ),
          ),

          SliverFillRemaining(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: IndexedStack(index: currentIndex, children: pages),
            ),
          ),
        ],
      ),

      bottomNavigationBar: ListenableBuilder(
        listenable: _friendRequests,
        builder: (context, _) => ChatlyBottomNavigationBar(
          selectedIndex: currentIndex,
          profileBadgeCount: _friendRequests.requests.length,
          onDestinationSelected: (index) {
            setState(() {
              currentIndex = index;
            });
            if (index == 0) {
              unawaited(
                _contactsKey.currentState?._loadContacts() ??
                    Future<void>.value(),
              );
            }
            if (index == 1) {
              unawaited(
                _chatsKey.currentState?._loadChats() ?? Future<void>.value(),
              );
            }
          },
        ),
      ),
    );
  }
}

class ContactsTab extends StatefulWidget {
  const ContactsTab({
    super.key,
    this.contactsService = const ContactsService(),
    this.friendsService = const FriendsService(),
    this.realtimeService,
  });

  final ContactsService contactsService;
  final FriendsService friendsService;
  final ChatRealtime? realtimeService;

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  static const _searchDelay = Duration(milliseconds: 400);

  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  late final ChatRealtime _realtimeService;
  StreamSubscription<Set<String>>? _onlineUserIdsSubscription;
  late Set<String> _onlineUserIds;
  List<Contact> _contacts = const [];
  List<Contact> _searchResults = const [];
  bool _isLoadingContacts = true;
  bool _isSearching = false;
  bool _isSearchActive = false;
  String? _contactsError;
  String? _searchError;
  int _searchRequestId = 0;

  @override
  void initState() {
    super.initState();
    _realtimeService = widget.realtimeService ?? ChatRealtimeService.instance;
    _onlineUserIds = _realtimeService.onlineUserIds;
    _onlineUserIdsSubscription = _realtimeService.onlineUserIdsChanges.listen((
      onlineUserIds,
    ) {
      if (mounted) setState(() => _onlineUserIds = onlineUserIds);
    });
    _loadContacts();
  }

  Future<void> _loadContacts({bool refreshPresence = true}) async {
    setState(() {
      _isLoadingContacts = true;
      _contactsError = null;
    });

    try {
      final contacts = await widget.contactsService.getFriends();
      if (!mounted) return;

      setState(() {
        _contacts = contacts;
        _isLoadingContacts = false;
      });
      if (refreshPresence) _realtimeService.refreshPresence();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _contactsError = 'Failed to load contacts';
        _isLoadingContacts = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    _searchDebounce?.cancel();
    final requestId = ++_searchRequestId;

    if (query.length < 3) {
      setState(() {
        _isSearchActive = false;
        _isSearching = false;
        _searchResults = const [];
        _searchError = null;
      });
      return;
    }

    setState(() {
      _isSearchActive = true;
      _isSearching = true;
      _searchError = null;
    });

    _searchDebounce = Timer(_searchDelay, () => _search(query, requestId));
  }

  Future<void> _search(String query, int requestId) async {
    try {
      final results = await widget.contactsService.searchUsers(query);
      if (!mounted || requestId != _searchRequestId) return;

      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted || requestId != _searchRequestId) return;

      setState(() {
        _searchError = 'Search failed';
        _isSearching = false;
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _onlineUserIdsSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          key: const Key('contacts-search-field'),
          controller: _searchController,
          onChanged: _onSearchChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search by login',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: _clearSearch,
                    icon: const Icon(Icons.clear),
                  ),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildContent() {
    if (_isSearchActive) {
      if (_isSearching) {
        return const Center(child: CircularProgressIndicator());
      }

      if (_searchError != null) {
        return Center(child: Text(_searchError!));
      }

      if (_searchResults.isEmpty) {
        return const Center(child: Text('No users found'));
      }

      return _buildContactsList(_searchResults);
    }

    if (_isLoadingContacts) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_contactsError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_contactsError!),
            const SizedBox(height: 8),
            FilledButton(onPressed: _loadContacts, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_contacts.isEmpty) {
      return const Center(child: Text('No contacts'));
    }

    return _buildContactsList(_contacts);
  }

  Widget _buildContactsList(List<Contact> contacts) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: contacts.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final contact = contacts[index];
        final isOnline = _onlineUserIds.contains(contact.id);
        return ListTile(
          leading: CircleAvatar(
            key: Key('contact-avatar-${contact.id}'),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            foregroundImage: contact.avatarUrl == null
                ? null
                : NetworkImage(
                    '${Constants.baseUrl}${contact.avatarUrl}',
                    headers: ApiService.instance.authorizationHeaders,
                  ),
            onForegroundImageError: contact.avatarUrl == null
                ? null
                : (_, _) {},
            child: const Icon(Icons.person),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(contact.login, overflow: TextOverflow.ellipsis),
              ),
              if (isOnline) ...[
                const SizedBox(width: 6),
                Container(
                  key: Key('contact-online-indicator-${contact.id}'),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
          onTap: () async {
            final wasRemoved = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => UserProfileScreen(
                  user: contact,
                  friendsService: widget.friendsService,
                  realtimeService: _realtimeService,
                ),
              ),
            );
            if (wasRemoved == true && mounted) {
              await _loadContacts();
            }
          },
        );
      },
    );
  }
}

class ChatsTab extends StatefulWidget {
  const ChatsTab({
    super.key,
    this.chatsService = const ChatsService(),
    this.realtimeService,
  });

  final ChatsService chatsService;
  final ChatRealtime? realtimeService;

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  List<ChatSummary> _chats = const [];
  bool _isLoading = true;
  String? _error;
  late final ChatRealtime _realtimeService;
  StreamSubscription<ChatMessage>? _messagesSubscription;

  @override
  void initState() {
    super.initState();
    _realtimeService = widget.realtimeService ?? ChatRealtimeService.instance;
    _messagesSubscription = _realtimeService.messages.listen(
      (_) => unawaited(_loadChats()),
    );
    _loadChats();
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadChats() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final chats = await widget.chatsService.getChats();
      if (!mounted) return;
      setState(() {
        _chats = chats;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not load chats';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 8),
            FilledButton(onPressed: _loadChats, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_chats.isEmpty) return const Center(child: Text('No chats yet'));

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _chats.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final chat = _chats[index];
        final peer = chat.peer;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            foregroundImage: peer.avatarUrl == null
                ? null
                : NetworkImage(
                    '${Constants.baseUrl}${peer.avatarUrl}',
                    headers: ApiService.instance.authorizationHeaders,
                  ),
            onForegroundImageError: peer.avatarUrl == null ? null : (_, _) {},
            child: const Icon(Icons.person),
          ),
          title: Text(peer.login),
          subtitle: Text(
            chat.lastMessage?.text ?? 'No messages yet',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () async {
            await Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) =>
                    ChatScreen(chat: chat, realtimeService: _realtimeService),
              ),
            );
            if (mounted) await _loadChats();
          },
        );
      },
    );
  }
}
