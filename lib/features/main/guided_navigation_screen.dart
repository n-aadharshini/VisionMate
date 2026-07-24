import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_ui.dart';
import '../assistant/services/tts_service.dart';
import '../assistant/services/landmark_check_in_service.dart';
import '../assistant/services/object_detection_service.dart';
import '../assistant/services/depth_estimation_service.dart';
import '../assistant/services/semantic_segmentation_service.dart';

enum JourneyGuidanceMode { guided, detailsOnly }

class GuidedNavigationScreen extends StatefulWidget {
  const GuidedNavigationScreen({super.key});

  @override
  State<GuidedNavigationScreen> createState() => _GuidedNavigationScreenState();
}

class _GuidedNavigationScreenState extends State<GuidedNavigationScreen> {
  JourneyGuidanceMode? _guidanceMode;
  final TtsService _ttsService = TtsService();
  final LandmarkCheckInService _landmarkService = LandmarkCheckInService();
  final ObjectDetectionService _objectDetectionService = ObjectDetectionService();
  final DepthEstimationService _depthEstimationService = DepthEstimationService();
  final SemanticSegmentationService _segmentationService =
      SemanticSegmentationService();
  String? _landmarkMessage;
  bool _isCheckingLandmark = false;

  Future<void> _runLandmarkCheckIn() async {
    setState(() => _isCheckingLandmark = true);
    final photoPath = await Navigator.of(context).pushNamed<String>(
      '/camera-capture',
    );
    if (!mounted) return;
    if (photoPath == null) {
      setState(() {
        _isCheckingLandmark = false;
        _landmarkMessage =
            'No photo was captured. Tap the camera button whenever you are ready to try again.';
      });
      return;
    }
    final result = await _landmarkService.checkInWithCapturedPhoto(photoPath);
    var message = result.message;
    if (result.photoPath != null) {
      try {
        final objects = await _objectDetectionService.detectFromFile(
          result.photoPath!,
        );
        if (objects.isNotEmpty) {
          final labels = objects.map((object) => object.label).join(', ');
          message = '$message I can also see: $labels.';
        } else {
          message = '$message I could not confidently identify an object in that photo.';
        }
      } catch (_) {
        message = '$message I could not analyse the photo this time.';
      }
      try {
        final photoBytes = await File(result.photoPath!).readAsBytes();
        final photo = image.decodeImage(photoBytes);
        if (photo != null) {
          final depth = await _depthEstimationService.estimate(photo);
          if (depth.hasMeaningfulSeparation) {
            message = '$message A relative-depth check suggests the nearest visible area is toward the ${depth.nearestArea}. This is not a measured distance, so I will not use it as an obstacle warning.';
          }
        }
      } catch (_) {
        // Depth is an optional, on-demand enhancement; GPS guidance remains
        // available if the model cannot run on this device.
      }
      try {
        final photoBytes = await File(result.photoPath!).readAsBytes();
        final photo = image.decodeImage(photoBytes);
        if (photo != null) {
          final segmentation = await _segmentationService.segment(photo);
          if (segmentation.regions.isNotEmpty) {
            final regions = segmentation.regions
                .map((region) => region.label)
                .join(', ');
            message = '$message Scene regions detected: $regions.';
          }
        }
      } catch (_) {
        // Segmentation is optional and never changes the GPS fallback.
      }
    }
    if (!mounted) return;
    setState(() {
      _isCheckingLandmark = false;
      _landmarkMessage = message;
    });
    await _ttsService.speak(message);
  }

  @override
  void dispose() {
    _objectDetectionService.dispose();
    _depthEstimationService.dispose();
    _segmentationService.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ttsService.speak(
        'Want me to guide you the whole way there, step by step, or would you rather I just tell you the route and distance now?',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final destination = ModalRoute.of(context)?.settings.arguments as String? ??
        'Home';

    return AppPage(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),
        const Row(children: [
          AppBackButton(),
          SizedBox(width: 7),
          Text('Navigate', style: TextStyle(fontWeight: FontWeight.w800)),
          Spacer(),
          Icon(Icons.more_vert),
        ]),
        const SizedBox(height: 14),
        Text(
          'Heading to $destination',
          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        const Text(
          'Want me to guide you the whole way there, step by step, or would you rather I just tell you the route and distance now?',
          style: TextStyle(color: AppColors.muted, height: 1.35),
        ),
        const SizedBox(height: 18),
        _GuidanceChoice(
          icon: Icons.directions_walk_rounded,
          title: 'Guide me all the way',
          subtitle: 'Turn prompts and friendly check-ins',
          selected: _guidanceMode == JourneyGuidanceMode.guided,
          onTap: () => setState(
            () => _guidanceMode = JourneyGuidanceMode.guided,
          ),
        ),
        const SizedBox(height: 10),
        _GuidanceChoice(
          icon: Icons.route_rounded,
          title: 'Just tell me the route',
          subtitle: 'Distance, time, and first direction',
          selected: _guidanceMode == JourneyGuidanceMode.detailsOnly,
          onTap: () => setState(
            () => _guidanceMode = JourneyGuidanceMode.detailsOnly,
          ),
        ),
        const SizedBox(height: 18),
        if (_guidanceMode != null)
          AppCard(
            child: ListTile(
              leading: Icon(
                _guidanceMode == JourneyGuidanceMode.guided
                    ? Icons.favorite_rounded
                    : Icons.info_outline_rounded,
                color: AppColors.cyan,
              ),
              title: Text(
                _guidanceMode == JourneyGuidanceMode.guided
                    ? 'Guided mode is ready'
                    : 'Route details',
              ),
              subtitle: Text(
                _guidanceMode == JourneyGuidanceMode.guided
                    ? 'I’ll stay with you and share the next step when navigation is available.'
                    : 'About 2.6 km away, around 18 minutes. Start by heading north on Beach Road.',
              ),
            ),
          )
        else
          const AppCard(
            child: ListTile(
              leading: Icon(Icons.mic_rounded, color: AppColors.cyan),
              title: Text('Voice destination'),
              subtitle: Text('Choose how you would like VisionMate to help.'),
            ),
          ),
        if (_guidanceMode == JourneyGuidanceMode.guided) ...[
          const SizedBox(height: 12),
          PrimaryButton(
            label: _isCheckingLandmark
                ? 'Checking your location...'
                : 'Check landmark with camera',
            icon: Icons.camera_alt_rounded,
            onPressed: _isCheckingLandmark ? () {} : _runLandmarkCheckIn,
          ),
        ],
        if (_landmarkMessage != null) ...[
          const SizedBox(height: 12),
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                _landmarkMessage!,
                style: const TextStyle(color: AppColors.muted),
              ),
            ),
          ),
        ],
        const Spacer(),
        const AppCard(
          child: ListTile(
            leading: Icon(Icons.home_rounded, color: AppColors.cyan),
            title: Text('Static demo fallback'),
            subtitle: Text('Home · Benson Ave · Office remain available.'),
          ),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }
}

class _GuidanceChoice extends StatelessWidget {
  const _GuidanceChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AppCard(
          color: selected
              ? AppColors.blue.withValues(alpha: .22)
              : AppColors.surface,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.cyan.withValues(alpha: .15),
              child: Icon(icon, color: AppColors.cyan),
            ),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.chevron_right_rounded,
              color: selected ? AppColors.cyan : AppColors.muted,
            ),
          ),
        ),
      );
}
