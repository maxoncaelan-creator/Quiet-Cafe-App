import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/supabase_service.dart';
import '../../widgets/app_drawer.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final supabaseService = SupabaseService();
    final signedIn = supabaseService.isSignedIn;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      drawer: const AppDrawer(currentRoute: AppRoute.settings),
      body: ListView(
        children: [
          if (signedIn)
            _SettingsRow(
              icon: Icons.account_circle_outlined,
              label: 'Account',
              sublabel: 'Email and reading history',
              onTap: () => context.push('/settings/account'),
            ),
          if (supabaseService.currentUserHasPassword)
            _SettingsRow(
              icon: Icons.lock_outline,
              label: 'Change password',
              sublabel: 'Update your account password',
              onTap: () => context.push('/settings/change-password'),
            ),
          _SettingsRow(
            icon: Icons.contrast,
            label: 'Display',
            sublabel: 'Theme, dark mode',
            onTap: () => context.push('/settings/display'),
          ),
          _SettingsRow(
            icon: Icons.location_on_outlined,
            label: 'Location',
            sublabel: 'City, GPS',
            onTap: () => context.push('/settings/location'),
          ),
          _SettingsRow(
            icon: Icons.shield_outlined,
            label: 'Permissions',
            sublabel: 'Notifications, microphone',
            onTap: () => context.push('/settings/permissions'),
          ),
          _SettingsRow(
            icon: Icons.gavel_outlined,
            label: 'Privacy Policy',
            sublabel: 'And other legal documents',
            onTap: () => context.push('/settings/legal'),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sublabel;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.icon,
    required this.label,
    this.sublabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: scheme.onSurfaceVariant),
      title: Text(label),
      subtitle: sublabel == null ? null : Text(sublabel!),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
