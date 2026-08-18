// Run with `flutter test`. NOT executed in this environment — Flutter SDK
// is not installed here. See README "What's verified vs not."

import 'package:flutter_test/flutter_test.dart';
import 'package:quiet_restaurant_finder/models/restaurant.dart';

void main() {
  test('Restaurant.fromJson parses a fully-scored restaurant', () {
    final json = {
      'placeId': 'sample-001',
      'yelpId': 'sample-yelp-001',
      'name': 'The Quiet Fork',
      'cuisine': 'Modern Australian',
      'priceLevel': 3,
      'address': '12 Quiet St, Surry Hills NSW',
      'suburb': 'Surry Hills',
      'lat': -33.8886,
      'lng': 151.2094,
      'googleRating': 4.6,
      'yelpRating': 4.5,
      'signals': {
        'review': {'positiveCount': 5, 'negativeCount': 1, 'subscore': 83.33},
        'popular': {'busynessPercent': 35, 'subscore': 65},
        'mic': {'readingCountIos': 2, 'readingCountAndroid': 1, 'subscore': 73.33},
      },
      'quietnessScore': 74.67,
      'confidence': 'Certain',
      'signalCount': 3,
    };

    final restaurant = Restaurant.fromJson(json);

    expect(restaurant.name, 'The Quiet Fork');
    expect(restaurant.hasEnoughData, isTrue);
    expect(restaurant.confidence, 'Certain');
    expect(restaurant.mic.totalReadings, 3);
  });

  test('Restaurant.fromJson parses a cold-start restaurant with null score', () {
    final json = {
      'placeId': 'sample-004',
      'name': 'New Opening Cafe',
      'signals': {
        'review': {'positiveCount': 0, 'negativeCount': 0, 'subscore': null},
        'popular': {'busynessPercent': null, 'subscore': null},
        'mic': {'readingCountIos': 0, 'readingCountAndroid': 0, 'subscore': null},
      },
      'quietnessScore': null,
      'confidence': null,
      'signalCount': 0,
    };

    final restaurant = Restaurant.fromJson(json);

    expect(restaurant.hasEnoughData, isFalse);
    expect(restaurant.quietnessScore, isNull);
  });
}
