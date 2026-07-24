import 'package:flutter/foundation.dart';

import '../../../core/widgets/app_ui.dart';

class CompanionModeController extends ChangeNotifier {
  CompanionModeController._();

  static final CompanionModeController instance = CompanionModeController._();

  bool _isEnabled = false;
  CompanionOrbState _state = CompanionOrbState.off;

  bool get isEnabled => _isEnabled;
  CompanionOrbState get state => _state;

  void enable() {
    _isEnabled = true;
    _setState(CompanionOrbState.listening);
  }

  void disable() {
    _isEnabled = false;
    _setState(CompanionOrbState.off);
  }

  void setListening() {
    if (_isEnabled) {
      _setState(CompanionOrbState.listening);
    }
  }

  void setProcessing() {
    if (_isEnabled) {
      _setState(CompanionOrbState.processing);
    }
  }

  void setSpeaking() {
    if (_isEnabled) {
      _setState(CompanionOrbState.speaking);
    }
  }

  void _setState(CompanionOrbState value) {
    if (_state == value) {
      return;
    }
    _state = value;
    notifyListeners();
  }
}
