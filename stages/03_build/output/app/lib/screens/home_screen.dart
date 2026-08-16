import 'package:flutter/material.dart';

import '../models/restaurant.dart';
import '../services/restaurant_repository.dart';
import 'restaurant_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repository = RestaurantRepository();

  List<Restaurant> _all = [];
  String? _suburbFilter;
  String? _cuisineFilter;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final restaurants = await _repository.loadAll();
      setState(() {
        _all = restaurants;
        _loading = false;
      });
    } catch (error) {
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  List<Restaurant> get _filtered {
    return _all.where((r) {
      if (_suburbFilter != null && r.suburb != _suburbFilter) return false;
      if (_cuisineFilter != null && r.cuisine != _cuisineFilter) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(body: Center(child: Text('Could not load restaurants: $_error')));
    }

    final ranked = _repository.rankedByQuietness(_filtered);
    final needsData = _repository.withoutEnoughData(_filtered);
    final suburbs = _all.map((r) => r.suburb).whereType<String>().toSet().toList()..sort();
    final cuisines = _all.map((r) => r.cuisine).whereType<String>().toSet().toList()..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('Quietest in Sydney')),
      body: Column(
        children: [
          _FilterBar(
            suburbs: suburbs,
            cuisines: cuisines,
            selectedSuburb: _suburbFilter,
            selectedCuisine: _cuisineFilter,
            onSuburbChanged: (v) => setState(() => _suburbFilter = v),
            onCuisineChanged: (v) => setState(() => _cuisineFilter = v),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final restaurant in ranked)
                  _RestaurantTile(restaurant: restaurant),
                if (needsData.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Not enough data yet',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  for (final restaurant in needsData)
                    _RestaurantTile(restaurant: restaurant),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final List<String> suburbs;
  final List<String> cuisines;
  final String? selectedSuburb;
  final String? selectedCuisine;
  final ValueChanged<String?> onSuburbChanged;
  final ValueChanged<String?> onCuisineChanged;

  const _FilterBar({
    required this.suburbs,
    required this.cuisines,
    required this.selectedSuburb,
    required this.selectedCuisine,
    required this.onSuburbChanged,
    required this.onCuisineChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: selectedSuburb,
              decoration: const InputDecoration(labelText: 'Suburb'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All suburbs')),
                for (final s in suburbs) DropdownMenuItem(value: s, child: Text(s)),
              ],
              onChanged: onSuburbChanged,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: selectedCuisine,
              decoration: const InputDecoration(labelText: 'Cuisine'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All cuisines')),
                for (final c in cuisines) DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: onCuisineChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _RestaurantTile extends StatelessWidget {
  final Restaurant restaurant;

  const _RestaurantTile({required this.restaurant});

  @override
  Widget build(BuildContext context) {
    final score = restaurant.quietnessScore;
    return ListTile(
      title: Text(restaurant.name),
      subtitle: Text([restaurant.cuisine, restaurant.suburb].whereType<String>().join(' · ')),
      trailing: score == null
          ? const Text('—')
          : Text(
              score.round().toString(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RestaurantDetailScreen(restaurant: restaurant)),
      ),
    );
  }
}
