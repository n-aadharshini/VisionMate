import 'dart:async';

import '../../../../core/services/location_service.dart';
import '../../../../core/services/sms_service.dart';
import '../domain/sos_contact.dart';
import 'sos_local_datasource.dart';
import 'sos_remote_datasource.dart';

/// Result of a full send-alert operation, returned up through the
/// use case to the controller.
class SosSendOutcome {
  final bool success;
  final String message;

  const SosSendOutcome({required this.success, required this.message});
}

abstract class SosRepository {
  Future<List<SosContact>> loadContacts();
  Future<void> saveContacts(List<SosContact> contacts);
  Future<void> addContact(SosContact contact);
  Future<void> updateContact(SosContact contact);
  Future<void> deleteContact(String id);

  Future<SosSendOutcome> sendAlert({
    required List<SosContact> contacts,
    required SosTriggerType triggerType,
    required SosLocation? location,
    String? message,
  });

  Future<List<SosHistoryEntry>> loadHistory();
}

/// Default implementation coordinating the remote and local
/// datasources: it sends the alert remotely, then always records
/// the attempt locally (success or failure) so the SOS history and
/// "last alert" state stay accurate even offline.
class SosRepositoryImpl implements SosRepository {
  SosRepositoryImpl({
    required SosRemoteDatasource remoteDatasource,
    required SosLocalDatasource localDatasource,
    SmsService? smsService,
  }) : _remote = remoteDatasource,
       _local = localDatasource,
       _sms = smsService ?? SmsService();

  final SosRemoteDatasource _remote;
  final SosLocalDatasource _local;
  final SmsService _sms;

  @override
  Future<List<SosContact>> loadContacts() => _local.getCachedContacts();

  @override
  Future<void> saveContacts(List<SosContact> contacts) =>
      _local.cacheContacts(contacts);
  @override
  Future<void> addContact(SosContact contact) => _local.addContact(contact);
  @override
  Future<void> updateContact(SosContact contact) =>
      _local.updateContact(contact);
  @override
  Future<void> deleteContact(String id) => _local.deleteContact(id);

  @override
  Future<SosSendOutcome> sendAlert({
    required List<SosContact> contacts,
    required SosTriggerType triggerType,
    required SosLocation? location,
    String? message,
  }) async {
    final timestamp = DateTime.now();
    final alertMessage =
        message ?? _buildMessage(triggerType, timestamp, location);
    final results = await Future.wait([
      _sms.sendSos(
        contacts.map((contact) => contact.phoneNumber).toList(),
        alertMessage,
      ),
      _remote.sendSosAlert(
        contacts: contacts,
        triggerType: triggerType,
        timestamp: timestamp,
        location: location,
        message: alertMessage,
      ),
    ]);
    final smsSuccess = results[0] as bool;

    await _local.appendHistory(
      SosHistoryEntry(
        triggerType: triggerType,
        timestamp: timestamp,
        location: location,
        success: smsSuccess,
      ),
    );

    if (smsSuccess) {
      await _local.saveLastAlertState(
        triggerType: triggerType,
        timestamp: timestamp,
        location: location,
      );

      // Fire-and-forget: also notify emergency services backend.
      unawaited(
        _remote.notifyEmergencyServices(
          location: location,
          timestamp: timestamp,
        ),
      );

      return const SosSendOutcome(
        success: true,
        message: 'Emergency contacts have been alerted.',
      );
    }

    return SosSendOutcome(
      success: false,
      message:
          'SMS could not be sent. Check SMS permission and mobile service.',
    );
  }

  @override
  Future<List<SosHistoryEntry>> loadHistory() => _local.getHistory();

  String _buildMessage(
    SosTriggerType triggerType,
    DateTime timestamp,
    SosLocation? location,
  ) {
    final locationText = location == null
        ? 'Location unavailable.'
        : 'Location: https://maps.google.com/?q=${location.latitude},${location.longitude}';
    return 'VisionMate ${triggerType.name} SOS at ${timestamp.toLocal().toIso8601String()}. $locationText';
  }
}
