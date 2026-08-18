// Blocked on Caelan's own Stripe account and a backend Edge Function to
// create the Checkout Session — the secret key can't live in this client,
// same reasoning as every other credential in this app. This screen is
// honest about that rather than showing a working-looking button that
// goes nowhere. See ui-design-decisions.md.

import 'package:flutter/material.dart';

import '../../widgets/app_drawer.dart';

class DonateScreen extends StatelessWidget {
  const DonateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Donate')),
      drawer: const AppDrawer(currentRoute: AppRoute.donate),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.volunteer_activism, color: scheme.onPrimaryContainer, size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              "Quiet Restaurant Finder is free to use. If it's helped you find somewhere calm, "
              'consider supporting the person who builds and maintains it.',
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.hourglass_empty, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Not connected yet — this needs a Stripe account to be set up first.'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
