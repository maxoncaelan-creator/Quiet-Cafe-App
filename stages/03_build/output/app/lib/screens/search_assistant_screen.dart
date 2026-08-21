// Real chat, proxied through the `search-assistant` Edge Function (see
// supabase/functions/search-assistant) — no Anthropic key in this file or
// anywhere in this app. Empty state (illustration + prompt) shows before
// the first message; once a conversation starts, it's a normal thread.
//
// Sign-in required + per-account rate limiting added 2026-08-18, per
// Caelan. Both are enforced server-side (the Edge Function itself rejects a
// signed-out or over-limit caller — see its file header); what's here is
// just the matching UI: a signed-out user sees a message instead of the
// composer, and a rate-limited user sees a "back soon" message with the
// reset time instead. Checked on load (fetchSearchAssistantUsage, a plain
// table read under RLS — costs no tokens) and again reactively if a
// message attempt comes back 429.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../services/location_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_drawer.dart';

class _ChatMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  const _ChatMessage({required this.role, required this.content});
}

class SearchAssistantScreen extends StatefulWidget {
  /// A List View hand-off can prefill a complete area question. It is never
  /// auto-sent: the user sees and controls the request before it spends any
  /// Search Assistant tokens or prompts an on-demand venue refresh.
  final String? initialQuery;

  const SearchAssistantScreen({super.key, this.initialQuery});

  @override
  State<SearchAssistantScreen> createState() => _SearchAssistantScreenState();
}

