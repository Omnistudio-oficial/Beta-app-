import 'package:flutter/material.dart';

/// The single set of authenticated destinations shared by the dashboard and
/// persistent navigation. Authentication remains an AppRoot concern, not a tab.
enum AppDestination {
  home,
  chat,
  music,
  maps,
  assistant,
  docs,
  social,
  converter,
  profile,
}

extension AppDestinationPresentation on AppDestination {
  String get label => switch (this) {
        AppDestination.home => 'Home',
        AppDestination.chat => 'Chat',
        AppDestination.music => 'Music',
        AppDestination.maps => 'Maps',
        AppDestination.assistant => 'AI',
        AppDestination.docs => 'Docs',
        AppDestination.social => 'Social',
        AppDestination.converter => 'Convert',
        AppDestination.profile => 'Profile',
      };

  IconData get icon => switch (this) {
        AppDestination.home => Icons.home_outlined,
        AppDestination.chat => Icons.chat_bubble_outline,
        AppDestination.music => Icons.music_note_outlined,
        AppDestination.maps => Icons.map_outlined,
        AppDestination.assistant => Icons.smart_toy_outlined,
        AppDestination.docs => Icons.description_outlined,
        AppDestination.social => Icons.groups_outlined,
        AppDestination.converter => Icons.swap_horiz_outlined,
        AppDestination.profile => Icons.person_outline,
      };
}

const authenticatedDestinations = AppDestination.values;
