import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/location_model.dart';
import 'current_location_controller.dart';

class CurrentLocationScreen extends StatelessWidget {
  const CurrentLocationScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => CurrentLocationController(),
    child: const _CurrentLocationView(),
  );
}

class _CurrentLocationView extends StatelessWidget {
  const _CurrentLocationView();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CurrentLocationController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Current Location')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                controller.status,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 24),
            if (controller.isLoading)
              const Center(
                child: Column(children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Fetching current location...')]),
              )
            else if (controller.location != null)
              _LocationCard(location: controller.location!),
            const SizedBox(height: 24),
            SizedBox(
              height: 58,
              child: FilledButton.icon(
                onPressed: controller.isLoading ? null : controller.refresh,
                icon: const Icon(Icons.my_location),
                label: const Text('Refresh Location', style: TextStyle(fontSize: 19)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 58,
              child: OutlinedButton.icon(
                onPressed: controller.location == null ? null : controller.openInMaps,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Open in Google Maps', style: TextStyle(fontSize: 19)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.location});
  final CurrentLocation location;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Current Address', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(location.address ?? 'Address unavailable; coordinates are shown below.', style: const TextStyle(fontSize: 18)),
          const Divider(height: 28),
          Text('Latitude: ${location.latitude}', style: const TextStyle(fontSize: 17)),
          Text('Longitude: ${location.longitude}', style: const TextStyle(fontSize: 17)),
          Text('Accuracy: ${location.accuracyMeters.toStringAsFixed(1)} meters', style: const TextStyle(fontSize: 17)),
          Text('Updated: ${location.updatedAt.toLocal()}', style: const TextStyle(fontSize: 17)),
        ],
      ),
    ),
  );
}
