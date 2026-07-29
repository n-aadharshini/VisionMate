import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/sos_contact.dart';
import '../widgets/add_edit_contact_dialog.dart';
import '../widgets/emergency_contact_tile.dart';
import 'manage_contacts_controller.dart';
import 'sos_controller.dart';

class ManageContactsScreen extends StatefulWidget {
  const ManageContactsScreen({super.key});
  @override
  State<ManageContactsScreen> createState() => _ManageContactsScreenState();
}

class _ManageContactsScreenState extends State<ManageContactsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<ManageContactsController>().load(),
    );
  }

  Future<void> _edit(SosContact? existing) async {
    final contact = await showDialog<SosContact>(
      context: context,
      builder: (_) => AddEditContactDialog(contact: existing),
    );
    if (!mounted || contact == null) return;
    final ok = existing == null
        ? await context.read<ManageContactsController>().add(contact)
        : await context.read<ManageContactsController>().edit(contact);
    if (mounted && !ok) {
      _showError(context.read<ManageContactsController>().error);
    }
  }

  Future<void> _delete(SosContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${contact.name}?'),
        content: const Text('This contact will no longer receive SOS alerts.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final ok = await context.read<ManageContactsController>().delete(contact);
    if (mounted && !ok) {
      _showError(context.read<ManageContactsController>().error);
    }
  }

  void _showError(String? error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Unable to update contacts')),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Manage Emergency Contacts')),
    floatingActionButton: Semantics(
      label: 'Add emergency contact',
      button: true,
      child: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.person_add),
        label: const Text('Add Contact'),
      ),
    ),
    body: Consumer<ManageContactsController>(
      builder: (context, controller, _) {
        if (controller.loading && controller.contacts.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Semantics(
              liveRegion: true,
              child: const Text(
                'Police and Ambulance are default contacts. They are always alerted and cannot be changed.',
              ),
            ),
            ...controller.contacts.map(
              (contact) => Card(
                child: Column(
                  children: [
                    EmergencyContactTile(
                      contact: contact,
                      onCall: (phoneNumber) {
                        final sosController = context.read<SosController>();
                        if (contact.isDefault) {
                          sosController.simulateEmergencyServiceCall(phoneNumber);
                        } else {
                          sosController.callNumber(phoneNumber);
                        }
                      },
                    ),
                    if (contact.isDefault)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Chip(
                          label: Text('Default — locked'),
                          avatar: Icon(Icons.lock),
                        ),
                      ),
                    if (!contact.isDefault)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              tooltip: 'Edit ${contact.name}',
                              icon: const Icon(Icons.edit),
                              onPressed: () => _edit(contact),
                            ),
                            IconButton(
                              tooltip: 'Delete ${contact.name}',
                              icon: const Icon(Icons.delete),
                              onPressed: () => _delete(contact),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
