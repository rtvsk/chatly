import 'dart:async';

import 'package:chatly/services/api_service.dart';
import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/avatar.dart';
import '../models/contact.dart';
import '../services/avatar_service.dart';
import '../services/contacts_service.dart';
import '../services/friends_service.dart';
import '../storage/token_storage.dart';
import '../widgets/chatly_bottom_navigation_bar.dart';
import './profile_screen.dart';
import './signup_screen.dart';
import './user_profile_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});
  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final FriendsService _friendsService = const FriendsService();
  final GlobalKey<_ContactsTabState> _contactsKey = GlobalKey();
  Timer? _notificationsTimer;
  String? login;
  Avatar? currentAvatar;
  int currentIndex = 0;
  int notificationCount = 0;

  @override
  void initState() {
    super.initState();
    _loadLogin();
    _refreshNotifications();
    _notificationsTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshNotifications(),
    );
  }

  @override
  void dispose() {
    _notificationsTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLogin() async {
    final savedLogin = await TokenStorage.instance.getUserLogin();

    if (!mounted) return;

    await ApiService.instance.get('/chats');
    final selectedAvatar = await _getCurrentAvatar();

    setState(() {
      login = savedLogin;
      currentAvatar = selectedAvatar;
    });
  }

  Future<Avatar?> _getCurrentAvatar() async {
    try {
      final avatars = await const AvatarService().getAvatars();

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

  Future<void> _refreshNotifications() async {
    try {
      final requests = await _friendsService.getIncomingRequests();
      if (!mounted) return;
      setState(() => notificationCount = requests.length);
    } catch (_) {
      // Keep the authenticated screen usable when notifications fail to load.
    }
  }

  Future<void> _refreshFriendships() async {
    await Future.wait([
      _refreshNotifications(),
      _contactsKey.currentState?._loadContacts() ?? Future<void>.value(),
    ]);
  }

  Future<void> _logout() async {
    await TokenStorage.instance.clearSession();

    if (!mounted) return;

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const SignupScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final userLogin = login ?? 'Loading...';

    final pages = [
      ContactsTab(key: _contactsKey),
      const ChatsTab(),
      ProfileTab(
        login: userLogin,
        onAvatarsChanged: _refreshCurrentAvatar,
        onNotificationsChanged: _refreshFriendships,
      ),
    ];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
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
            actions: [
              IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
            ],
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

      bottomNavigationBar: ChatlyBottomNavigationBar(
        selectedIndex: currentIndex,
        profileBadgeCount: notificationCount,
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
          if (index == 2) unawaited(_refreshNotifications());
        },
      ),
    );
  }
}

class ContactsTab extends StatefulWidget {
  const ContactsTab({
    super.key,
    this.contactsService = const ContactsService(),
    this.friendsService = const FriendsService(),
  });

  final ContactsService contactsService;
  final FriendsService friendsService;

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  static const _searchDelay = Duration(milliseconds: 400);

  final _searchController = TextEditingController();
  Timer? _searchDebounce;
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
    _loadContacts();
  }

  Future<void> _loadContacts() async {
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
          title: Text(contact.login),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => UserProfileScreen(
                user: contact,
                friendsService: widget.friendsService,
              ),
            ),
          ),
        );
      },
    );
  }
}

class ChatsTab extends StatelessWidget {
  const ChatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: 30,
      itemBuilder: (context, index) {
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.chat)),
          title: Text('Chat $index'),
          subtitle: const Text('Last message...'),
        );
      },
    );
  }
}