class _SearchAssistantScreenState extends State<SearchAssistantScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _supabaseService = SupabaseService();
  final _locationService = LocationService();
  final List<_ChatMessage> _messages = [];
  bool _sending = false;

  StreamSubscription? _authSubscription;
  bool _signedIn = false;
  DateTime? _rateLimitedUntil;
  Timer? _rateLimitRefreshTimer;
  NearbyRestaurant? _guessedRestaurant;
  Position? _currentPosition;
  DateTime? _locationCapturedAt;

  static const _locationRefreshAge = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    final initialQuery = widget.initialQuery?.trim();
    if (initialQuery != null && initialQuery.isNotEmpty) {
      _controller.text = initialQuery;
      _controller.selection =
          TextSelection.collapsed(offset: initialQuery.length);
    }
    if (SupabaseService.isConfigured) {
      _signedIn = _supabaseService.isSignedIn;
      if (_signedIn) {
        _checkRateLimitStatus();
        _captureLocationAndMaybeGuessVenue();
      }
      _authSubscription = _supabaseService.authStateChanges.listen((_) {
        if (!mounted) return;
        final signedIn = _supabaseService.isSignedIn;
        setState(() => _signedIn = signedIn);
        if (signedIn) {
          _checkRateLimitStatus();
          _captureLocationAndMaybeGuessVenue();
        } else {
          _rateLimitRefreshTimer?.cancel();
          setState(() {
            _rateLimitedUntil = null;
            _guessedRestaurant = null;
            _currentPosition = null;
            _locationCapturedAt = null;
          });
        }
      });
    }
  }

  /// Captures one bounded GPS fix for two deliberately separate uses: the
  /// assistant receives it with the next question so the backend can refresh
  /// nearby venues, while the empty state may also ask "Are you at X?". A
  /// previous No suppresses only that prompt; it must not stop location-aware
  /// search. As before, unavailable location stays silent rather than blocking
  /// the normal assistant flow.
  Future<void> _captureLocationAndMaybeGuessVenue() async {
    final position = await _locationService.getCurrentPosition();
    if (position == null || !mounted) return;
    setState(() {
      _currentPosition = position;
      _locationCapturedAt = DateTime.now();
    });

    if (!await LocationService.canGuessAgain()) return;

    NearbyRestaurant? nearest;
    try {
      nearest = await _supabaseService.findNearestRestaurant(
          position.latitude, position.longitude);
    } catch (_) {
      return;
    }
    if (nearest != null && mounted) {
      setState(() => _guessedRestaurant = nearest);
    }
  }

  /// A screen can sit open for a long time before the user asks something. Do
  /// not keep re-storing that original fix as if it were current: refresh it
  /// after five minutes and, when a fresh fix is unavailable, let the backend
  /// use only its bounded recent-location fallback instead.
  Future<Position?> _positionForAssistant() async {
    final capturedAt = _locationCapturedAt;
    if (_currentPosition != null &&
        capturedAt != null &&
        DateTime.now().difference(capturedAt) < _locationRefreshAge) {
      return _currentPosition;
    }

    final position = await _locationService.getCurrentPosition();
    if (position == null) return null;
    if (mounted) {
      setState(() {
        _currentPosition = position;
        _locationCapturedAt = DateTime.now();
      });
    }
    return position;
  }

  void _confirmGuess() {
    final restaurant = _guessedRestaurant;
    if (restaurant == null) return;
    // No `extra` — the by-id loader (router.dart's _RestaurantByIdLoader)
    // fetches the full Restaurant itself, same as opening a bookmarked or
    // shared restaurant URL directly.
    context.push('/restaurant/${restaurant.placeId}');
  }

  Future<void> _dismissGuess() async {
    await LocationService.recordDismissal();
    if (mounted) setState(() => _guessedRestaurant = null);
  }

  /// A plain table read under RLS (search_assistant_usage's own-row SELECT
  /// policy) — costs no tokens, doesn't touch the assistant itself. Lets
  /// the screen show "on a break" immediately on load if the account was
  /// already at its limit from an earlier session, not just after a fresh
  /// attempt comes back 429.
  Future<void> _checkRateLimitStatus() async {
    final usage = await _supabaseService.fetchSearchAssistantUsage();
    if (!mounted || usage == null) return;
    if (usage.isRateLimited) {
      setState(() => _rateLimitedUntil = usage.resetAt);
      _scheduleRateLimitRefresh();
    }
  }

  /// Keeps the displayed countdown accurate and clears the gate on its own
  /// once time's up, rather than leaving a stale "X hours" on screen for
  /// however long the user happens to sit on this screen.
  void _scheduleRateLimitRefresh() {
    _rateLimitRefreshTimer?.cancel();
    _rateLimitRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final until = _rateLimitedUntil;
      if (until == null || !until.isAfter(DateTime.now())) {
        _rateLimitRefreshTimer?.cancel();
        setState(() => _rateLimitedUntil = null);
      } else {
        setState(() {}); // just to re-render the countdown text
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    // Reachable only once the composer itself is showing (see build()'s
    // gate above), which already requires isConfigured/_signedIn/not rate
    // limited — no need to re-check any of that here.
    final history =
        _messages.map((m) => {'role': m.role, 'content': m.content}).toList();

    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: text));
      _sending = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final position = await _positionForAssistant();
      final reply = await _supabaseService.askSearchAssistant(
        text,
        history,
        latitude: position?.latitude,
        longitude: position?.longitude,
        accuracyMeters: position?.accuracy,
      );
      if (!mounted) return;
      setState(
          () => _messages.add(_ChatMessage(role: 'assistant', content: reply)));
    } on SearchAssistantRateLimited catch (e) {
      if (!mounted) return;
      setState(() => _rateLimitedUntil = e.resetAt);
      _scheduleRateLimitRefresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(const _ChatMessage(
            role: 'assistant',
            content:
                "Sorry, I couldn't reach the search assistant just now. Try again in a moment.",
          )));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _authSubscription?.cancel();
    _rateLimitRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rateLimitedUntil = _rateLimitedUntil;
    return Scaffold(
      appBar: AppBar(title: const Text('Search Assistant')),
      drawer: const AppDrawer(currentRoute: AppRoute.searchAssistant),
      body: SafeArea(
        child: !SupabaseService.isConfigured
            ? const Center(
                child: Text(
                    'Search Assistant needs a configured backend to work.'))
            : !_signedIn
                ? const _SignInRequiredMessage()
                : rateLimitedUntil != null
                    ? _RateLimitedMessage(resetAt: rateLimitedUntil)
                    : Column(
                        children: [
                          Expanded(
                            child: _messages.isEmpty
                                ? (_guessedRestaurant != null
                                    ? _VenueGuessPrompt(
                                        restaurant: _guessedRestaurant!,
                                        onYes: _confirmGuess,
                                        onNo: _dismissGuess,
                                      )
                                    : const _EmptyState())
                                : _MessageList(
                                    messages: _messages,
                                    sending: _sending,
                                    scrollController: _scrollController,
                                  ),
                          ),
                          _Composer(
                              controller: _controller,
                              sending: _sending,
                              onSend: _send),
                        ],
                      ),
      ),
    );
  }
}

