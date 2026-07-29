import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around local notifications used to inform
/// the user about SOS status changes.
class NotificationService {
  bool _initialized = false;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<void> showSosSentNotification() async {
    await _show(
      id: 2,
      title: 'SOS sent',
      body: 'Your emergency contacts have been alerted with your location.',
    );
  }

  Future<void> showSosFailedNotification(String reason) async {
    await _show(id: 3, title: 'SOS failed to send', body: reason);
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'sos_alerts',
        'SOS alerts',
        channelDescription: 'VisionMate emergency alerts',
        importance: Importance.max,
        priority: Priority.high,
      ),
    );
    await _plugin.show(id, title, body, details);
  }
}
