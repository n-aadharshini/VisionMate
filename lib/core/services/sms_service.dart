import 'package:flutter_sms/flutter_sms.dart';

/// Opens a pre-filled SMS composer for each recipient.
class SmsService {
  Future<bool> sendSos(List<String> phoneNumbers, String message) async {
    final recipients = phoneNumbers.where((number) => number.trim().isNotEmpty).toList();
    if (recipients.isEmpty) return false;

    try {
      // Sending separately avoids Android converting the alert to a group MMS.
      for (final recipient in recipients) {
        await sendSMS(
          message: message,
          recipients: [recipient],
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
