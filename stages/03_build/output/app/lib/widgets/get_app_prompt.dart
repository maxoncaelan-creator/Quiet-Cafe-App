// Shared bottom sheet with store-link buttons, reused by DownloadAppBanner's
// CTA and by the web-only "take a reading in the app" fallback on
// restaurant_detail_screen.dart — one place for this UI instead of two.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/store_links.dart';

Future<void> showGetAppPrompt(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Get the app', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Some features, like taking a noise reading, need the mobile app.'),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.apple),
              label: const Text('App Store'),
              onPressed: () => launchUrl(Uri.parse(appStoreUrl)),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.shop_outlined),
              label: const Text('Google Play'),
              onPressed: () => launchUrl(Uri.parse(playStoreUrl)),
            ),
          ],
        ),
      ),
    ),
  );
}
