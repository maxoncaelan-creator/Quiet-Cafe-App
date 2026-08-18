// The wide-layout equivalent of AppDrawer — shown by AppShell instead of
// the drawer once the window is at least kWideLayoutBreakpoint wide. Reads
// the same appNavDestinations list so the two never drift apart.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/supabase_service.dart';
import 'app_nav_destinations.dart';

class AppNavRail extends StatelessWidget {
  final AppRoute? currentRoute;

  const AppNavRail({super.key, required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    final signedIn = SupabaseService().isSignedIn;
    final selectedIndex = appNavDestinations.indexWhere((d) => d.route == currentRoute);

    return NavigationRail(
      selectedIndex: selectedIndex < 0 ? null : selectedIndex,
      labelType: NavigationRailLabelType.all,
      destinations: [
        for (final d in appNavDestinations)
          NavigationRailDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.selectedIcon),
            label: Text(d.label),
          ),
      ],
      onDestinationSelected: (i) {
        final target = appNavDestinations[i];
        if (target.route == currentRoute) return;
        context.go(target.path);
      },
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: IconButton(
              icon: const Icon(Icons.login),
              tooltip: signedIn ? 'Account' : 'Login / Signup',
              onPressed: () => context.push(signedIn ? '/account' : '/sign-in'),
            ),
          ),
        ),
      ),
    );
  }
}
