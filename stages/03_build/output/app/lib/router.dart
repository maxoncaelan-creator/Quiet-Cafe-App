// Full route table for the app — added for web support (bookmarkable/
// shareable URLs) and to let the persistent nav shell (AppShell) wrap every
// screen, not just the 5 top-level ones. See PLATFORM_SETUP.md's "Web"
// section for the route table in prose form.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'models/restaurant.dart';
import 'services/beta_gate_notifier.dart';
import 'services/supabase_service.dart';
import 'screens/account_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/beta_gate_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/create_account_email_screen.dart';
import 'screens/create_account_password_screen.dart';
import 'screens/create_account_screen.dart';
import 'screens/favourites_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/home_screen.dart';
import 'screens/mic_calibration_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/restaurant_detail_screen.dart';
import 'screens/search_assistant_screen.dart';
import 'screens/settings/display_settings_screen.dart';
import 'screens/settings/donate_screen.dart';
import 'screens/settings/legal_screen.dart';
import 'screens/settings/location_settings_screen.dart';
import 'screens/settings/permissions_settings_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/sign_in_email_screen.dart';
import 'widgets/app_shell.dart';

// Single source of truth for router.dart's own gate redirect below —
// also handed to BetaGateScreen so a successful redemption can trigger a
// recheck. See beta_gate_notifier.dart.
final betaGateNotifier = BetaGateNotifier();

// Auth routes remain available while signed out. Once an ordinary sign-in or
// email-confirmation callback installs a session, the gate owns navigation so
// a callback cannot remain stranded on the sign-in screen. Recovery stays
// exempt because its temporary session must reach ResetPasswordScreen.
const _authFlowPaths = {
  '/sign-in',
  '/sign-in/email',
  '/sign-up',
  '/sign-up/email',
  '/sign-up/password',
  '/forgot-password',
  '/reset-password',
};

const _passwordRecoveryPaths = {
  '/forgot-password',
  '/reset-password',
};

/// Closed-beta gate, added 2026-08-21 (Caelan): sign-in is required before
/// anything else while the beta is closed, and a signed-in account without
/// a redeemed code lands on /beta-gate instead. This is a beta-period
/// override of this app's normal "browsing never needs an account" design
/// (see decisions.md) — worth removing, not just leaving dormant, once the
/// closed beta ends.
String? _gateRedirect(BuildContext context, GoRouterState state) {
  if (!SupabaseService.isConfigured) {
    return null; // standalone/demo build — no gate
  }

  final loc = state.matchedLocation;
  final supabaseService = SupabaseService();
  if (!supabaseService.isSignedIn) {
    return _authFlowPaths.contains(loc) ? null : '/sign-in';
  }

  if (_passwordRecoveryPaths.contains(loc)) return null;

  final hasAccess = betaGateNotifier.hasAccess;
  if (hasAccess == null) {
    return loc == '/checking-access' ? null : '/checking-access';
  }
  if (!hasAccess) {
    return loc == '/beta-gate' ? null : '/beta-gate';
  }

  // Signed in and cleared the gate — don't leave them stranded on the
  // gate/loading screens once there's nothing left to do there.
  if (loc == '/beta-gate' || loc == '/checking-access') return '/';
  return null;
}

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  refreshListenable: betaGateNotifier,
  redirect: _gateRedirect,
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) {
            final initialQuery = state.extra;
            return SearchAssistantScreen(
              initialQuery: initialQuery is String ? initialQuery : null,
            );
          },
        ),
        GoRoute(path: '/list', builder: (context, state) => const HomeScreen()),
        GoRoute(
            path: '/favourites',
            builder: (context, state) => const FavouritesScreen()),
        GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen()),
        GoRoute(
            path: '/settings/display',
            builder: (context, state) => const DisplaySettingsScreen()),
        GoRoute(
            path: '/settings/location',
            builder: (context, state) => const LocationSettingsScreen()),
        GoRoute(
            path: '/settings/permissions',
            builder: (context, state) => const PermissionsSettingsScreen()),
        GoRoute(
            path: '/settings/legal',
            builder: (context, state) => const LegalScreen()),
        GoRoute(
            path: '/settings/account',
            builder: (context, state) => const AccountScreen()),
        GoRoute(
          path: '/settings/change-password',
          builder: (context, state) => const ChangePasswordScreen(),
        ),
        GoRoute(
            path: '/donate', builder: (context, state) => const DonateScreen()),
        // Preserve existing bookmarks while keeping all new navigation under
        // Settings.
        GoRoute(
            path: '/account',
            redirect: (context, state) => '/settings/account'),
        GoRoute(
          path: '/account/change-password',
          redirect: (context, state) => '/settings/change-password',
        ),
        GoRoute(
          path: '/beta-gate',
          builder: (context, state) =>
              BetaGateScreen(gateNotifier: betaGateNotifier),
        ),
        GoRoute(
          path: '/checking-access',
          builder: (context, state) =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
        ),
        GoRoute(
            path: '/sign-in', builder: (context, state) => const AuthScreen()),
        GoRoute(
            path: '/sign-in/email',
            builder: (context, state) => const SignInEmailScreen()),
        GoRoute(
          path: '/sign-up',
          builder: (context, state) => CreateAccountScreen(
            onPendingConfirmation: state.extra as ValueChanged<String>,
          ),
        ),
        GoRoute(
          path: '/sign-up/email',
          builder: (context, state) => CreateAccountEmailScreen(
            onPendingConfirmation: state.extra as ValueChanged<String>,
          ),
        ),
        GoRoute(
          path: '/sign-up/password',
          builder: (context, state) {
            final extra = state.extra as ({
              String email,
              ValueChanged<String> onPendingConfirmation
            });
            return CreateAccountPasswordScreen(
              email: extra.email,
              onPendingConfirmation: extra.onPendingConfirmation,
            );
          },
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (context, state) => ForgotPasswordScreen(
              initialEmail: (state.extra as String?) ?? ''),
        ),
        GoRoute(
            path: '/reset-password',
            builder: (context, state) => const ResetPasswordScreen()),
        GoRoute(
            path: '/mic-calibration',
            builder: (context, state) => const MicCalibrationScreen()),
        GoRoute(
          path: '/restaurant/:placeId',
          builder: (context, state) {
            final extra = state.extra;
            if (extra is Restaurant) {
              return RestaurantDetailScreen(restaurant: extra);
            }
            // Direct load / browser refresh — no in-memory Restaurant to
            // hand over, so fetch it by the id in the URL instead. This is
            // what makes this route genuinely bookmarkable/shareable, not
            // just cosmetically present.
            return _RestaurantByIdLoader(
                placeId: state.pathParameters['placeId']!);
          },
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    appBar: AppBar(title: const Text('Not found')),
    body: Center(
      child: FilledButton(
        onPressed: () => context.go('/'),
        child: const Text('Back to Search Assistant'),
      ),
    ),
  ),
);

/// Fetches a restaurant by place_id when a URL is opened/refreshed directly
/// without the in-memory Restaurant object go_router's `extra` normally
/// carries from in-app taps.
class _RestaurantByIdLoader extends StatelessWidget {
  final String placeId;

  const _RestaurantByIdLoader({required this.placeId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Restaurant>(
      future: SupabaseService().fetchRestaurantByPlaceId(placeId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Restaurant not found')),
            body: Center(
                child: Text(
                    'Could not load this restaurant: ${snapshot.error ?? 'not found'}')),
          );
        }
        return RestaurantDetailScreen(restaurant: snapshot.data!);
      },
    );
  }
}
