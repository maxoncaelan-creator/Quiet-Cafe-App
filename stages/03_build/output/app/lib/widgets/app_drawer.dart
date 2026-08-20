// The overlay-with-scrim behavior ("don't lose context of where you are")
// is Flutter's default Scaffold.drawer rendering — nothing custom needed
// for that part. This widget is just the drawer's content.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/supabase_service.dart';
import 'app_nav_destinations.dart';

export 'app_nav_destinations.dart' show AppRoute;

class AppDrawer extends StatelessWidget {
  final AppRoute currentRoute;

  const AppDrawer({super.key, required this.currentRoute});

  void _go(BuildContext context, AppRoute route, String path) {
    Navigator.of(context).pop(); // close the drawer first
    if (route == currentRoute) return;
    context.go(path);
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
            // Donate hidden here per Caelan (2026-08-19) — still shown on
            // the wide-layout nav rail, since only the drawer was asked
            // about; filtered out of the shared list rather than removed
            // from it so the two surfaces can differ without duplicating
            // the destinations list.
            for (final d in appNavDestinations.where((d) => d.route != AppRoute.donate))
              _DrawerItem(
                icon: d.icon,
                selectedIcon: d.selectedIcon,
                label: d.label,
                selected: currentRoute == d.route,
                onTap: () => _go(context, d.route, d.path),
              ),
            // Login/Account stays at the bottom of the menu items (Caelan,
            // 2026-08-19) but matches the same _DrawerItem style as the rest
            // of the list rather than a chip (Caelan, 2026-08-20) — it had
            // been visually inconsistent with Search Assistant/List/etc.
            _DrawerItem(
              icon: signedIn ? Icons.account_circle_outlined : Icons.login,
              selectedIcon: signedIn ? Icons.account_circle : Icons.login,
              label: signedIn ? 'Account' : 'Login / Signup',
              selected: currentRoute == AppRoute.login,
              onTap: () {
                Navigator.of(context).pop();
                context.push(signedIn ? '/account' : '/sign-in');
              },
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
