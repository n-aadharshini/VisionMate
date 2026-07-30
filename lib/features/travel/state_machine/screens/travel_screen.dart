import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_ui.dart';
import '../../../assistant/services/conversation_controller.dart';
import 'journey_screen.dart';

class TravelScreen extends StatefulWidget {
  const TravelScreen({super.key});
  @override
  State<TravelScreen> createState() => _TravelScreenState();
}

class _TravelScreenState extends State<TravelScreen> {
  late final Timer _timer;
  int _minutes = 6;
  bool _bus = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _minutes > 0) setState(() => _minutes--);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final destination = ModalRoute.of(context)?.settings.arguments is String
        ? ModalRoute.of(context)!.settings.arguments as String
        : 'T Nagar';
    final conversation = ConversationControllerScope.of(context);
    final message = conversation.messages.isEmpty
        ? 'Ask when the next one arrives.'
        : conversation.messages.last.text;
    final options = _bus
        ? const [
            ('Bus 47', 'CMBT Platform 5', 6),
            ('Bus 21B', 'CMBT Platform 2', 14),
            ('Bus 47A', 'CMBT Platform 5', 27),
          ]
        : const [
            ('Metro Blue Line', 'CMBT Metro', 8),
            ('Metro Green Line', 'Arumbakkam', 16),
          ];
    return FeatureScreenShell(
      title: destination,
      bottom: MiniChatStrip(
        text: message,
        onTap: () => Navigator.of(context).pop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('Bus'),
                icon: Icon(Icons.directions_bus_rounded),
              ),
              ButtonSegment(
                value: false,
                label: Text('Train'),
                icon: Icon(Icons.train_rounded),
              ),
            ],
            selected: {_bus},
            onSelectionChanged: (value) => setState(() {
              _bus = value.first;
              _minutes = _bus ? 6 : 8;
            }),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    options.first.$1,
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    options.first.$2,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _minutes == 0
                        ? 'Arriving now'
                        : 'Arriving in $_minutes min',
                    style: const TextStyle(
                      fontSize: 20,
                      color: AppColors.cyan,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Next arrivals',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: options.length - 1,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = options[index + 1];
                return AppCard(
                  child: ListTile(
                    leading: const Icon(
                      Icons.directions_bus_rounded,
                      color: AppColors.cyan,
                    ),
                    title: Text(item.$1),
                    subtitle: Text(item.$2),
                    trailing: Text(
                      '${item.$3} min',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                );
              },
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).pushNamed('/travel/live', arguments: destination),
            icon: const Icon(Icons.directions_walk_rounded),
            label: const Text('Start live journey'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
  }
}

class LiveTravelScreen extends StatelessWidget {
  const LiveTravelScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const JourneyScreen(title: 'Live journey');
}
