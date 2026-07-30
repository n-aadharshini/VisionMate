import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:phone_state/phone_state.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/location_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/permission_service.dart';
import '../data/sos_remote_datasource.dart';
import '../data/sos_repository.dart';
import '../domain/send_sos_usecase.dart';
import '../domain/sos_contact.dart';
import '../services/sos_feedback_service.dart';
import 'sos_state.dart';

class SosController extends ChangeNotifier {
  // This heuristic can mistake a genuinely short call for a declined call.
  static const _unansweredCallThreshold = Duration(seconds: 20);
  static const _offHookGracePeriod = Duration(seconds: 5);
  static const _maxPrimaryCallAttempts = 3;
  SosController({
    required SendSosUseCase sendSosUseCase,
    required SosRepository repository,
    @Deprecated('SOS uses CurrentLocationService directly.')
    LocationService? locationService,
    required PermissionService permissionService,
    required NotificationService notificationService,
    SosFeedbackService? feedbackService,
  }) : _sendSosUseCase = sendSosUseCase,
       _repository = repository,
       _permissionService = permissionService,
       _notificationService = notificationService,
       _feedback = feedbackService ?? SosFeedbackService();

  final SendSosUseCase _sendSosUseCase;
  final SosRepository _repository;
  final PermissionService _permissionService;
  final NotificationService _notificationService;
  final SosFeedbackService _feedback;

  SosState _state = const SosState();
  SosState get state => _state;
  bool _disposed = false;
  StreamSubscription<PhoneState>? _callStateSubscription;
  List<SosContact> _callQueue = const [];
  int _callAttempts = 0;
  DateTime? _activeCallStartedAt;
  bool _callFallbackCancelled = false;
  bool _awaitingCallResult = false;
  bool _dialLaunchConfirmed = false;
  bool _offHookDetected = false;
  Timer? _offHookGraceTimer;

  Future<void> initialize() => refreshContacts();

  /// Requests only the two permissions needed to send an SOS alert.
  /// Phone permission is requested later, only if the user starts a call.
  Future<void> requestSosPermissions() async {
    await _permissionService.requestLocationPermission();
    await _permissionService.requestSmsPermission();
  }

  Future<void> refreshContacts() async {
    try {
      _set(_state.copyWith(contacts: await _repository.loadContacts()));
    } catch (error) {
      _set(
        _state.copyWith(
          status: SosStatus.error,
          message: 'Failed to load emergency contacts: $error',
        ),
      );
    }
  }

  Future<void> triggerManualSos({bool confirmed = true}) async {
    if (!confirmed || _state.isBusy) return;
    await _send(contacts: _sosRecipients(), includeLocation: true);
  }

  Future<void> sendToContact(
    SosContact contact, {
    required bool includeLocation,
  }) => _send(contacts: [contact], includeLocation: includeLocation);

  Future<void> callNumber(String phoneNumber) async {
    if (!await _permissionService.isPhonePermissionGranted()) {
      _set(
        _state.copyWith(
          status: SosStatus.error,
          message: 'Phone permission is needed to place calls.',
        ),
      );
      return;
    }

    final contact = _contactFor(phoneNumber);
    if (Platform.isAndroid && contact != null && !contact.isDefault) {
      await _startPrimaryCallSequence(contact);
      return;
    }

    await _launchCall(phoneNumber, contactName: contact?.name);
  }

  Future<bool> _launchCall(
    String phoneNumber, {
    String? contactName,
  }) async {
    final telUri = Uri(scheme: 'tel', path: phoneNumber);
    _callFallbackLog('dial attempted: $telUri');
    try {
      final canLaunch = await canLaunchUrl(telUri);
      _callFallbackLog('canLaunchUrl: $canLaunch');
      if (!canLaunch) {
        await _reportDialFailure(contactName ?? phoneNumber);
        return false;
      }

      final opened = await launchUrl(
        telUri,
        mode: LaunchMode.externalApplication,
      );
      _callFallbackLog('launchUrl result: $opened');
      if (!opened) {
        await _reportDialFailure(contactName ?? phoneNumber);
      } else if (contactName != null) {
        await _updateWithFeedback(
          _state.copyWith(
            status: SosStatus.success,
            message: 'Calling $contactName now.',
          ),
          () => _feedback.callPlaced(contactName),
        );
      }
      return opened;
    } catch (error) {
      _callFallbackLog('dial exception: $error');
      await _reportDialFailure(contactName ?? phoneNumber);
      return false;
    }
  }

  Future<void> _reportDialFailure(String contactName) async {
    final message = "Couldn't open the dialer for $contactName.";
    await _updateWithFeedback(
      _state.copyWith(status: SosStatus.error, message: message),
      () => _feedback.failure(message),
    );
  }

