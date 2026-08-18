import 'package:flutter/material.dart';

import '../../widgets/app_drawer.dart';
import 'display_settings_screen.dart';
import 'legal_screen.dart';
import 'location_settings_screen.dart';
import 'permissions_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      drawer: const AppDrawer(currentRoute: AppRoute.settings),
      body: ListView(
        children: [
          _SettingsRow(
            icon: Icons.contrast,
            label: 'Display',
            sublabel: 'Theme, dark mode',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DisplaySettingsScreen()),
            ),
          ),
          _SettingsRow(
            icon: Icons.location_on_outlined,
            label: 'Location',
            sublabel: 'City, GPS',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LocationSettingsScreen()),
            ),
          ),
          _SettingsRow(
            icon: Icons.shield_outlined,
            label: 'Permissions',
            sublabel: 'Notifications, microphone',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PermissionsSettingsScreen()),
            ),
          ),
          _SettingsRow(
            icon: Icons.gavel_outlined,
            label: 'Privacy Policy',
            sublabel: 'And other legal documents',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LegalScreen()),
            ),
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
