import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/services/location_service.dart';
import '../../../../core/services/sms_service.dart';
import '../../../current_location/services/current_geocoding_service.dart';
import '../../../current_location/services/current_location_service.dart';
import '../domain/sos_contact.dart';
import 'sos_local_datasource.dart';
import 'sos_remote_datasource.dart';

/// Result of a full send-alert operation, returned up through the
/// use case to the controller.
class SosSendOutcome {
  final bool success;
  final String message;
  final SosLocation? location;

  const SosSendOutcome({
    required this.success,
    required this.message,
    this.location,
  });
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
    CurrentLocationService? currentLocationService,
    CurrentGeocodingService? currentGeocodingService,
  }) : _remote = remoteDatasource,
       _local = localDatasource,
       _sms = smsService ?? SmsService(),
       _currentLocationService =
           currentLocationService ?? CurrentLocationService(),
       _currentGeocodingService =
           currentGeocodingService ?? CurrentGeocodingService();

  final SosRemoteDatasource _remote;
  final SosLocalDatasource _local;
  final SmsService _sms;
  final CurrentLocationService _currentLocationService;
  final CurrentGeocodingService _currentGeocodingService;

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
    final resolvedLocation = location ?? await _fetchLocation();
    final alertMessage =
        message ?? _buildMessage(triggerType, timestamp, resolvedLocation);
    final results = await Future.wait([
      _sms.sendSos(
        contacts.map((contact) => contact.phoneNumber).toList(),
        alertMessage,
      ),
      _remote.sendSosAlert(
        contacts: contacts,
        triggerType: triggerType,
        timestamp: timestamp,
        location: resolvedLocation,
        message: alertMessage,
      ),
    ]);
    final smsSuccess = results[0] as bool;

    await _local.appendHistory(
      SosHistoryEntry(
        triggerType: triggerType,
        timestamp: timestamp,
        location: resolvedLocation,
        success: smsSuccess,
      ),
    );

    if (smsSuccess) {
      await _local.saveLastAlertState(
        triggerType: triggerType,
        timestamp: timestamp,
        location: resolvedLocation,
      );

      // Fire-and-forget: also notify emergency services backend.
      unawaited(
        _remote.notifyEmergencyServices(
          location: resolvedLocation,
          timestamp: timestamp,
        ),
      );

      return SosSendOutcome(
        success: true,
        message: 'Emergency contacts have been alerted.',
        location: resolvedLocation,
      );
    }

    return SosSendOutcome(
      success: false,
      message:
          'SMS could not be sent. Check SMS permission and mobile service.',
      location: resolvedLocation,
    );
  }

  Future<SosLocation?> _fetchLocation() async {
    try {
      final current = await _currentLocationService
          .fetch()
          .timeout(const Duration(seconds: 8));
      final address = await _currentGeocodingService
          .addressFor(current)
          .timeout(const Duration(seconds: 8));
      return SosLocation(
        latitude: current.latitude,
        longitude: current.longitude,
        accuracy: current.accuracyMeters,
        readableAddress: address,
      );
    } catch (error) {
      debugPrint('[SOS] Current location unavailable: $error');
      return null;
    }
  }

  @override
  Future<List<SosHistoryEntry>> loadHistory() => _local.getHistory();

  String _buildMessage(
    SosTriggerType triggerType,
    DateTime timestamp,
    SosLocation? location,
  ) {
    if (location == null) {
      return 'Emergency! VisionMate user needs help. Location unavailable.';
    }
    final mapLink =
        'https://maps.google.com/?q=${location.latitude},${location.longitude}';
    final address = location.readableAddress;
    final addressText = address == null || address.isEmpty
        ? ''
        : 'Near $address.\n';
    return 'EMERGENCY!\n\n'
        'I need immediate help.\n\n'
        '$addressText'
        'My current location:\n'
        'Latitude: ${location.latitude}\n'
        'Longitude: ${location.longitude}\n'
        '$mapLink\n\n'
        'Please reach me as soon as possible.';
  }
}
