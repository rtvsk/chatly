import 'package:chatly/services/api_service.dart';
import 'package:flutter/material.dart';

import '../storage/token_storage.dart';
import './signup_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});
  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  String? login;
  int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadLogin();
  }

  Future<void> _loadLogin() async {
    final savedLogin = await TokenStorage.instance.getUserLogin();

    if (!mounted) return;

    final response = await ApiService.instance.get('/chats');
    print(response.statusCode);
    print(response.body);

    setState(() {
      login = savedLogin;
    });
  }

  Future<void> _logout() async {
    await TokenStorage.instance.clearSession();

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const SignupScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userLogin = login ?? 'Loading...';

    final pages = [
      const ContactsTab(),
      const ChatsTab(),
    ];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            // expandedHeight: 160,
            title: Text(userLogin),
            actions: [
              IconButton(
                onPressed: _logout,
                icon: const Icon(Icons.logout),
              ),
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
            child: Padding(padding: EdgeInsets.all(8), child: pages[currentIndex]),
          ),
        ],
      ),

      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.contacts_outlined),
            selectedIcon: Icon(Icons.contacts),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
        ],
      ),
    );
  }
}

class ContactsTab extends StatelessWidget {
  const ContactsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: 30,
      itemBuilder: (context, index) {
        return ListTile(
          leading: const CircleAvatar(
            child: Icon(Icons.person),
          ),
          title: Text('Contact $index'),
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
          leading: const CircleAvatar(
            child: Icon(Icons.chat),
          ),
          title: Text('Chat $index'),
          subtitle: const Text('Last message...'),
        );
      },
    );
  }
}