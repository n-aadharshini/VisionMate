import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/voice_sos_service.dart';
import '../services/voice_intent_matcher.dart';
import '../widgets/emergency_contact_tile.dart';
import '../widgets/sos_button.dart';
import 'manage_contacts_controller.dart';
import 'manage_contacts_screen.dart';
import 'sos_controller.dart';
import 'sos_state.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key, this.voiceAction});

  final String? voiceAction;

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  late final VoiceSosService _voiceSosService;
  Future<void> _openManageContacts() async {
    final sosController = context.read<SosController>();
    final manageController = context.read<ManageContactsController>();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: sosController),
            ChangeNotifierProvider.value(value: manageController),
          ],
          child: const ManageContactsScreen(),
        ),
      ),
    );
    if (mounted) await sosController.refreshContacts();
  }

  @override
  void initState() {
    super.initState();
    _voiceSosService = VoiceSosService();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final continueToPermissions = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Prepare Emergency SOS'),
          content: const Text(
            'VisionMate needs emergency safety permissions so SOS can work without delays.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      final controller = context.read<SosController>();
      if (continueToPermissions == true) {
        await controller.requestSosPermissions();
      }
      await controller.initialize();
      await _voiceSosService.start(
        onCommand: (command) async {
          switch (command) {
            case VoiceSosCommand.sendSos:
              await controller.triggerManualSos();
            case VoiceSosCommand.callAmbulance:
              await controller.simulateEmergencyServiceCall('108');
            case VoiceSosCommand.cancelSos:
              controller.cancelCallFallback();
          }
        },
        onStatus: (_) {},
        onTranscript: (transcript) async {
          final intent = VoiceIntentMatcher().match(
            transcript,
            controller.state.contacts,
          );
          if (intent.type != VoiceIntentType.callContact ||
              intent.contact == null) {
            return false;
          }
          await controller.callNumber(intent.contact!.phoneNumber);
          return true;
        },
      );
      if (widget.voiceAction == 'send_sos') {
        await controller.triggerManualSos();
      }
    });
  }

  @override
  void dispose() {
    _voiceSosService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Emergency SOS')),
      body: SafeArea(
        child: Consumer<SosController>(
          builder: (context, controller, _) {
            final state = controller.state;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: SosButton(
                      isLoading: state.isBusy,
                      onPressed: () => controller.triggerManualSos(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (state.status == SosStatus.success ||
                      state.status == SosStatus.error)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: state.status == SosStatus.success
                            ? Colors.green.shade800
                            : Colors.red.shade900,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        state.message ?? '',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Emergency Contacts',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _openManageContacts,
                        icon: const Icon(Icons.manage_accounts_outlined),
                        label: const Text('Manage'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (state.contacts.isEmpty)
                    const Text(
                      'No emergency contacts found.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ...state.contacts.map(
                    (contact) => EmergencyContactTile(
                      contact: contact,
                      onCall: (phoneNumber) {
                        if (contact.isDefault) {
                          controller.simulateEmergencyNumberCall(phoneNumber);
                        } else {
                          controller.callNumber(phoneNumber);
                        }
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
