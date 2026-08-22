import 'package:flutter_test/flutter_test.dart';
import 'package:quiet_restaurant_finder/widgets/noise_level_bar.dart';

void main() {
  test('uses the four public loudness categories', () {
    expect(NoiseLevelBar.categories, ['Quiet', 'Normal', 'Loud', 'Very Loud']);
  });

  test('maps the quietness range across the four categories', () {
    expect(NoiseLevelBar.categoryIndexFor(100), 0);
    expect(NoiseLevelBar.categoryIndexFor(74), 1);
    expect(NoiseLevelBar.categoryIndexFor(49), 2);
    expect(NoiseLevelBar.categoryIndexFor(24), 3);
  });
}
