import 'package:flutter/material.dart';

import 'package:beta_app/screens/ai_screen.dart';
import 'package:beta_app/screens/auth_screen.dart';
import 'package:beta_app/screens/chat_screen.dart';
import 'package:beta_app/screens/converter_screen.dart';
import 'package:beta_app/screens/docs_screen.dart';
import 'package:beta_app/screens/home_screen.dart';
import 'package:beta_app/screens/maps_screen.dart';
import 'package:beta_app/screens/music_screen.dart';
import 'package:beta_app/screens/profile_screen.dart';
import 'package:beta_app/screens/social_screen.dart';

class NavigationShell extends StatefulWidget {
  const NavigationShell({super.key});

  @override
  State<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<NavigationShell> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = <Widget>[
    HomeScreen(),
    ChatScreen(),
    MusicScreen(),
    MapsScreen(),
    AIScreen(),
    DocsScreen(),
    SocialScreen(),
    ConverterScreen(),
    AuthScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (value) {
          setState(() => _selectedIndex = value);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.music_note_outlined), label: 'Music'),
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Maps'),
          NavigationDestination(icon: Icon(Icons.smart_toy_outlined), label: 'AI'),
          NavigationDestination(icon: Icon(Icons.description_outlined), label: 'Docs'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Social'),
          NavigationDestination(icon: Icon(Icons.swap_horiz_outlined), label: 'Convert'),
          NavigationDestination(icon: Icon(Icons.login_outlined), label: 'Auth'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}
