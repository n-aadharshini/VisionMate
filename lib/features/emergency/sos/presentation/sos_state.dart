import '../../../../core/services/location_service.dart';
import '../data/sos_remote_datasource.dart';
import '../domain/sos_contact.dart';

/// All possible statuses the SOS screen can be in.
enum SosStatus {
  idle,
  loading,
  success,
  error,
}

/// Minimal immutable state object for the SOS feature.
class SosState {
  final SosStatus status;
  final String? message;
  final List<SosContact> contacts;
  final SosLocation? lastSentLocation;
  final DateTime? lastSentTime;
  final SosTriggerType? lastTriggerType;

  const SosState({
    this.status = SosStatus.idle,
    this.message,
    this.contacts = const [],
    this.lastSentLocation,
    this.lastSentTime,
    this.lastTriggerType,
  });

  bool get isBusy => status == SosStatus.loading;

  SosState copyWith({
    SosStatus? status,
    String? message,
    List<SosContact>? contacts,
    SosLocation? lastSentLocation,
    DateTime? lastSentTime,
    SosTriggerType? lastTriggerType,
    bool clearMessage = false,
  }) {
    return SosState(
      status: status ?? this.status,
      message: clearMessage ? null : (message ?? this.message),
      contacts: contacts ?? this.contacts,
      lastSentLocation: lastSentLocation ?? this.lastSentLocation,
      lastSentTime: lastSentTime ?? this.lastSentTime,
      lastTriggerType: lastTriggerType ?? this.lastTriggerType,
    );
  }
}
