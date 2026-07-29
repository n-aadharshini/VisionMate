import 'package:flutter/foundation.dart';

import '../data/sos_repository.dart';
import '../domain/sos_contact.dart';

class ManageContactsController extends ChangeNotifier {
  ManageContactsController(this._repository);
  final SosRepository _repository;
  List<SosContact> _contacts = const [];
  bool _loading = false;
  String? _error;
  bool _disposed = false;
  List<SosContact> get contacts => _contacts;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _notify();
    try {
      _contacts = await _repository.loadContacts();
      _error = null;
    } catch (e) {
      _error = 'Could not load contacts: $e';
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<bool> add(SosContact contact) => _save(contact, isEdit: false);
  Future<bool> edit(SosContact contact) => _save(contact, isEdit: true);
  Future<bool> _save(SosContact contact, {required bool isEdit}) async {
    if (contact.isDefault) return _fail('Default contacts cannot be changed.');
    final validation = _validate(contact);
    if (validation != null) return _fail(validation);
    try {
      if (isEdit)
        await _repository.updateContact(contact);
      else
        await _repository.addContact(contact);
      await load();
      return true;
    } catch (e) {
      return _fail(e.toString());
    }
  }

  Future<bool> delete(SosContact contact) async {
    if (contact.isDefault) return _fail('Default contacts cannot be deleted.');
    try {
      await _repository.deleteContact(contact.id);
      await load();
      return true;
    } catch (e) {
      return _fail(e.toString());
    }
  }

  String? _validate(SosContact contact) {
    if (contact.name.trim().isEmpty) return 'Enter a contact name.';
    final phone = contact.phoneNumber.replaceAll(RegExp(r'[ -]'), '').trim();
    if (!RegExp(r'^(\+91)?[6-9]\d{9}$').hasMatch(phone))
      return 'Enter a valid phone number.';
    if (contact.relation.trim().isEmpty) return 'Enter a relation.';
    return null;
  }

  Future<bool> _fail(String message) async {
    _error = message;
    _notify();
    return false;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
