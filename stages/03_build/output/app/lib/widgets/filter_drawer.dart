// Pops out from the right (Scaffold.endDrawer), mirroring how AppDrawer
// pops out from the left — same Drawer widget, same scrim-and-slide
// behavior, just a different set of controls. Added 2026-08-19 to replace
// the two inline dropdowns that used to sit under the search bar: Suburb
// and Cuisine Type stayed, Loudness and Rating were added, and a Sort By
// section moved in alongside them per Caelan's request.

import 'package:flutter/material.dart';

import '../utils/text_format.dart';
import 'noise_level_bar.dart';
import 'searchable_suburb_picker.dart';

enum SortOption {
  quietestFirst,
  loudestFirst,
  ratingHighest,
  ratingLowest;

  String get label => switch (this) {
        SortOption.quietestFirst => 'Loudness - Quietest First',
        SortOption.loudestFirst => 'Loudness - Loudest First',
        SortOption.ratingHighest => 'Rating - Highest',
        SortOption.ratingLowest => 'Rating - Lowest',
      };
}

// Thresholds rather than exact-match buckets — "4.0+" reads naturally and
// matches how rating filters work in comparable apps; ratings in the data
// are Google's raw 0-5 values, not a tiered enum like Loudness has.
const List<double> ratingThresholds = [4.5, 4.0, 3.5, 3.0];

class FilterDrawer extends StatelessWidget {
  final List<String> suburbs;
  final List<String> cuisines;
  final String? selectedSuburb;
  final String? selectedCuisine;
  final int? selectedLoudnessIndex;
  final double? selectedMinRating;
  final SortOption sortBy;
  final ValueChanged<String?> onSuburbChanged;
  final ValueChanged<String?> onCuisineChanged;
  final ValueChanged<int?> onLoudnessChanged;
  final ValueChanged<double?> onRatingChanged;
  final ValueChanged<SortOption> onSortByChanged;
  final VoidCallback onClear;

  const FilterDrawer({
    super.key,
    required this.suburbs,
    required this.cuisines,
    required this.selectedSuburb,
    required this.selectedCuisine,
    required this.selectedLoudnessIndex,
    required this.selectedMinRating,
    required this.sortBy,
    required this.onSuburbChanged,
    required this.onCuisineChanged,
    required this.onLoudnessChanged,
    required this.onRatingChanged,
    required this.onSortByChanged,
    required this.onClear,
  });

  bool get _hasActiveFilters =>
      selectedSuburb != null ||
      selectedCuisine != null ||
      selectedLoudnessIndex != null ||
      selectedMinRating != null;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Filters',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _FilterSection(
                    label: 'Suburb',
                    child: SearchableSuburbPicker(
                      suburbs: suburbs,
                      selectedSuburb: selectedSuburb,
                      onChanged: onSuburbChanged,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _FilterSection(
                    label: 'Cuisine Type',
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedCuisine,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(), isDense: true),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('All cuisines')),
                        for (final c in cuisines)
                          DropdownMenuItem(
                            value: c,
                            child: Text(humanizeSnakeCase(c),
                                overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: onCuisineChanged,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _FilterSection(
                    label: 'Loudness',
                    child: DropdownButtonFormField<int>(
                      initialValue: selectedLoudnessIndex,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(), isDense: true),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Any loudness')),
                        for (var i = 0;
                            i < NoiseLevelBar.categories.length;
                            i++)
                          DropdownMenuItem(
                              value: i,
                              child: Text(NoiseLevelBar.categories[i])),
                      ],
                      onChanged: onLoudnessChanged,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _FilterSection(
                    label: 'Rating',
                    child: DropdownButtonFormField<double>(
                      initialValue: selectedMinRating,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(), isDense: true),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Any rating')),
                        for (final t in ratingThresholds)
                          DropdownMenuItem(
                              value: t,
                              child: Text('${t.toStringAsFixed(1)}+ stars')),
                      ],
                      onChanged: onRatingChanged,
                    ),
                  ),
                  const Divider(height: 40),
                  _FilterSection(
                    label: 'Sort By',
                    child: DropdownButtonFormField<SortOption>(
                      initialValue: sortBy,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(), isDense: true),
                      items: [
                        for (final option in SortOption.values)
                          DropdownMenuItem(
                              value: option,
                              child: Text(option.label,
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) {
                        if (v != null) onSortByChanged(v);
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            if (_hasActiveFilters)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Clear all filters'),
                  onPressed: onClear,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  final String label;
  final Widget child;

  const _FilterSection({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
