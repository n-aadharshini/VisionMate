import 'package:flutter/foundation.dart';

import 'models/emergency_contact.dart';
import 'services/emergency_call_service.dart';
import 'services/emergency_contacts_store.dart';
import 'services/emergency_location_service.dart';
import 'services/emergency_sms_service.dart';
import 'services/emergency_tts_service.dart';

class SosEmergencyController extends ChangeNotifier {
  SosEmergencyController({
    EmergencyContactsStore? contactsStore,
    EmergencyLocationService? locationService,
    EmergencySmsService? smsService,
    EmergencyCallService? callService,
    EmergencyTtsService? ttsService,
  }) : _contactsStore = contactsStore ?? EmergencyContactsStore(),
       _locationService = locationService ?? EmergencyLocationService(),
       _smsService = smsService ?? EmergencySmsService(),
       _callService = callService ?? EmergencyCallService(),
       _ttsService = ttsService ?? EmergencyTtsService();

  final EmergencyContactsStore _contactsStore;
  final EmergencyLocationService _locationService;
  final EmergencySmsService _smsService;
  final EmergencyCallService _callService;
  final EmergencyTtsService _ttsService;

  List<EmergencyContact> contacts = const [];
  EmergencyLocation? location;
  String status = 'Ready for emergency assistance.';
  bool isBusy = false;
  bool _cancelled = false;

  Future<void> initialize() async {
    contacts = await _contactsStore.load();
    notifyListeners();
  }

  Future<void> addOrUpdate(EmergencyContact contact) async {
    final updated = [...contacts];
    final index = updated.indexWhere((item) => item.id == contact.id);
    if (index < 0) {
      updated.add(contact);
    } else {
      updated[index] = contact;
    }
    contacts = updated;
    await _contactsStore.save(contacts);
    notifyListeners();
  }

  Future<void> delete(EmergencyContact contact) async {
    if (contact.isDefault) return;
    contacts = contacts.where((item) => item.id != contact.id).toList();
    await _contactsStore.save(contacts);
    notifyListeners();
  }

  /// Safe adapter for the existing assistant to invoke without importing UI.
  Future<void> triggerFromVoiceCommand(String command) async {
    final normalized = command.toLowerCase().trim();
    if (['help', 'emergency', 'sos'].contains(normalized)) await trigger();
  }

  Future<void> trigger() async {
    if (isBusy) return;
    _cancelled = false;
    isBusy = true;
    status = 'Emergency mode activated.';
    notifyListeners();
    await _ttsService.emergencyActivated();

    try {
      status = 'Getting your GPS location.';
      notifyListeners();
      await _ttsService.sendingLocation();
      try {
        location = await _locationService.currentLocation();
      } on EmergencyLocationException catch (error) {
        status = '${error.message} Sending SOS without location.';
        notifyListeners();
        await _ttsService.speak(error.message);
      }
      if (_cancelled) return;

      final recipients = contacts.where((contact) => !contact.isDefault).toList();
      if (recipients.isEmpty) {
        status = 'No personal contacts saved. Calling 112.';
        notifyListeners();
        await _ttsService.speak('No emergency contacts saved. Calling 112.');
      } else {
        status = 'Opening emergency SMS message.';
        notifyListeners();
        await _smsService.send(contacts: recipients, location: location);
      }
      if (_cancelled) return;

      final primary = contacts.where((contact) => contact.isPrimary).firstOrNull ??
          contacts.where((contact) => !contact.isDefault).firstOrNull ??
          contacts.firstWhere((contact) => contact.phoneNumber == '112');
      status = 'Calling ${primary.name}.';
      notifyListeners();
      await _ttsService.callingContact();
      if (!await _callService.call(primary.phoneNumber) && primary.phoneNumber != '112') {
        status = 'Primary call failed. Calling 112.';
        notifyListeners();
        await _ttsService.speak('Call failed. Calling 112.');
        await _callService.call('112');
      }
      status = 'Emergency actions started.';
    } catch (error) {
      status = 'Emergency action failed: $error';
      await _ttsService.speak('Emergency action failed.');
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  void cancel() {
    _cancelled = true;
    status = 'SOS cancelled.';
    _ttsService.speak('SOS cancelled.');
    notifyListeners();
  }

  @override
  void dispose() {
    _ttsService.dispose();
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
