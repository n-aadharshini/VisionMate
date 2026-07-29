import '../domain/sos_contact.dart';

enum VoiceIntentType {
  activateSos,
  callContact,
  messageContact,
  locationContact,
  callDefault,
  safe,
  unknown,
}

class VoiceIntent {
  const VoiceIntent(this.type, {this.contact, this.defaultNumber});
  final VoiceIntentType type;
  final SosContact? contact;
  final String? defaultNumber;
}

/// Shared free/on-device keyword matcher for English, Tamil and Tanglish.
class VoiceIntentMatcher {
  static const triggerPhrases = <VoiceIntentType, List<String>>{
    VoiceIntentType.activateSos: [
      'help',
      'sos',
      'emergency',
      'please help',
      'help pannunga',
      'kaapaathunga',
      'உதவி',
      'காப்பாத்துங்க',
    ],
    VoiceIntentType.safe: [
      "i'm safe",
      'i am safe',
      "i'm okay",
      'i am okay',
      'im fine',
      'cancel',
      'safe than',
      'seri',
      'paravayillai',
      'நான் பாதுகாப்பாக',
      'பரவாயில்லை',
      'நல்லா இருக்கேன்',
    ],
  };

  VoiceIntent match(String transcript, List<SosContact> contacts) {
    final text = _normalise(transcript);
    if (_contains(text, triggerPhrases[VoiceIntentType.safe]!)) {
      return const VoiceIntent(VoiceIntentType.safe);
    }
    if (_contains(text, ['call 108', '108 ku call pannu', 'ambulance', '108'])) {
      return const VoiceIntent(
        VoiceIntentType.callDefault,
        defaultNumber: '108',
      );
    }
    if (_contains(text, ['call 100', '100 ku call pannu', 'police', '100'])) {
      return const VoiceIntent(
        VoiceIntentType.callDefault,
        defaultNumber: '100',
      );
    }
    final contact = _findContact(text, contacts);
    if (contact != null) {
      if (_contains(text, [
        'send location',
        'send my location',
        'location anupu',
        'location அனுப்பு',
      ])) {
        return VoiceIntent(VoiceIntentType.locationContact, contact: contact);
      }
      if (_contains(text, [
        'message',
        'send sos',
        'sos anupu',
        'message அனுப்பு',
      ])) {
        return VoiceIntent(VoiceIntentType.messageContact, contact: contact);
      }
      if (_contains(text, ['call', 'dial', 'phone', 'கால்'])) {
        return VoiceIntent(VoiceIntentType.callContact, contact: contact);
      }
    }
    if (_contains(text, triggerPhrases[VoiceIntentType.activateSos]!)) {
      return const VoiceIntent(VoiceIntentType.activateSos);
    }
    return const VoiceIntent(VoiceIntentType.unknown);
  }

  SosContact? _findContact(String text, List<SosContact> contacts) {
    for (final contact in contacts.where((item) => !item.isDefault)) {
      if (text.contains(_normalise(contact.name))) return contact;
    }
    return null;
  }

  bool _contains(String text, List<String> phrases) =>
      phrases.any((phrase) => text.contains(_normalise(phrase)));
  String _normalise(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u0B80-\u0BFF ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
