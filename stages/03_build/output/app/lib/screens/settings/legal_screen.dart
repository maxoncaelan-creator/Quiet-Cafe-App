// Privacy Policy / Terms don't exist yet (content gap, not code — see
// ui-design-decisions.md) — those rows are visibly disabled rather than
// linking to a placeholder URL. Open Source Licenses is real: Flutter
// generates it automatically from every package's license, nothing to
// write or wait on.

import 'package:flutter/material.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: ListView(
        children: [
          const _LegalRow(icon: Icons.privacy_tip_outlined, label: 'Privacy Policy'),
          const _LegalRow(icon: Icons.description_outlined, label: 'Terms of Service'),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Open Source Licenses'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Quiet Restaurant Finder',
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _LegalRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: false,
      leading: Icon(icon),
      title: Text(label),
      trailing: const Text('Coming soon', style: TextStyle(fontSize: 12)),
    );
  }
}
