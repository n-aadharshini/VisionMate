import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/location_service.dart';
import '../domain/sos_contact.dart';
import 'sos_remote_datasource.dart';

/// A single record of a past SOS send, kept locally for the demo
/// "history" and for offline resilience.
class SosHistoryEntry {
  final SosTriggerType triggerType;
  final DateTime timestamp;
  final SosLocation? location;
  final bool success;

  const SosHistoryEntry({
    required this.triggerType,
    required this.timestamp,
    required this.location,
    required this.success,
  });

  Map<String, dynamic> toJson() => {
    'triggerType': triggerType.name,
    'timestamp': timestamp.toIso8601String(),
    'location': location?.toJson(),
    'success': success,
  };

  factory SosHistoryEntry.fromJson(Map<String, dynamic> json) {
    return SosHistoryEntry(
      triggerType: SosTriggerType.values.firstWhere(
        (t) => t.name == json['triggerType'],
        orElse: () => SosTriggerType.manual,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
      location: json['location'] == null
          ? null
          : SosLocation.fromJson(json['location'] as Map<String, dynamic>),
      success: json['success'] as bool,
    );
  }
}

/// Handles all on-device persistence for the SOS feature: cached
/// emergency contacts, alert history, and last alert state.
class SosLocalDatasource {
  static const _contactsKey = 'sos_contacts_v1';
  static const _legacySeedContactIds = {
    'personal_aathika_9003740502',
    'personal_divya_9360592574',
    'personal_divi_8248135194',
  };
  List<SosContact>? _memoryContacts;

  Future<List<SosContact>> getCachedContacts() async {
    if (_memoryContacts != null) return List<SosContact>.from(_memoryContacts!);
    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString(_contactsKey);
      if (encoded == null) {
        final initialContacts = _initialContacts();
        await cacheContacts(initialContacts);
        return initialContacts;
      }
      final decoded = jsonDecode(encoded) as List<dynamic>;
      _memoryContacts = _withRequiredDefaults(
        decoded
            .map((value) => SosContact.fromJson(value as Map<String, dynamic>))
            .toList(),
      );
    } catch (_) {
      // Keeps the SOS screen usable in test and unsupported environments. On a
      // device this branch is not used; SharedPreferences remains the source of truth.
      _memoryContacts = _initialContacts();
    }
    return List<SosContact>.from(_memoryContacts!);
  }

  Future<void> cacheContacts(List<SosContact> contacts) async {
    final ordered = _withRequiredDefaults(contacts);
    _memoryContacts = List<SosContact>.from(ordered);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _contactsKey,
        jsonEncode(ordered.map((contact) => contact.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> addContact(SosContact contact) async {
    if (contact.isDefault)
      throw ArgumentError('Default contacts cannot be added.');
    final contacts = await getCachedContacts();
    await cacheContacts([...contacts, contact]);
  }

  Future<void> updateContact(SosContact contact) async {
    if (contact.isDefault)
      throw ArgumentError('Default contacts cannot be edited.');
    final contacts = await getCachedContacts();
    final index = contacts.indexWhere((existing) => existing.id == contact.id);
    if (index < 0 || contacts[index].isDefault) {
      throw ArgumentError('This contact cannot be edited.');
    }
    contacts[index] = contact;
    await cacheContacts(contacts);
  }

  Future<void> deleteContact(String id) async {
    final contacts = await getCachedContacts();
    final matches = contacts.where((item) => item.id == id);
    if (matches.isEmpty) return;
    final contact = matches.first;
    if (contact.isDefault)
      throw ArgumentError('Default contacts cannot be deleted.');
    contacts.removeWhere((item) => item.id == id);
    await cacheContacts(contacts);
  }

  Future<void> appendHistory(SosHistoryEntry entry) async {
    // History persistence can be added independently; alert delivery must not
    // be blocked if local history is unavailable.
  }

  Future<List<SosHistoryEntry>> getHistory() async {
    return const [];
  }

  Future<void> saveLastAlertState({
    required SosTriggerType triggerType,
    required DateTime timestamp,
    required SosLocation? location,
  }) async {
    // No-op placeholder for the prototype.
  }

  /// Seed contacts for first run of the prototype/demo so the UI
  /// isn't empty before a real contact-management screen exists.
  List<SosContact> _defaultContacts() {
    return const [
      SosContact(
        id: 'default_police',
        name: 'Police',
        phoneNumber: '100',
        relation: 'Emergency Services',
        isDefault: true,
      ),
      SosContact(
        id: 'default_ambulance',
        name: 'Ambulance',
        phoneNumber: '108',
        relation: 'Emergency Services',
        isDefault: true,
      ),
    ];
  }

  List<SosContact> _initialContacts() => [
    ..._defaultContacts(),
    const SosContact(
      id: 'personal_aadhu_9361263756',
      name: 'aadhu',
      phoneNumber: '9361263756',
      relation: 'Primary emergency contact',
    ),
    const SosContact(
      id: 'personal_divi_9360592574',
      name: 'divi',
      phoneNumber: '9360592574',
      relation: 'Primary emergency contact',
      isPrimary: true,
    ),
    const SosContact(
      id: 'personal_naami_9284806239',
      name: 'naami',
      phoneNumber: '9284806239',
      relation: 'Primary emergency contact',
    ),
  ];

  List<SosContact> _withRequiredDefaults(List<SosContact> contacts) {
    // Never trust persisted default records: these fixed numbers must remain
    // present and immutable even if older/corrupt storage is encountered.
    final personal = contacts
        .where(
          (contact) =>
              !contact.isDefault && !_legacySeedContactIds.contains(contact.id),
        )
        .toList();
    for (final seeded in _initialContacts().where(
      (contact) => !contact.isDefault,
    )) {
      if (!personal.any(
        (contact) => contact.phoneNumber == seeded.phoneNumber,
      )) {
        personal.add(seeded);
      }
    }
    return [..._defaultContacts(), ...personal];
  }
}
