
import 'dart:convert';

import '../../../../core/services/location_service.dart';
import '../domain/sos_contact.dart';

/// Trigger type carried in the SOS payload so the backend (or, in
/// this prototype, the mock endpoint) knows whether this alert was
/// user-initiated SOS request.
enum SosTriggerType { manual }

class SosHttpResponse {
  const SosHttpResponse({required this.statusCode});

  final int statusCode;
}

class SosHttpClient {
  Future<SosHttpResponse> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    return const SosHttpResponse(statusCode: 200);
  }
}

/// Result returned by the remote datasource after attempting to
/// send an SOS alert.
class SosSendResult {
  final bool success;
  final String? serverMessage;

  const SosSendResult({required this.success, this.serverMessage});
}

/// Handles all network calls related to SOS: sending the alert
/// payload to the backend, and, if configured, notifying an
/// emergency-services integration.
///
/// For this prototype the endpoint is a placeholder base URL.
/// Swap [baseUrl] for your real backend/Firebase Cloud Function.
class SosRemoteDatasource {
  SosRemoteDatasource({
    SosHttpClient? client,
    this.baseUrl = 'https://api.visionmate.example.com',
  }) : _client = client ?? SosHttpClient();

  final SosHttpClient _client;
  final String baseUrl;

  Future<SosSendResult> sendSosAlert({
    required List<SosContact> contacts,
    required SosTriggerType triggerType,
    required DateTime timestamp,
    SosLocation? location,
    String? message,
  }) async {
    final payload = {
      'triggerType': triggerType.name,
      'timestamp': timestamp.toIso8601String(),
      'location': location?.toJson(),
      'message': message ?? 'Emergency SOS triggered via VisionMate.',
      'contacts': contacts.map((c) => c.toJson()).toList(),
    };

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/sos/send'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const SosSendResult(success: true);
      }

      return SosSendResult(
        success: false,
        serverMessage: 'Server responded with ${response.statusCode}',
      );
    } catch (e) {
      // In a prototype/demo without a live backend, network calls
      // will typically fail here. The repository layer decides how
      // to handle that (e.g. still show local success for demo
      // purposes, or surface the error).
      return SosSendResult(success: false, serverMessage: e.toString());
    }
  }

  /// Optionally forwards the alert to an emergency-services
  /// integration endpoint. No-op stub for the prototype.
  Future<void> notifyEmergencyServices({
    required SosLocation? location,
    required DateTime timestamp,
  }) async {
    try {
      await _client.post(
        Uri.parse('$baseUrl/sos/emergency-services'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'location': location?.toJson(),
          'timestamp': timestamp.toIso8601String(),
        }),
      );
    } catch (_) {
      // Best-effort only; failures here should not block the main
      // contact-alert flow.
    }
  }
}
