import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/emergency_contact.dart';
import 'sos_emergency_controller.dart';

/// Standalone screen: add it to the app router when this parallel module is adopted.
class SosEmergencyScreen extends StatelessWidget {
  const SosEmergencyScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => SosEmergencyController()..initialize(),
    child: const _SosEmergencyView(),
  );
}

class _SosEmergencyView extends StatelessWidget {
  const _SosEmergencyView();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SosEmergencyController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency SOS'),
        actions: [
          IconButton(
            tooltip: 'Add emergency contact',
            icon: const Icon(Icons.person_add),
            onPressed: () => _editContact(context),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Semantics(
              button: true,
              label: 'Emergency SOS. Double tap to request help.',
              child: SizedBox(
                height: 220,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                    shape: const CircleBorder(),
                  ),
                  onPressed: controller.isBusy ? null : controller.trigger,
                  child: controller.isBusy
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('SOS', style: TextStyle(fontSize: 52, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Semantics(
              liveRegion: true,
              child: Text(controller.status, style: const TextStyle(fontSize: 18)),
            ),
            if (controller.location != null) ...[
              const SizedBox(height: 8),
              Text('GPS: ${controller.location!.latitude}, ${controller.location!.longitude}'),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: controller.isBusy ? controller.cancel : null,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel SOS'),
            ),
            const SizedBox(height: 24),
            const Text('Emergency Contacts', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ...controller.contacts.map((contact) => ListTile(
              title: Text(contact.name),
              subtitle: Text(contact.phoneNumber),
              trailing: contact.isDefault ? const Icon(Icons.lock) : PopupMenuButton<String>(
                onSelected: (value) => value == 'edit' ? _editContact(context, contact) : controller.delete(contact),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Future<void> _editContact(BuildContext context, [EmergencyContact? contact]) async {
    final name = TextEditingController(text: contact?.name);
    final phone = TextEditingController(text: contact?.phoneNumber);
    final saved = await showDialog<EmergencyContact>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(contact == null ? 'Add contact' : 'Edit contact'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, EmergencyContact(
            id: contact?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
            name: name.text.trim(), phoneNumber: phone.text.trim(), isPrimary: contact?.isPrimary ?? true,
          )), child: const Text('Save')),
        ],
      ),
    );
    if (saved != null && saved.name.isNotEmpty && saved.phoneNumber.isNotEmpty && context.mounted) {
      await context.read<SosEmergencyController>().addOrUpdate(saved);
    }
  }
}