  /// Android-only fallback for personal calls. iOS intentionally uses only
  /// `tel:` because third-party apps cannot reliably observe call outcomes.
  Future<void> _startPrimaryCallSequence(SosContact firstContact) async {
    cancelCallFallback(silent: true);
    if (!await _permissionService.isPhoneStatePermissionGranted()) {
      _callFallbackLog(
        'READ_PHONE_STATE is not granted; placing call without fallback.',
      );
      await _launchCall(firstContact.phoneNumber, contactName: firstContact.name);
      return;
    }

    _callFallbackCancelled = false;
    _callAttempts = 0;
    _callQueue = [
      firstContact,
      ..._state.contacts.where(
        (contact) =>
            !contact.isDefault &&
            contact.isPrimary &&
            contact.id != firstContact.id,
      ),
    ];
    _callFallbackLog('READ_PHONE_STATE granted; listener attached.');
    _callStateSubscription = PhoneState.stream.listen(_onPhoneState);
    await _tryNextPrimaryContact();
  }

  Future<void> _tryNextPrimaryContact() async {
    if (_callFallbackCancelled || _callAttempts >= _maxPrimaryCallAttempts) {
      await _sendSmsFallback();
      return;
    }
    if (_callQueue.isEmpty) {
      await _sendSmsFallback();
      return;
    }

    final next = _callQueue.removeAt(0);
    _callAttempts++;
    _activeCallStartedAt = null;
    _awaitingCallResult = true;
    _dialLaunchConfirmed = false;
    _offHookDetected = false;
    _callFallbackLog('attempt $_callAttempts: dialing ${next.name}.');
    final opened = await _launchCall(
      next.phoneNumber,
      contactName: next.name,
    );
    if (!opened) {
      _callFallbackLog('dial failed; fallback sequence stopped.');
      _stopCallMonitoring();
      return;
    }

    _dialLaunchConfirmed = true;
    _callFallbackLog('dial launch confirmed; waiting for off-hook.');
    if (_offHookDetected) return;
    _offHookGraceTimer = Timer(_offHookGracePeriod, () {
      if (_callFallbackCancelled || _offHookDetected) return;
      _callFallbackLog(
        'no off-hook within ${_offHookGracePeriod.inSeconds}s; disabling fallback for this call.',
      );
      _stopCallMonitoring();
    });
  }

  void _onPhoneState(PhoneState phoneState) {
    _callFallbackLog('state: ${phoneState.status.name}.');
    if (_callFallbackCancelled || !_awaitingCallResult) return;
    if (phoneState.status == PhoneStateStatus.CALL_STARTED) {
      _activeCallStartedAt ??= DateTime.now();
      _offHookDetected = true;
      _offHookGraceTimer?.cancel();
      _callFallbackLog('off-hook detected; monitoring call duration.');
      return;
    }
    if (phoneState.status == PhoneStateStatus.CALL_ENDED ||
        phoneState.status == PhoneStateStatus.NOTHING) {
      if (!_dialLaunchConfirmed || !_offHookDetected) {
        _callFallbackLog('idle ignored before a confirmed off-hook transition.');
        return;
      }
      _callFallbackLog('idle detected after off-hook; evaluating duration.');
      unawaited(_handleCallEnded(phoneState.duration));
    }
  }

  Future<void> _handleCallEnded(Duration? reportedDuration) async {
    if (_callFallbackCancelled || !_awaitingCallResult) return;
    _awaitingCallResult = false;
    final duration = reportedDuration ??
        (_activeCallStartedAt == null
            ? Duration.zero
            : DateTime.now().difference(_activeCallStartedAt!));
    _activeCallStartedAt = null;
    if (duration >= _unansweredCallThreshold) {
      _callFallbackLog(
        'call lasted ${duration.inSeconds}s; treated as answered, fallback stopped.',
      );
      _stopCallMonitoring();
      return;
    }

    _callFallbackLog(
      'call lasted ${duration.inSeconds}s; treated as unanswered/declined.',
    );

    if (_callQueue.isNotEmpty && _callAttempts < _maxPrimaryCallAttempts) {
      final next = _callQueue.first;
      final message = 'No answer. Trying ${next.name}.';
      await _updateWithFeedback(
        _state.copyWith(status: SosStatus.success, message: message),
        () => _feedback.callUnanswered(next.name),
      );
      if (!_callFallbackCancelled) await _tryNextPrimaryContact();
      return;
    }
    await _sendSmsFallback();
  }

