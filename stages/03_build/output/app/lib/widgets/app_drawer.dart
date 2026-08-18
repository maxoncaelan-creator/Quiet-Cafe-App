// The overlay-with-scrim behavior ("don't lose context of where you are")
// is Flutter's default Scaffold.drawer rendering — nothing custom needed
// for that part. This widget is just the drawer's content.

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/account_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/favourites_screen.dart';
import '../screens/home_screen.dart';
import '../screens/search_assistant_screen.dart';
import '../screens/settings/donate_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../services/supabase_service.dart';

enum AppRoute { searchAssistant, list, favourites, login, settings, donate }

class AppDrawer extends StatelessWidget {
  final AppRoute currentRoute;

  const AppDrawer({super.key, required this.currentRoute});

  void _go(BuildContext context, AppRoute route, Widget Function() builder) {
    Navigator.of(context).pop(); // close the drawer first
    if (route == currentRoute) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => builder()));
  }

  Future<void> _reportProblem(BuildContext context) async {
    Navigator.of(context).pop();
    // Simplest option that needs no new backend — see ui-design-decisions.md.
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@quietrestaurantfinder.app',
      query: 'subject=${Uri.encodeComponent('Quiet Restaurant Finder — problem report')}',
    );
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final signedIn = SupabaseService().isSignedIn;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Quiet Restaurant Finder', style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            _DrawerItem(
              icon: Icons.forum_outlined,
              selectedIcon: Icons.forum,
              label: 'Search Assistant',
              selected: currentRoute == AppRoute.searchAssistant,
              onTap: () => _go(context, AppRoute.searchAssistant, () => const SearchAssistantScreen()),
            ),
            _DrawerItem(
              icon: Icons.restaurant_outlined,
              selectedIcon: Icons.restaurant,
              label: 'List',
              selected: currentRoute == AppRoute.list,
              onTap: () => _go(context, AppRoute.list, () => const HomeScreen()),
            ),
            _DrawerItem(
              icon: Icons.star_border_rounded,
              selectedIcon: Icons.star_rounded,
              label: 'Favourites',
              selected: currentRoute == AppRoute.favourites,
              onTap: () => _go(context, AppRoute.favourites, () => const FavouritesScreen()),
            ),
            _DrawerItem(
              icon: Icons.login,
              selectedIcon: Icons.login,
              label: signedIn ? 'Account' : 'Login / Signup',
              selected: currentRoute == AppRoute.login,
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => signedIn ? const AccountScreen() : const AuthScreen(),
                ));
              },
            ),
            _DrawerItem(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              label: 'Settings',
              selected: currentRoute == AppRoute.settings,
              onTap: () => _go(context, AppRoute.settings, () => const SettingsScreen()),
            ),
            _DrawerItem(
              icon: Icons.volunteer_activism_outlined,
              selectedIcon: Icons.volunteer_activism,
              label: 'Donate',
              selected: currentRoute == AppRoute.donate,
              onTap: () => _go(context, AppRoute.donate, () => const DonateScreen()),
            ),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Report a problem'),
              onTap: () => _reportProblem(context),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 4),
              child: FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  final info = snapshot.data;
                  return Text(
                    info == null ? '' : 'Version ${info.version} (${info.buildNumber})',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? scheme.onSecondaryContainer : scheme.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
