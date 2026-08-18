// Single source of truth for the 5 top-level nav destinations, shared by
// AppDrawer (narrow layouts) and AppNavRail (wide layouts) so the two can't
// drift apart. `login` stays special-cased in both — it's a push (not a
// route swap) whose target depends on sign-in state, unlike these 5.
import 'package:flutter/material.dart';

enum AppRoute { searchAssistant, list, favourites, login, settings, donate }

class AppNavDestination {
  final AppRoute route;
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const AppNavDestination({
    required this.route,
    required this.path,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

const appNavDestinations = [
  AppNavDestination(
    route: AppRoute.searchAssistant,
    path: '/',
    icon: Icons.forum_outlined,
    selectedIcon: Icons.forum,
    label: 'Search Assistant',
  ),
  AppNavDestination(
    route: AppRoute.list,
    path: '/list',
    icon: Icons.restaurant_outlined,
    selectedIcon: Icons.restaurant,
    label: 'List',
  ),
  AppNavDestination(
    route: AppRoute.favourites,
    path: '/favourites',
    icon: Icons.star_border_rounded,
    selectedIcon: Icons.star_rounded,
    label: 'Favourites',
  ),
  AppNavDestination(
    route: AppRoute.settings,
    path: '/settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: 'Settings',
  ),
  AppNavDestination(
    route: AppRoute.donate,
    path: '/donate',
    icon: Icons.volunteer_activism_outlined,
    selectedIcon: Icons.volunteer_activism,
    label: 'Donate',
  ),
];

/// Maps the current location to one of the 5 destinations above, or null for
/// everything else (account, auth, detail, settings sub-screens) — those
/// screens simply show no destination selected, same as they show no drawer
/// item selected today.
AppRoute? appRouteForLocation(String location) {
  for (final d in appNavDestinations) {
    if (location == d.path) return d.route;
  }
  return null;
}
