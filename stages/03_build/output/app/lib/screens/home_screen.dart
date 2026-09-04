import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/restaurant.dart';
import '../providers/favourites_provider.dart';
import '../providers/restaurant_list_provider.dart';
import '../services/location_service.dart';
import '../services/observability_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/filter_drawer.dart';
import '../widgets/noise_level_bar.dart';
import '../widgets/restaurant_tile.dart';
import '../widgets/searchable_suburb_picker.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/voice_search_bar.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _locationService = LocationService();
  final _supabaseService = SupabaseService();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  String? _suburbFilter;
  bool _showAll = false;
  String? _cuisineFilter;
  int? _loudnessFilterIndex; // index into NoiseLevelBar.categories; null = any
  double? _minRatingFilter;
  SortOption _sortBy = SortOption.quietestFirst;
  String _searchQuery = '';
  bool _refreshingCoverage = false;

  StreamSubscription? _authSubscription;
  String? _signedInEmail;

  @override
  void initState() {
    super.initState();
    // Reflects sign-in state live in the app bar — the previous UI never
    // showed this anywhere, which is easy to mistake for "sessions don't
    // persist" even when they actually do (supabase_flutter persists by
    // default; nothing in this app overrides that).
    //
    // This used to also re-fetch favourites on every sign-in/out here. That
    // is now favouriteIdsProvider's own job (it invalidates itself on the
    // same two events — see favourites_provider.dart) so this listener only
    // has one thing left to do.
    if (SupabaseService.isConfigured) {
      _signedInEmail = _supabaseService.currentUserEmail;
      _authSubscription = _supabaseService.authStateChanges.listen((_) {
        if (!mounted) return;
        setState(() => _signedInEmail = _supabaseService.currentUserEmail);
      });
    }
  }

  /// Toggles the shared favourite set. No local optimistic flip or revert
  /// here any more — favouriteIdsProvider owns both (see toggle() there),
  /// which is what makes a star tapped here show correctly on the detail
  /// screen and vice versa without either screen refetching.
  Future<void> _toggleFavorite(Restaurant restaurant) async {
    if (!_supabaseService.isSignedIn) {
      // Same point-of-need prompt as "Take a reading here" — browsing and
      // favoriting share the account gate, but only favoriting needs it.
      final signedIn = await context.push<bool>('/sign-in');
      if (signedIn != true || !mounted) return;
    }

    try {
      await ref.read(favouriteIdsProvider.notifier).toggle(restaurant.placeId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update favorite — try again.')),
      );
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _handleAccountTap() async {
    await context
        .push(_signedInEmail != null ? '/settings/account' : '/sign-in');
  }

  List<Restaurant> _filtered(List<Restaurant> all) {
    final query = _searchQuery.trim().toLowerCase();
    return all.where((r) {
      if (_suburbFilter != null && r.suburb != _suburbFilter) return false;
      if (_cuisineFilter != null && r.cuisine != _cuisineFilter) return false;
      if (_loudnessFilterIndex != null &&
          NoiseLevelBar.categoryIndexFor(r.quietnessScore) !=
              _loudnessFilterIndex) {
        return false;
      }
      if (_minRatingFilter != null &&
          (r.googleRating == null || r.googleRating! < _minRatingFilter!)) {
        return false;
      }
      if (query.isNotEmpty) {
        final haystack = [r.name, r.cuisine, r.suburb]
            .whereType<String>()
            .join(' ')
            .toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  /// Starts from the repository's quietest-first ranking (already limited to
  /// restaurants with enough data to score) and re-orders it when a
  /// different Sort By option is selected — Loudest First is just that same
  /// list reversed, Rating sorts push restaurants with no rating yet to the
  /// end regardless of direction rather than clumping them at the top.
  List<Restaurant> _sortedRanked(List<Restaurant> all) {
    final quietestFirst = ref
        .read(restaurantRepositoryProvider)
        .rankedByQuietness(_filtered(all));
    switch (_sortBy) {
      case SortOption.quietestFirst:
        return quietestFirst;
      case SortOption.loudestFirst:
        return quietestFirst.reversed.toList();
      case SortOption.ratingHighest:
        return [...quietestFirst]
          ..sort((a, b) => _compareRating(a, b, descending: true));
      case SortOption.ratingLowest:
        return [...quietestFirst]
          ..sort((a, b) => _compareRating(a, b, descending: false));
    }
  }

  int _compareRating(Restaurant a, Restaurant b, {required bool descending}) {
    final ar = a.googleRating;
    final br = b.googleRating;
    if (ar == null && br == null) return 0;
    if (ar == null) return 1; // no rating yet sorts last either way
    if (br == null) return -1;
    return descending ? br.compareTo(ar) : ar.compareTo(br);
  }

  void _clearFilters() {
    setState(() {
      _suburbFilter = null;
      _showAll = true;
      _cuisineFilter = null;
      _loudnessFilterIndex = null;
      _minRatingFilter = null;
    });
  }

  bool get _hasChosenScope => _showAll || _suburbFilter != null;

  void _chooseSuburb(String? suburb) {
    setState(() {
      _suburbFilter = suburb;
      _showAll = suburb == null;
    });
  }

  /// A typed search term is an explicit area only after the user chooses the
  /// coverage action below. A selected suburb is already an exact known area.
  String? get _coverageArea {
    final typed = _searchQuery.trim();
    if (typed.isNotEmpty) return typed;
    return _suburbFilter;
  }

  void _askAssistantAbout(String area) {
    context.go('/', extra: 'Find quiet venues in $area');
  }

  // The suburb-targeted collector deliberately has no List View affordance.
  // Search Assistant invokes the matching guarded server flow in the
  // background after it identifies an explicit suburb in the request.
  // ignore: unused_element
  Future<void> _findMoreVenues(String area) async {
    if (_refreshingCoverage) return;

    if (!_supabaseService.isSignedIn) {
      final signedIn = await context.push<bool>('/sign-in');
      if (signedIn != true || !mounted) return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Find more venues in $area?'),
        content: Text(
          'We’ll treat “$area” as a suburb and check for more venues. This may use a limited Google Places refresh.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Find venues'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _refreshingCoverage = true);
    try {
      final refresh = await _supabaseService.refreshVenueCoverage(area);
      if (!mounted) return;
      // The cached list is only worth caching if there's an explicit way to
      // bust it when the underlying data legitimately changed — a coverage
      // refresh that actually added rows is exactly that case, so this reads
      // through the cache rather than trusting refresh.triggered/placesFound
      // to imply nothing more needs fetching.
      await ref.read(restaurantListProvider.notifier).reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_coverageRefreshMessage(refresh, area))),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Could not check for more venues — please try again later.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshingCoverage = false);
    }
  }

  Future<void> _checkNearbyVenues() async {
    if (_refreshingCoverage) return;

    if (!_supabaseService.isSignedIn) {
      final signedIn = await context.push<bool>('/sign-in');
      if (signedIn != true || !mounted) return;
    }

    setState(() => _refreshingCoverage = true);
    try {
      // The app requests GPS permission during onboarding. LocationService
      // still safely handles an unavailable service or a later revoked grant.
      final position = await _locationService.getCurrentPosition();
      if (!mounted) return;
      if (position == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Your location is unavailable. Turn on location services and try again.'),
          ),
        );
        return;
      }

      final refresh = await _supabaseService.refreshVenueCoverageNear(
        position.latitude,
        position.longitude,
      );
      if (!mounted) return;
      // Same reasoning as _findMoreVenues: a nearby check can add rows, so
      // the cache must be explicitly busted rather than left to whatever it
      // last held.
      await ref.read(restaurantListProvider.notifier).reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_nearbyCoverageRefreshMessage(refresh))),
      );
    } catch (e, st) {
      await ObservabilityService.captureError(e, st,
          context: 'home.check_nearby_venues');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Could not check nearby venues — please try again later.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshingCoverage = false);
    }
  }

  String _coverageRefreshMessage(VenueCoverageRefresh refresh, String area) {
    if (refresh.triggered) {
      final placesFound = refresh.placesFound ?? 0;
      if (placesFound == 0) {
        return 'We checked $area but did not find any new venues yet.';
      }
      return 'Added $placesFound new ${placesFound == 1 ? 'venue' : 'venues'} in $area.';
    }
    return switch (refresh.reason) {
      'coverage_sufficient' => '$area already has good venue coverage.',
      'recently_checked' =>
        '$area was checked recently. Please try again tomorrow.',
      'daily_cap_reached' =>
        'We have reached today’s venue-refresh limit. Please try again tomorrow.',
      'user_daily_cap_reached' =>
        'You have used your five venue refreshes for today. Please try again tomorrow.',
      'topup_in_progress' =>
        'A venue refresh for $area is already running. Please check back shortly.',
      _ => 'No additional venue refresh was needed for $area.',
    };
  }

  String _nearbyCoverageRefreshMessage(VenueCoverageRefresh refresh) {
    if (refresh.triggered) {
      final placesFound = refresh.placesFound ?? 0;
      if (placesFound == 0) {
        return 'We checked within 1 km of you but did not find any new venues yet.';
      }
      return 'Added $placesFound new ${placesFound == 1 ? 'venue' : 'venues'} near you.';
    }
    return switch (refresh.reason) {
      'nearby_recently_checked' =>
        'We already checked within 250 m of you this week. Please try again next week.',
      'coverage_sufficient' =>
        'There are already venues listed within 1 km of you.',
      'daily_cap_reached' =>
        'We have reached today’s venue-refresh limit. Please try again tomorrow.',
      'user_daily_cap_reached' =>
        'You have used your five venue refreshes for today. Please try again tomorrow.',
      'nearby_check_in_progress' =>
        'Someone nearby is already checking this area. Please check back shortly.',
      _ => 'No additional nearby venue refresh was needed.',
    };
  }

  @override
  Widget build(BuildContext context) {
    // restaurantListProvider replaces this screen's own initState() fetch —
    // see restaurant_list_provider.dart for why a shared AsyncNotifier
    // rather than a per-screen field. AsyncValue.when covers the three
    // states the old _loading/_error fields tracked by hand.
    final restaurantsAsync = ref.watch(restaurantListProvider);
    return restaurantsAsync.when(
      loading: () => const Scaffold(body: PageSkeleton()),
      error: (error, _) => Scaffold(
        body: Center(child: Text('Could not load restaurants: $error')),
      ),
      data: (all) => _buildLoaded(context, all),
    );
  }

  Widget _buildLoaded(BuildContext context, List<Restaurant> all) {
    // Derived from the shared set at build time, same as FavouritesScreen
    // and RestaurantDetailScreen — a toggle from either of those screens is
    // visible here with no refetch of its own.
    final favouriteIds =
        ref.watch(favouriteIdsProvider).valueOrNull ?? const <String>{};
    final ranked = _sortedRanked(all);
    final needsData =
        ref.read(restaurantRepositoryProvider).withoutEnoughData(_filtered(all));
    final suburbs =
        all.map((r) => r.suburb).whereType<String>().toSet().toList()..sort();
    final cuisines =
        all.map((r) => r.cuisine).whereType<String>().toSet().toList()..sort();
    final hasActiveFilters = _suburbFilter != null ||
        _cuisineFilter != null ||
        _loudnessFilterIndex != null ||
        _minRatingFilter != null;
    final coverageArea = _coverageArea;

    return Scaffold(
      key: _scaffoldKey,
      drawer: const AppDrawer(currentRoute: AppRoute.list),
      endDrawer: FilterDrawer(
        suburbs: suburbs,
        cuisines: cuisines,
        selectedSuburb: _suburbFilter,
        selectedCuisine: _cuisineFilter,
        selectedLoudnessIndex: _loudnessFilterIndex,
        selectedMinRating: _minRatingFilter,
        sortBy: _sortBy,
        onSuburbChanged: _chooseSuburb,
        onCuisineChanged: (v) => setState(() => _cuisineFilter = v),
        onLoudnessChanged: (v) => setState(() => _loudnessFilterIndex = v),
        onRatingChanged: (v) => setState(() => _minRatingFilter = v),
        onSortByChanged: (v) => setState(() => _sortBy = v),
        onClear: _clearFilters,
      ),
      appBar: AppBar(
        title: const Text('List View'),
        actions: [
          if (SupabaseService.isConfigured)
            _signedInEmail != null
                ? IconButton(
                    tooltip: 'Signed in as $_signedInEmail',
                    icon: const Icon(Icons.account_circle),
                    onPressed: _handleAccountTap,
                  )
                : Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.login, size: 18),
                      label: const Text('Sign In'),
                      onPressed: _handleAccountTap,
                    ),
                  ),
        ],
      ),
      body: !_hasChosenScope
          ? _ChooseSuburbScreen(
              suburbs: suburbs,
              onSuburbSelected: _chooseSuburb,
              onShowAll: () => _chooseSuburb(null),
              showRecordVenues: SupabaseService.isConfigured,
              refreshingCoverage: _refreshingCoverage,
              onRecordVenues: _checkNearbyVenues,
            )
          : Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: VoiceSearchBar(
                          onQueryChanged: (q) =>
                              setState(() => _searchQuery = q)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: IconButton(
                        tooltip: 'Filters',
                        icon: Badge(
                          isLabelVisible: hasActiveFilters,
                          smallSize: 8,
                          child: const Icon(Icons.filter_list),
                        ),
                        onPressed: () =>
                            _scaffoldKey.currentState?.openEndDrawer(),
                      ),
                    ),
                  ],
                ),
                if (SupabaseService.isConfigured)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _RecordNearbyButton(
                        refreshing: _refreshingCoverage,
                        onPressed: _checkNearbyVenues,
                      ),
                    ),
                  ),
                Expanded(
                  child: all.isEmpty
                      ? const _EmptyState()
                      : ListView(
                          children: [
                            for (final restaurant in ranked)
                              RestaurantTile(
                                restaurant: restaurant,
                                isFavorite: favouriteIds
                                    .contains(restaurant.placeId),
                                onToggleFavorite: () =>
                                    _toggleFavorite(restaurant),
                              ),
                            if (needsData.isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'Not enough data yet',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              for (final restaurant in needsData)
                                RestaurantTile(
                                  restaurant: restaurant,
                                  isFavorite: favouriteIds
                                      .contains(restaurant.placeId),
                                  onToggleFavorite: () =>
                                      _toggleFavorite(restaurant),
                                ),
                            ],
                            if (coverageArea != null &&
                                SupabaseService.isConfigured) ...[
                              const SizedBox(height: 8),
                              _SearchResultActions(
                                area: coverageArea,
                                refreshing: _refreshingCoverage,
                                onAskAssistant: () =>
                                    _askAssistantAbout(coverageArea),
                                onCheckNearby: _checkNearbyVenues,
                                noMatches: ranked.isEmpty && needsData.isEmpty,
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}

class _ChooseSuburbScreen extends StatelessWidget {
  final List<String> suburbs;
  final ValueChanged<String?> onSuburbSelected;
  final VoidCallback onShowAll;
  final bool showRecordVenues;
  final bool refreshingCoverage;
  final VoidCallback onRecordVenues;

  const _ChooseSuburbScreen({
    required this.suburbs,
    required this.onSuburbSelected,
    required this.onShowAll,
    required this.showRecordVenues,
    required this.refreshingCoverage,
    required this.onRecordVenues,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.location_city_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Choose Suburb',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Start with a suburb to browse its restaurants.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              SearchableSuburbPicker(
                suburbs: suburbs,
                selectedSuburb: null,
                hintText: 'Select a suburb',
                includeAllSuburbs: false,
                onChanged: onSuburbSelected,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onShowAll,
                child: const Text('show all'),
              ),
              if (showRecordVenues) ...[
                const SizedBox(height: 24),
                _RecordNearbyButton(
                  refreshing: refreshingCoverage,
                  onPressed: onRecordVenues,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordNearbyButton extends StatelessWidget {
  final bool refreshing;
  final VoidCallback onPressed;

  const _RecordNearbyButton({
    required this.refreshing,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: refreshing ? null : onPressed,
      icon: refreshing
          ? const SkeletonBox(
              width: 18,
              height: 18,
              borderRadius: BorderRadius.all(Radius.circular(99)),
            )
          : const Icon(Icons.my_location),
      label: Text(
        refreshing ? 'Recording venues…' : 'Record venues near me',
      ),
    );
  }
}

class _SearchResultActions extends StatelessWidget {
  final String area;
  final bool refreshing;
  final bool noMatches;
  final VoidCallback onAskAssistant;
  final VoidCallback onCheckNearby;

  const _SearchResultActions({
    required this.area,
    required this.refreshing,
    required this.noMatches,
    required this.onAskAssistant,
    required this.onCheckNearby,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              noMatches
                  ? 'No venues found in $area'
                  : 'Not finding the right venue in $area?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Record venues near you, or ask the Assistant to search this area.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: refreshing ? null : onCheckNearby,
                  icon: refreshing
                      ? const SkeletonBox(
                          width: 18,
                          height: 18,
                          borderRadius: BorderRadius.all(Radius.circular(99)),
                        )
                      : const Icon(Icons.my_location),
                  label:
                      Text(refreshing ? 'Recording…' : 'Record venues near me'),
                ),
                OutlinedButton.icon(
                  onPressed: onAskAssistant,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Ask Assistant'),
                ),
              ],
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_outlined,
                size: 48, color: Theme.of(context).disabledColor),
            const SizedBox(height: 12),
            const Text(
              'No restaurants yet',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'Check back soon — we\'re still gathering data.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
