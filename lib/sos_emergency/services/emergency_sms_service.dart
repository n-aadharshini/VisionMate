import 'package:flutter_sms/flutter_sms.dart';

import '../models/emergency_contact.dart';
import 'emergency_location_service.dart';

class EmergencySmsService {
  Future<void> send({
    required List<EmergencyContact> contacts,
    required EmergencyLocation? location,
  }) async {
    final locationBody = location == null
        ? 'Location is unavailable.'
        : 'My live location:\n${location.mapsUrl}';
    final message = 'EMERGENCY!\n\nI need immediate help.\n\n'
        '$locationBody\n\nPlease reach me as soon as possible.';
    await sendSMS(
      message: message,
      recipients: contacts.map((contact) => contact.phoneNumber).toList(),
    );
  }
}