class _SignInRequiredMessage extends StatelessWidget {
  const _SignInRequiredMessage();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.lock_outline,
                  color: scheme.onPrimaryContainer, size: 36),
            ),
            const SizedBox(height: 24),
            Text(
              'Search Assistant needs you to sign up or log in to work.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.push('/sign-in'),
              child: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RateLimitedMessage extends StatelessWidget {
  final DateTime resetAt;
  const _RateLimitedMessage({required this.resetAt});

  /// "X hours and Y minutes" / "Y minutes" (hours dropped under 1h, per
  /// Caelan) / drops "and 0 minutes" when the remainder is exactly on the
  /// hour. Rounds up to the nearest minute so this doesn't show a stale
  /// "0 minutes" (or nothing) in the last seconds before the window
  /// actually resets — see the 30s refresh timer that re-renders this.
  static String _message(Duration remaining) {
    final totalMinutes =
        remaining.inSeconds <= 0 ? 0 : (remaining.inSeconds / 60).ceil();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    String plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'}';

    final remainingText = hours < 1
        ? plural(minutes, 'minute')
        : minutes == 0
            ? plural(hours, 'hour')
            : '${plural(hours, 'hour')} and ${plural(minutes, 'minute')}';

    return 'Search Assistant is on a break, it will be available again in $remainingText.';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = resetAt.difference(DateTime.now());
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.hourglass_bottom,
                  color: scheme.onPrimaryContainer, size: 36),
            ),
            const SizedBox(height: 24),
            Text(
              _message(remaining.isNegative ? Duration.zero : remaining),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.local_cafe_outlined,
                  color: scheme.onPrimaryContainer, size: 36),
            ),
            const SizedBox(height: 24),
            Text(
              'Ready to start searching for quiet eating spots?',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Occupies the exact same slot as [_EmptyState] rather than a dialog or
/// popup — Caelan was specific that this replaces the splash icon/message
/// in place, not overlays it. Sending a message hides it automatically:
/// _messages becomes non-empty, and build()'s own ternary swaps to
/// _MessageList before this widget is ever reached again.
class _VenueGuessPrompt extends StatelessWidget {
  final NearbyRestaurant restaurant;
  final VoidCallback onYes;
  final VoidCallback onNo;

  const _VenueGuessPrompt(
      {required this.restaurant, required this.onYes, required this.onNo});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.place_outlined,
                  color: scheme.onPrimaryContainer, size: 36),
            ),
            const SizedBox(height: 24),
            Text(
              'Are you at ${restaurant.name}?',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(onPressed: onNo, child: const Text('No')),
                const SizedBox(width: 12),
                FilledButton(onPressed: onYes, child: const Text('Yes')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  final List<_ChatMessage> messages;
  final bool sending;
  final ScrollController scrollController;

  const _MessageList(
      {required this.messages,
      required this.sending,
      required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      itemCount: messages.length + (sending ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 20),
      itemBuilder: (context, index) {
        if (index >= messages.length) return const _TypingIndicator();
        final message = messages[index];
        return message.role == 'user'
            ? _UserBubble(text: message.content)
            : _AssistantMessage(text: message.content);
      },
    );
  }
}

class _AssistantMessage extends StatelessWidget {
  final String text;
  const _AssistantMessage({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: scheme.primary,
          child: Icon(Icons.auto_awesome, size: 14, color: scheme.onPrimary),
        ),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
      ],
    );
  }
}

class _UserBubble extends StatelessWidget {
  final String text;
  const _UserBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ),
      ],
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: scheme.primary,
          child: Icon(Icons.auto_awesome, size: 14, color: scheme.onPrimary),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 16,
          height: 16,
          child:
              CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
        ),
      ],
    );
  }
}

class _Composer extends StatefulWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  const _Composer(
      {required this.controller, required this.sending, required this.onSend});

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _speech = stt.SpeechToText();
  bool _listening = false;
  bool _speechAvailable = false;
  bool _initAttempted = false;

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  // Not called from initState — speech_to_text's initialize() triggers the
  // OS microphone-permission prompt immediately, which showed up on this
  // screen's very first load (before any user interaction) when tested on
  // a real device. Deferred to the first tap of the mic button instead.
  Future<void> _initSpeech() async {
    if (_initAttempted) return;
    _initAttempted = true;
    final available = await _speech.initialize(onStatus: (status) {
      if ((status == 'done' || status == 'notListening') && mounted) {
        setState(() => _listening = false);
      }
    });
    if (mounted) setState(() => _speechAvailable = available);
  }

  Future<void> _toggleListening() async {
    if (!_initAttempted) await _initSpeech();
    if (!_speechAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text("Speech recognition isn't available on this device.")),
        );
      }
      return;
    }
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        widget.controller.text = result.recognizedWords;
        widget.controller.selection =
            TextSelection.collapsed(offset: widget.controller.text.length);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  enabled: !widget.sending,
                  decoration: const InputDecoration(
                    hintText: 'Ask about quiet restaurants…',
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => widget.onSend(),
                ),
              ),
              IconButton(
                icon: Icon(
                  _listening ? Icons.mic : Icons.mic_none,
                  color: _listening ? scheme.primary : scheme.onSurfaceVariant,
                ),
                onPressed: widget.sending ? null : _toggleListening,
              ),
              IconButton.filled(
                icon: const Icon(Icons.arrow_upward),
                onPressed: widget.sending ? null : widget.onSend,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
