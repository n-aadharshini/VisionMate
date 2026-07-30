import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/services/transport_query_service.dart';
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
  final _transportService = TransportQueryService();
  String? _destination;
  List<Map<String, dynamic>> _routes = [];
  Map<String, int?> _headways = {};
  String _status = 'Initializing...';
  String? _lastResponse;
  bool _loading = true;
  bool _dbReady = false;
  ConversationController? _conversation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _conversation = ConversationControllerScope.of(context);
    final dest = ModalRoute.of(context)?.settings.arguments;
    final newDest = dest is String && dest.trim().isNotEmpty ? dest.trim() : null;
    if (newDest != _destination) {
      _destination = newDest;
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      await _transportService.ensureDatabase();
      _dbReady = true;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Could not load transport data.';
        _loading = false;
      });
      return;
    }

    if (_destination != null) {
      await _searchForDestination(_destination!);
    } else {
      if (!mounted) return;
      setState(() {
        _status = 'Ask about a bus or a place to go.';
        _loading = false;
      });
    }
  }

  Future<void> _searchForDestination(String destination) async {
    try {
      final stops = await _transportService.findStops(destination);
      if (stops.isEmpty) {
        if (!mounted) return;
        setState(() {
          _routes = [];
          _status = 'I couldn\'t find that stop. Try saying the area or landmark name.';
          _loading = false;
        });
        return;
      }

      final routes = await _transportService.busesToDestination(destination);
      _routes = routes;

      final headways = <String, int?>{};
      for (final r in routes) {
        final name = r['route_short_name'] as String? ?? '';
        if (name.isNotEmpty && stops.isNotEmpty) {
          headways[name] = await _transportService.approximateHeadwayMinutes(
            name, stops.first['stop_name'] as String,
          );
        }
      }
      _headways = headways;

      if (!mounted) return;
      final response = _buildResponse(routes);
      _lastResponse = response;
      setState(() {
        _status = routes.isEmpty
            ? 'I couldn\'t find reliable transport information right now. Please try again later.'
            : 'Found ${routes.length} route${routes.length == 1 ? '' : 's'} to $destination.';
        _loading = false;
      });

      _conversation?.speak(response);
      _registerHandler();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _routes = [];
        _status = 'I couldn\'t find reliable transport information right now. Please try again later.';
        _loading = false;
      });
    }
  }

  String _buildResponse(List<Map<String, dynamic>> routes) {
    if (routes.isEmpty) {
      return 'I couldn\'t find reliable transport information right now. Please try again later.';
    }

    final names = routes
        .map((r) => r['route_short_name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList();

    if (names.isEmpty) {
      return 'I couldn\'t find reliable transport information right now. Please try again later.';
    }

    final listStr = names.length > 1
        ? '${names.sublist(0, names.length - 1).join(', ')} or ${names.last}'
        : names.first;
    final sentence = 'You can take bus $listStr to reach $_destination.';

    final headwayParts = <String>[];
    for (final name in names) {
      final hw = _headways[name];
      if (hw != null) {
        headwayParts.add('$name runs roughly every $hw minutes');
      }
    }
    if (headwayParts.isNotEmpty) {
      return '$sentence ${headwayParts.join('. ')}.';
    }
    return sentence;
  }

  void _registerHandler() {
    _conversation?.setFeatureVoiceCommandHandler(_handleTravelCommand);
  }

  Future<FeatureVoiceCommandResult?> _handleTravelCommand(String transcript) async {
    if (!_dbReady) return null;
    final normalized = transcript.toLowerCase().trim();

    if (normalized.contains('repeat') || normalized.contains('say again')) {
      if (_lastResponse != null) {
        return FeatureVoiceCommandResult.handled(reply: _lastResponse);
      }
      return null;
    }

    if (normalized.contains('clear') || normalized.contains('go back')) {
      return FeatureVoiceCommandResult.handled(reply: 'Going back.');
    }

    if (normalized.contains('which bus') || normalized.contains('how do i get') || normalized.contains('to ')) {
      final dest = _extractPlace(normalized);
      if (dest != null) {
        return _handleDestinationQuery(dest);
      }
    }

    if (normalized.contains('from ') && normalized.contains(' to ')) {
      final parts = normalized.split(' to ');
      final fromPart = parts[0];
      final toPart = parts.length > 1 ? parts[1] : '';
      final origin = _extractPlace(fromPart);
      final destination = _extractPlace(toPart);
      if (origin != null && destination != null) {
        return _handleBetweenQuery(origin, destination);
      }
    }

    if (_containsAny(normalized, ['when', 'next', 'timing', 'schedule', 'headway'])) {
      final route = _extractRouteNumber(normalized);
      if (route != null && _destination != null) {
        return _handleScheduleQuery(route, _destination!);
      }
    }

    return null;
  }

  Future<FeatureVoiceCommandResult> _handleDestinationQuery(String dest) async {
    try {
      final stops = await _transportService.findStops(dest);
      if (stops.isEmpty) {
        return FeatureVoiceCommandResult.handled(
          reply: 'I couldn\'t find that stop. Try saying the area or landmark name.',
        );
      }
      final routes = await _transportService.busesToDestination(dest);
      if (routes.isEmpty) {
        return FeatureVoiceCommandResult.handled(
          reply: 'I couldn\'t find reliable transport information right now. Please try again later.',
        );
      }
      final names = routes.map((r) => r['route_short_name'] as String? ?? '').where((n) => n.isNotEmpty).toList();
      final listStr = names.length > 1
          ? '${names.sublist(0, names.length - 1).join(', ')} or ${names.last}'
          : names.first;
      final msg = 'You can take bus $listStr to reach $dest.';
      return FeatureVoiceCommandResult.handled(reply: msg);
    } catch (_) {
      return FeatureVoiceCommandResult.handled(
        reply: 'I couldn\'t find reliable transport information right now. Please try again later.',
      );
    }
  }

  Future<FeatureVoiceCommandResult> _handleBetweenQuery(String origin, String destination) async {
    try {
      final routes = await _transportService.busesBetween(origin, destination);
      if (routes.isEmpty) {
        return FeatureVoiceCommandResult.handled(
          reply: 'I couldn\'t find reliable transport information right now. Please try again later.',
        );
      }
      final names = routes.map((r) => r['route_short_name'] as String? ?? '').where((n) => n.isNotEmpty).toList();
      final listStr = names.length > 1
          ? '${names.sublist(0, names.length - 1).join(', ')} or ${names.last}'
          : names.first;
      return FeatureVoiceCommandResult.handled(
        reply: 'You can take bus $listStr from $origin to $destination.',
      );
    } catch (_) {
      return FeatureVoiceCommandResult.handled(
        reply: 'I couldn\'t find reliable transport information right now. Please try again later.',
      );
    }
  }

  Future<FeatureVoiceCommandResult> _handleScheduleQuery(String route, String stop) async {
    try {
      final headway = await _transportService.approximateHeadwayMinutes(route, stop);
      if (headway == null) {
        return FeatureVoiceCommandResult.handled(
          reply: 'Scheduled headway for bus $route is not available at this stop.',
        );
      }
      return FeatureVoiceCommandResult.handled(
        reply: 'Bus $route runs roughly every $headway minutes at $stop.',
      );
    } catch (_) {
      return FeatureVoiceCommandResult.handled(
        reply: 'I couldn\'t find schedule information right now. Please try again later.',
      );
    }
  }

  void _repeatLastResponse() {
    if (_lastResponse != null) _conversation?.speak(_lastResponse!);
  }

  void _clearFeatureHandler() {
    _conversation?.setFeatureVoiceCommandHandler(null);
  }

  @override
  void dispose() {
    _clearFeatureHandler();
    _transportService.dispose();
    super.dispose();
  }

  String? _extractPlace(String text) {
    final match = RegExp(r'(?:to|from|for|reach|at)\s+(.+?)(?:[?.!,]|$)', caseSensitive: false).firstMatch(text);
    final place = match?.group(1)?.trim();
    return (place != null && place.isNotEmpty) ? place : null;
  }

  String? _extractRouteNumber(String text) {
    final match = RegExp(r'\b(bus\s+)?(\d{1,4}[A-Za-z]?)\b', caseSensitive: false).firstMatch(text);
    return match?.group(2);
  }

  bool _containsAny(String text, List<String> keywords) => keywords.any(text.contains);

  @override
  Widget build(BuildContext context) {
    final conversation = ConversationControllerScope.of(context);
    final lastMessage = _lastResponse ?? conversation.messages.lastOrNull?.text ??
        'Ask when the next one arrives.';

    return FeatureScreenShell(
      title: _destination ?? 'Travel',
      bottom: MiniChatStrip(
        text: lastMessage,
        onTap: () => Navigator.of(context).pop(),
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_destination != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'To $_destination',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                if (_routes.isEmpty)
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _status,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: _routes.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        if (index < _routes.length) {
                          final r = _routes[index];
                          final shortName = r['route_short_name'] as String? ?? '';
                          final longName = r['route_long_name'] as String? ?? '';
                          final headway = _headways[shortName];
                          return AppCard(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.blue.withValues(alpha: 0.25),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          shortName,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w900,
                                            color: AppColors.cyan,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      if (headway != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.surfaceHigh.withValues(alpha: 0.5),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '~${headway}min',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.muted,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Scheduled',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: AppColors.muted.withValues(alpha: 0.6),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (longName.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      longName,
                                      style: const TextStyle(color: AppColors.muted, fontSize: 14),
                                    ),
                                  ],
                                  Text(
                                    'Tap to hear arrival details',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.muted.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: AppColors.outline),
                                  ),
                                  onPressed: _repeatLastResponse,
                                  icon: const Icon(Icons.replay_rounded, size: 20),
                                  label: const Text('Repeat arrival details'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: AppColors.outline),
                                  ),
                                  onPressed: () => Navigator.of(context).pushNamed(
                                    '/travel/live',
                                    arguments: _destination,
                                  ),
                                  icon: const Icon(Icons.directions_walk_rounded, size: 20),
                                  label: const Text('Start live journey'),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
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
