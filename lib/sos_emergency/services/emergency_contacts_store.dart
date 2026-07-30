import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/emergency_contact.dart';

class EmergencyContactsStore {
  static const _key = 'visionmate_parallel_sos_contacts_v1';

  Future<List<EmergencyContact>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_key);
    final contacts = encoded == null
        ? _defaults
        : (jsonDecode(encoded) as List<dynamic>)
              .map((item) => EmergencyContact.fromJson(item as Map<String, dynamic>))
              .toList();
    final merged = _ensureDefaults(contacts);
    await save(merged);
    return merged;
  }

  Future<void> save(List<EmergencyContact> contacts) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key,
      jsonEncode(contacts.map((contact) => contact.toJson()).toList()),
    );
  }

  List<EmergencyContact> _ensureDefaults(List<EmergencyContact> contacts) => [
    ..._defaults,
    ...contacts.where((contact) => !contact.isDefault),
  ];

  static const _defaults = [
    EmergencyContact(
      id: 'india_112',
      name: 'India Emergency',
      phoneNumber: '112',
      isDefault: true,
    ),
    EmergencyContact(
      id: 'ambulance_108',
      name: 'Ambulance',
      phoneNumber: '108',
      isDefault: true,
    ),
  ];
}
