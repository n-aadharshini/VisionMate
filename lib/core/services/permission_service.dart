import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Centralizes all permission requests needed by the SOS feature:
/// location (to attach coordinates to alerts), phone (to place
/// emergency calls) and notifications (to show local alerts/status).
class PermissionService {
  Future<bool> requestLocationPermission() async {
    var status = await Permission.locationWhenInUse.status;
    if (status.isPermanentlyDenied) {
      // Android no longer shows its permission dialog after "Don't ask again".
      // Take the user to this app's settings so Location can be enabled.
      await openAppSettings();
      status = await Permission.locationWhenInUse.status;
    }
    if (!status.isGranted && !status.isLimited) {
      status = await Permission.locationWhenInUse.request();
    }
    if (!status.isGranted && !status.isLimited) {
      // A denied request cannot be overridden by Flutter. Open the exact app
      // settings page so the user can turn Location on for VisionMate.
      await openAppSettings();
      status = await Permission.locationWhenInUse.status;
    }
    return status.isGranted || status.isLimited;
  }

  Future<bool> requestPhonePermission() async {
    return (await Permission.phone.request()).isGranted;
  }

  Future<bool> requestNotificationPermission() async {
    return (await Permission.notification.request()).isGranted;
  }

  Future<bool> requestSmsPermission() async =>
      (await Permission.sms.request()).isGranted;

  Future<bool> requestMicrophonePermission() async =>
      (await Permission.microphone.request()).isGranted;

  /// Requests the SOS permissions together when the SOS screen opens.
  Future<Map<String, bool>> requestAllSosPermissions() async {
    final permissions = <Permission>[
      Permission.locationWhenInUse,
      Permission.phone,
      Permission.notification,
      Permission.microphone,
      Permission.sms,
      if (Platform.isAndroid) Permission.activityRecognition,
    ];
    final statuses = await permissions.request();
    return {
      'location': _isGranted(statuses[Permission.locationWhenInUse]),
      'phone': _isGranted(statuses[Permission.phone]),
      'notification': _isGranted(statuses[Permission.notification]),
      'microphone': _isGranted(statuses[Permission.microphone]),
      'sms': _isGranted(statuses[Permission.sms]),
      'activityRecognition': Platform.isAndroid
          ? _isGranted(statuses[Permission.activityRecognition])
          : true,
    };
  }

  Future<bool> isPhonePermissionGranted() async =>
      _isGranted(await Permission.phone.status);

  /// READ_PHONE_STATE and CALL_PHONE belong to Android's phone permission
  /// group, so this confirms the state-monitoring grant before listening.
  Future<bool> isPhoneStatePermissionGranted() => isPhonePermissionGranted();

  bool _isGranted(PermissionStatus? status) =>
      status == PermissionStatus.granted || status == PermissionStatus.limited;

  Future<bool> isLocationPermissionGranted() async {
    final status = await Permission.locationWhenInUse.status;
    return status.isGranted || status.isLimited;
  }
}
