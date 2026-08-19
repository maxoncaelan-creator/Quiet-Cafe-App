import 'package:flutter_test/flutter_test.dart';
import 'package:quiet_restaurant_finder/utils/text_format.dart';

void main() {
  test('humanizeSnakeCase turns a Places-style enum into a readable label', () {
    expect(humanizeSnakeCase('french_restaurant'), 'French Restaurant');
    expect(humanizeSnakeCase('restaurant'), 'Restaurant');
    expect(humanizeSnakeCase('fine_dining_restaurant'), 'Fine Dining Restaurant');
  });

  test('humanizeSnakeCase leaves an empty string alone', () {
    expect(humanizeSnakeCase(''), '');
  });
}
