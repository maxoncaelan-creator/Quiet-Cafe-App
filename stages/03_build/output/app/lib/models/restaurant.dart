// Mirrors the shape written by data-pipeline/src/pipeline.js
// (see stages/03_build/output/data-pipeline/data/restaurants.json)
// and the field-level detail in stage 2's data-schema.md.

class SignalScore {
  final num? subscore;

  const SignalScore({required this.subscore});

  factory SignalScore.fromJson(Map<String, dynamic> json) {
    return SignalScore(subscore: json['subscore'] as num?);
  }
}

class MicSignal extends SignalScore {
  final int readingCountIos;
  final int readingCountAndroid;

  const MicSignal({
    required super.subscore,
    required this.readingCountIos,
    required this.readingCountAndroid,
  });

  factory MicSignal.fromJson(Map<String, dynamic> json) {
    return MicSignal(
      subscore: json['subscore'] as num?,
      readingCountIos: (json['readingCountIos'] as num?)?.toInt() ?? 0,
      readingCountAndroid: (json['readingCountAndroid'] as num?)?.toInt() ?? 0,
    );
  }

  int get totalReadings => readingCountIos + readingCountAndroid;
}

class Restaurant {
  final String placeId;
  final String? yelpId;
  final String name;
  final String? cuisine;
  final int? priceLevel;
  final String? address;
  final String? suburb;
  final double? lat;
  final double? lng;
  final double? googleRating;
  final double? yelpRating;

  final SignalScore review;
  final SignalScore popular;
  final MicSignal mic;

  final double? quietnessScore;
  final String? confidence; // 'low' | 'medium' | 'high' | null
  final int signalCount;

  const Restaurant({
    required this.placeId,
    this.yelpId,
    required this.name,
    this.cuisine,
    this.priceLevel,
    this.address,
    this.suburb,
    this.lat,
    this.lng,
    this.googleRating,
    this.yelpRating,
    required this.review,
    required this.popular,
    required this.mic,
    this.quietnessScore,
    this.confidence,
    required this.signalCount,
  });

  bool get hasEnoughData => quietnessScore != null;

  factory Restaurant.fromJson(Map<String, dynamic> json) {
    final signals = json['signals'] as Map<String, dynamic>;
    return Restaurant(
      placeId: json['placeId'] as String,
      yelpId: json['yelpId'] as String?,
      name: json['name'] as String,
      cuisine: json['cuisine'] as String?,
      priceLevel: (json['priceLevel'] as num?)?.toInt(),
      address: json['address'] as String?,
      suburb: json['suburb'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      googleRating: (json['googleRating'] as num?)?.toDouble(),
      yelpRating: (json['yelpRating'] as num?)?.toDouble(),
      review: SignalScore.fromJson(signals['review'] as Map<String, dynamic>),
      popular: SignalScore.fromJson(signals['popular'] as Map<String, dynamic>),
      mic: MicSignal.fromJson(signals['mic'] as Map<String, dynamic>),
      quietnessScore: (json['quietnessScore'] as num?)?.toDouble(),
      confidence: json['confidence'] as String?,
      signalCount: (json['signalCount'] as num?)?.toInt() ?? 0,
    );
  }
}
