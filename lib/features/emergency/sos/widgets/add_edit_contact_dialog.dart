import 'package:flutter/material.dart';
import '../domain/sos_contact.dart';

class AddEditContactDialog extends StatefulWidget {
  const AddEditContactDialog({super.key, this.contact});
  final SosContact? contact;
  @override
  State<AddEditContactDialog> createState() => _AddEditContactDialogState();
}

class _AddEditContactDialogState extends State<AddEditContactDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.contact?.name,
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.contact?.phoneNumber,
  );
  late final TextEditingController _relation = TextEditingController(
    text: widget.contact?.relation,
  );
  late bool _primary = widget.contact?.isPrimary ?? false;
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _relation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.contact == null
          ? 'Add emergency contact'
          : 'Edit emergency contact',
    ),
    content: Form(
      key: _form,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Name is required' : null,
            ),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Indian mobile number',
              ),
              validator: (v) {
                final phone = (v ?? '').replaceAll(RegExp(r'[ -]'), '').trim();
                return RegExp(r'^(\+91)?[6-9]\d{9}$').hasMatch(phone)
                    ? null
                    : 'Enter a valid Indian mobile number';
              },
            ),
            TextFormField(
              controller: _relation,
              decoration: const InputDecoration(labelText: 'Relation'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Relation is required' : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mark as primary'),
              value: _primary,
              onChanged: (value) => setState(() => _primary = value),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(
            context,
            SosContact(
              id:
                  widget.contact?.id ??
                  DateTime.now().microsecondsSinceEpoch.toString(),
              name: _name.text.trim(),
              phoneNumber: _phone.text.trim(),
              relation: _relation.text.trim(),
              isPrimary: _primary,
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}
