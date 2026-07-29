
import '../../../../core/services/location_service.dart';
import '../data/sos_remote_datasource.dart';
import '../data/sos_repository.dart';
import 'sos_contact.dart';

/// Raised when the SOS flow cannot proceed because of invalid
/// input (e.g. no contacts configured).
class SosValidationException implements Exception {
  final String message;
  const SosValidationException(this.message);

  @override
  String toString() => message;
}

/// Encapsulates the core business rule for sending an SOS alert:
/// validate contacts, validate/attach location (best-effort), pick
/// the trigger type, and delegate to the repository.
///
/// Both the manual and automatic flows call this same use case,
/// guaranteeing they share one alert pipeline.
class SendSosUseCase {
  SendSosUseCase({required this._repository});

  final SosRepository _repository;

  Future<SosSendOutcome> call({
    required List<SosContact> contacts,
    required SosTriggerType triggerType,
    SosLocation? location,
    String? message,
  }) async {
    final validContacts = _validateContacts(contacts);

    // Location is best-effort: a missing/failed location should not
    // block sending the alert, since getting help matters more than
    // having perfect coordinates.
    return _repository.sendAlert(
      contacts: validContacts,
      triggerType: triggerType,
      location: location,
      message: message,
    );
  }

  List<SosContact> _validateContacts(List<SosContact> contacts) {
    if (contacts.isEmpty) {
      throw const SosValidationException(
        'No emergency contacts configured. Please add at least one '
        'contact before sending an SOS.',
      );
    }
    return contacts;
  }
}