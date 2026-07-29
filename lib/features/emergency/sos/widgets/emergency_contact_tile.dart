import 'package:flutter/material.dart';

import '../domain/sos_contact.dart';

/// Displays a single emergency contact with a large, accessible
/// call action.
class EmergencyContactTile extends StatelessWidget {
  const EmergencyContactTile({
    super.key,
    required this.contact,
    required this.onCall,
  });

  final SosContact contact;
  final void Function(String phoneNumber) onCall;

  @override
  Widget build(BuildContext context) {
    final callLabel = contact.isDefault
        ? 'Simulate call to ${contact.name}'
        : 'Call ${contact.name}';
    final subtitle = '${contact.relation} · ${contact.phoneNumber}';

    return Semantics(
      label: 'Emergency contact ${contact.name}, ${contact.relation}, '
          '${contact.isPrimary ? "primary contact" : ""}. '
          'Double tap the call button to call ${contact.phoneNumber}.',
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        elevation: 2,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          leading: CircleAvatar(
            radius: 26,
            backgroundColor:
                contact.isPrimary ? const Color(0xFFD32F2F) : Colors.blueGrey,
            child: Text(
              contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  contact.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (contact.isPrimary) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD32F2F),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'PRIMARY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(fontSize: 16),
          ),
          trailing: Semantics(
            button: true,
            label: callLabel,
            child: IconButton(
              iconSize: 32,
              icon: const Icon(Icons.call, color: Color(0xFF2E7D32)),
              tooltip: callLabel,
              onPressed: () => onCall(contact.phoneNumber),
            ),
          ),
        ),
      ),
    );
  }
}
