import 'package:flutter/material.dart';

/// A suburb selector that keeps a text search inside its selection surface.
/// This avoids an unwieldy, scroll-only dropdown as the venue database grows.
class SearchableSuburbPicker extends StatelessWidget {
  final List<String> suburbs;
  final String? selectedSuburb;
  final ValueChanged<String?> onChanged;
  final String hintText;
  final bool includeAllSuburbs;

  const SearchableSuburbPicker({
    super.key,
    required this.suburbs,
    required this.selectedSuburb,
    required this.onChanged,
    this.hintText = 'Select a suburb',
    this.includeAllSuburbs = true,
  });

  Future<void> _open(BuildContext context) async {
    final selection = await showModalBottomSheet<_SuburbSelection>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SuburbSelectionSheet(
        suburbs: suburbs,
        selectedSuburb: selectedSuburb,
        includeAllSuburbs: includeAllSuburbs,
      ),
    );
    if (selection != null) onChanged(selection.suburb);
  }

  @override
  Widget build(BuildContext context) {
    final displayText =
        selectedSuburb ?? (includeAllSuburbs ? 'All suburbs' : hintText);
    return Semantics(
      button: true,
      label: 'Suburb selector',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _open(context),
          child: InputDecorator(
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(displayText, overflow: TextOverflow.ellipsis),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuburbSelection {
  final String? suburb;

  const _SuburbSelection(this.suburb);
}

class _SuburbSelectionSheet extends StatefulWidget {
  final List<String> suburbs;
  final String? selectedSuburb;
  final bool includeAllSuburbs;

  const _SuburbSelectionSheet({
    required this.suburbs,
    required this.selectedSuburb,
    required this.includeAllSuburbs,
  });

  @override
  State<_SuburbSelectionSheet> createState() => _SuburbSelectionSheetState();
}

class _SuburbSelectionSheetState extends State<_SuburbSelectionSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = widget.suburbs
        .where((suburb) => suburb.toLowerCase().contains(normalizedQuery))
        .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          top: 16,
          right: 20,
          bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose Suburb',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search suburbs',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    if (widget.includeAllSuburbs &&
                        ('all suburbs'.contains(normalizedQuery) ||
                            normalizedQuery.isEmpty))
                      ListTile(
                        title: const Text('All suburbs'),
                        trailing: widget.selectedSuburb == null
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.pop(
                            context, const _SuburbSelection(null)),
                      ),
                    for (final suburb in filtered)
                      ListTile(
                        title: Text(suburb),
                        trailing: suburb == widget.selectedSuburb
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () =>
                            Navigator.pop(context, _SuburbSelection(suburb)),
                      ),
                    if (filtered.isEmpty &&
                        !(widget.includeAllSuburbs &&
                            'all suburbs'.contains(normalizedQuery)))
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('No suburbs found')),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
