// Shown once, globally (see main.dart's MaterialApp.router builder), only
// when the web build is opened from an iOS/Android browser — Flutter web
// derives defaultTargetPlatform from the browser's own UA, no extra package
// needed. Desktop-browser and native-app visitors never see this.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/download_banner_service.dart';
import 'get_app_prompt.dart';

bool get _isMobileWebVisitor =>
    kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

class DownloadAppBanner extends StatelessWidget {
  const DownloadAppBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!_isMobileWebVisitor) return const SizedBox.shrink();

    return ValueListenableBuilder<bool>(
      valueListenable: DownloadBannerService.dismissed,
      builder: (context, dismissed, _) {
        if (dismissed) return const SizedBox.shrink();

        final scheme = Theme.of(context).colorScheme;
        return Material(
          color: scheme.secondaryContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.phone_iphone, color: scheme.onSecondaryContainer, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Get the app for the best experience',
                      style: TextStyle(color: scheme.onSecondaryContainer),
                    ),
                  ),
                  TextButton(
                    onPressed: () => showGetAppPrompt(context),
                    child: const Text('Get the app'),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: scheme.onSecondaryContainer, size: 18),
                    tooltip: 'Dismiss',
                    onPressed: DownloadBannerService.dismiss,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
