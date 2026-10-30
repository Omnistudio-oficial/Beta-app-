import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:beta_app/app/app_destination.dart';
import 'package:beta_app/screens/ai_screen.dart';
import 'package:beta_app/screens/chat_screen.dart';
import 'package:beta_app/screens/converter_screen.dart';
import 'package:beta_app/screens/docs_screen.dart';
import 'package:beta_app/screens/home_screen.dart';
import 'package:beta_app/screens/maps_screen.dart';
import 'package:beta_app/screens/music_screen.dart';
import 'package:beta_app/screens/profile_screen.dart';
import 'package:beta_app/screens/social_screen.dart';

/// Hosts all migrated screens in one authenticated environment. Optional
/// overrides make route behavior testable without initializing Firebase.
class NavigationShell extends StatefulWidget {
  const NavigationShell({
    super.key,
    this.pageOverrides = const {},
    this.displayName,
    this.onSignOut,
  });

  final Map<AppDestination, Widget> pageOverrides;
  final String? displayName;
  final VoidCallback? onSignOut;

  @override
  State<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<NavigationShell> {
  AppDestination _selectedDestination = AppDestination.home;

  void _navigate(AppDestination destination) {
    if (!authenticatedDestinations.contains(destination)) return;
    setState(() => _selectedDestination = destination);
  }

  Widget _pageFor(AppDestination destination, User? user) {
    final override = widget.pageOverrides[destination];
    if (override != null) return override;
    return switch (destination) {
      AppDestination.home => HomeScreen(
          displayName: widget.displayName ?? user?.displayName ?? user?.email?.split('@').first ?? '',
          onNavigate: _navigate,
          onSignOut: widget.onSignOut ?? () => FirebaseAuth.instance.signOut(),
        ),
      AppDestination.chat => const ChatScreen(),
      AppDestination.music => const MusicScreen(),
      AppDestination.maps => const MapsScreen(),
      AppDestination.assistant => const AIScreen(),
      AppDestination.docs => const DocsScreen(),
      AppDestination.social => const SocialScreen(),
      AppDestination.converter => const ConverterScreen(),
      AppDestination.profile => const ProfileScreen(),
    };
  }

  @override
  Widget build(BuildContext context) {
    // An injected display name signals a test host and avoids touching the
    // Firebase singleton before the Firebase-dependent app is initialized.
    final user = widget.displayName == null ? FirebaseAuth.instance.currentUser : null;
    final pages = [for (final destination in authenticatedDestinations) _pageFor(destination, user)];
    final selectedIndex = authenticatedDestinations.indexOf(_selectedDestination);

    return Scaffold(
      body: IndexedStack(index: selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => _navigate(authenticatedDestinations[index]),
        destinations: [
          for (final destination in authenticatedDestinations)
            NavigationDestination(
              key: Key('navigation_${destination.name}'),
              icon: Icon(destination.icon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}