  Future<void> _sendSmsFallback() async {
    if (_callFallbackCancelled) return;
    _stopCallMonitoring();
    const message = 'No one answered. Sending SMS to all contacts instead.';
    await _updateWithFeedback(
      _state.copyWith(status: SosStatus.success, message: message),
      () => _feedback.failure(message),
    );
    if (!_callFallbackCancelled) {
      await _send(contacts: _sosRecipients(), includeLocation: true);
    }
  }

  /// Call this from the existing voice "I'm safe" / cancel action. It cannot
  /// terminate an already-opened system dialer call, but blocks all next calls.
  void cancelCallFallback({bool silent = false}) {
    _callFallbackCancelled = true;
    _stopCallMonitoring();
    if (!silent) {
      unawaited(_updateWithFeedback(
        _state.copyWith(
          status: SosStatus.success,
          message: "Great, glad you're safe.",
        ),
        _feedback.safeConfirmed,
      ));
    }
  }

  void _stopCallMonitoring() {
    _offHookGraceTimer?.cancel();
    _offHookGraceTimer = null;
    _callStateSubscription?.cancel();
    _callStateSubscription = null;
    _callQueue = const [];
    _activeCallStartedAt = null;
    _awaitingCallResult = false;
    _dialLaunchConfirmed = false;
    _offHookDetected = false;
  }

  void _callFallbackLog(String message) =>
      debugPrint('[CallFallback] ${DateTime.now().toIso8601String()} $message');

  SosContact? _contactFor(String phoneNumber) {
    for (final contact in _state.contacts) {
      if (contact.phoneNumber == phoneNumber) return contact;
    }
    return null;
  }

  List<SosContact> _sosRecipients() {
    final primaryPersonal = _state.contacts
        .where((contact) => !contact.isDefault && contact.isPrimary)
        .toList();
    return primaryPersonal.isNotEmpty
        ? primaryPersonal
        : _state.contacts.where((contact) => !contact.isDefault).toList();
  }

  Future<void> simulateEmergencyNumberCall(String number) async {
    final message = 'Calling $number, please wait.';
    _set(
      _state.copyWith(
        status: SosStatus.success,
        message: message,
      ),
    );
    await _feedback.simulatedCall(number);
  }

  /// Backwards-compatible name for existing simulated-call integrations.
  Future<void> simulateEmergencyServiceCall(String number) =>
      simulateEmergencyNumberCall(number);

  Future<void> _send({
    required List<SosContact> contacts,
    required bool includeLocation,
  }) async {
    _set(_state.copyWith(status: SosStatus.loading, clearMessage: true));

    try {
      // Android presents each sensitive permission in its own system dialog.
      // Request location before SMS so an approved location is ready to be
      // attached to the emergency alert.
      final locationGranted = !includeLocation ||
          await _permissionService.requestLocationPermission();

      SosLocation? location;
      if (includeLocation && locationGranted) {
        // SosRepositoryImpl fetches the shared Current Location service.
        // A null value explicitly requests that best-effort fetch.
        location = null;
      }

      if (!await _permissionService.requestSmsPermission()) {
        throw const SosValidationException(
          'SMS permission is required to send the emergency alert.',
        );
      }

      final outcome = await _sendSosUseCase(
        contacts: contacts,
        triggerType: SosTriggerType.manual,
        location: location,
      );
      if (!outcome.success) throw SosValidationException(outcome.message);

      await _notificationService.showSosSentNotification();
      await _updateWithFeedback(
        _state.copyWith(
          status: SosStatus.success,
          message: !locationGranted
              ? '${outcome.message} Location permission was denied.'
              : outcome.location == null
                  ? '${outcome.message} Location unavailable.'
                  : outcome.message,
          lastSentLocation: outcome.location,
          lastSentTime: DateTime.now(),
          lastTriggerType: SosTriggerType.manual,
        ),
        () => _feedback.alertSent(
          contacts,
          address: outcome.location?.readableAddress,
        ),
      );
    } on SosValidationException catch (error) {
      await _updateWithFeedback(
        _state.copyWith(status: SosStatus.error, message: error.message),
        () => _feedback.failure('Unable to send SOS.'),
      );
    } catch (error) {
      await _updateWithFeedback(
        _state.copyWith(
          status: SosStatus.error,
          message: 'Unable to send SOS: $error',
        ),
        () => _feedback.failure('Unable to send SOS.'),
      );
    }
  }

  void _set(SosState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  Future<void> _updateWithFeedback(
    SosState value,
    Future<void> Function() feedback,
  ) async {
    _set(value);
    await feedback();
  }

  @override
  void dispose() {
    _disposed = true;
    cancelCallFallback(silent: true);
    _feedback.dispose();
    super.dispose();
  }
}
