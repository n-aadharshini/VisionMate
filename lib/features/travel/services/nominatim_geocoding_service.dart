import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'geocoding_service.dart';

/// Free implementation of [GeocodingService] using OpenStreetMap's
/// Nominatim geocoding API — no API key, no billing account required.
///
/// Trade-offs vs a paid provider like Google's Geocoding API:
/// - No cost, no card on file — good for development/testing without
///   committing to a billing account.
/// - Nominatim's usage policy caps the free public instance at
///   ~1 request/second and requires an identifying `User-Agent` header
///   (both handled below). Fine for one person testing on a phone; NOT
///   fine for production traffic at real scale — at that point either
///   self-host Nominatim or switch to a paid provider. Swapping is a
///   one-line change wherever this is constructed, since
///   [GeocodingService] is an interface.
/// - Generally less accurate than Google for informal/local place names
///   (small colleges, shop names) since it's built from OpenStreetMap
///   data, which has patchier coverage in some areas than Google's index.
///   Well-known places, addresses, and landmarks resolve fine.
///
/// Policy reference: https://operations.osmfoundation.org/policies/nominatim/
class NominatimGeocodingService implements GeocodingService {
  NominatimGeocodingService({
    http.Client? client,
    this.appIdentifier = 'VisionMate (accessibility navigation app)',
  }) : _client = client ?? http.Client();

  static const _endpoint = 'https://nominatim.openstreetmap.org/search';
  static const _timeout = Duration(seconds: 8);

  /// Nominatim's usage policy requires a descriptive User-Agent
  /// identifying the calling app — sent with every request below.
  final String appIdentifier;

  final http.Client _client;

  @override
  Future<GeocodedPlace?> geocode(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.parse(_endpoint).replace(queryParameters: {
      'q': trimmed,
      'format': 'jsonv2',
      'limit': '1',
      // Nudges results toward India (VisionMate's stated audience per
      // vision_mate_brain.dart's system prompt) — a soft preference, not
      // a hard filter, same role as 'region' in GoogleGeocodingService.
      'countrycodes': 'in',
    });

    final response = await _client
        .get(uri, headers: {'User-Agent': appIdentifier})
        .timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Nominatim request failed with status ${response.statusCode}.',
      );
    }

    final results = jsonDecode(response.body) as List<dynamic>;
    if (results.isEmpty) return null;

    final first = results.first as Map<String, dynamic>;
    final lat = double.tryParse(first['lat']?.toString() ?? '');
    final lng = double.tryParse(first['lon']?.toString() ?? '');
    if (lat == null || lng == null) return null;

    return GeocodedPlace(
      displayName:
          _shortDisplayName(first['display_name'] as String?) ?? trimmed,
      latitude: lat,
      longitude: lng,
    );
  }

  /// Nominatim's `display_name` is a full address, similarly long to
  /// Google's `formatted_address` — take just the first comma-separated
  /// segment so `JourneyPlan.summarySpeech` reads naturally aloud.
  String? _shortDisplayName(String? displayName) {
    if (displayName == null || displayName.trim().isEmpty) return null;
    final firstSegment = displayName.split(',').first.trim();
    return firstSegment.isEmpty ? null : firstSegment;
  }
}
