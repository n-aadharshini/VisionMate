import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/location_model.dart';
import '../services/current_geocoding_service.dart';
import '../services/current_location_service.dart';
import '../services/current_location_tts_service.dart';

class CurrentLocationController extends ChangeNotifier {
  CurrentLocationController({
    CurrentLocationService? locationService,
    CurrentGeocodingService? geocodingService,
    CurrentLocationTtsService? ttsService,
  }) : _locationService = locationService ?? CurrentLocationService(),
       _geocodingService = geocodingService ?? CurrentGeocodingService(),
       _ttsService = ttsService ?? CurrentLocationTtsService();

  final CurrentLocationService _locationService;
  final CurrentGeocodingService _geocodingService;
  final CurrentLocationTtsService _ttsService;
  CurrentLocation? location;
  String status = 'Tap Refresh to get your current location.';
  bool isLoading = false;

  Future<void> refresh() async {
    if (isLoading) return;
    isLoading = true;
    status = 'Fetching current location...';
    notifyListeners();
    try {
      final coordinates = await _locationService.fetch();
      location = coordinates.withAddress(await _geocodingService.addressFor(coordinates));
      status = location!.address == null
          ? 'Current location found. Address unavailable.'
          : 'Current location updated.';
      await _ttsService.announce(location!);
    } on CurrentLocationException catch (error) {
      status = error.message;
      await _ttsService.error(error.message);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Adapter for the existing assistant to call without importing UI.
  Future<void> handleVoiceCommand(String command) async {
    final normalized = command.toLowerCase().trim();
    if (['where am i?', 'where am i', 'current location', 'my location'].contains(normalized)) {
      await refresh();
    }
  }

  Future<void> openInMaps() async {
    final current = location;
    if (current == null) return;
    final opened = await launchUrl(Uri.parse(current.mapsUrl), mode: LaunchMode.externalApplication);
    if (!opened) {
      status = 'Unable to open Google Maps.';
      await _ttsService.error(status);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _ttsService.dispose();
    super.dispose();
  }
}
