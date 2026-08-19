// Display-only formatting. Google Places primary types (and anything else
// stored as a lower_snake_case enum, e.g. "french_restaurant") come straight
// from the API and are used as-is for filtering/comparison — this only
// changes how they're rendered as text, never the underlying value.

String humanizeSnakeCase(String value) {
  if (value.isEmpty) return value;
  return value
      .split('_')
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');
}
