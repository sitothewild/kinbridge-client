import 'package:flutter/material.dart';
import '../../models/platform_model.dart';
import '../shell/kb_shell.dart' show KBRole;
import 'connect_code_page.dart';
import 'notifications_page.dart';
import 'role_picker_page.dart';
import 'sign_in_page.dart';
import 'welcome_page.dart';

/// Keys written into RustDesk's local-options store. Reusing bind.* keeps
/// the KinBridge state in the same place as existing RustDesk prefs.
const String kKbOnboardingDone = "kb-onboarding-done";
const String kKbRole = "kb-role";
const String kKbNotifHelp = "kb-notif-help";
const String kKbNotifPairing = "kb-notif-pairing";
const String kKbNotifRecap = "kb-notif-recap";
const String kKbPairingCode = "kb-pairing-code";

/// First-launch flow coordinator. Self-navigating PageView with a lightweight
/// state machine: Welcome -> Role -> (Helper: ConnectCode) -> Notifications ->
/// done callback.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.onComplete});

  final void Function(KBRole role) onComplete;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

enum _Step { welcome, signIn, role, connectCode, notifications }

class _OnboardingFlowState extends State<OnboardingFlow> {
  _Step _step = _Step.welcome;
  KBRole? _role;

  Future<void> _save(String key, String value) async {
    await bind.mainSetLocalOption(key: key, value: value);
  }

  Future<void> _complete() async {
    await _save(kKbOnboardingDone, "Y");
    if (_role != null) {
      await _save(kKbRole, _role == KBRole.owner ? "owner" : "helper");
    }
    widget.onComplete(_role ?? KBRole.owner);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        switch (_step) {
          case _Step.welcome:
            return true;
          case _Step.signIn:
            setState(() => _step = _Step.welcome);
            return false;
          case _Step.role:
            setState(() => _step = _Step.welcome);
            return false;
          case _Step.connectCode:
            setState(() => _step = _Step.role);
            return false;
          case _Step.notifications:
            setState(() => _step =
                _role == KBRole.helper ? _Step.connectCode : _Step.role);
            return false;
        }
      },
      child: _buildStep(),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _Step.welcome:
        return WelcomePage(
          onGetStarted: () => setState(() => _step = _Step.role),
          onSignIn: () => setState(() => _step = _Step.signIn),
          onSkip: _complete,
        );
      case _Step.signIn:
        return SignInPage(
          onBack: () => setState(() => _step = _Step.welcome),
          onSignedIn: (role) async {
            // Returning user — their role is known from user_roles, skip
            // role picker + connect-code (they already paired). Go straight
            // to notifications prefs (first-launch on this device) then home.
            setState(() => _role = role);
            await _save(kKbRole, role == KBRole.owner ? "owner" : "helper");
            if (!mounted) return;
            setState(() => _step = _Step.notifications);
          },
        );
      case _Step.role:
        return RolePickerPage(
          onBack: () => setState(() => _step = _Step.welcome),
          onPick: (r) {
            setState(() {
              _role = r;
              _step = r == KBRole.helper
                  ? _Step.connectCode
                  : _Step.notifications;
            });
          },
        );
      case _Step.connectCode:
        return ConnectCodePage(
          onBack: () => setState(() => _step = _Step.role),
          onSubmit: (code) async {
            // TODO(Phase V): POST /api/pairing/redeem with this code.
            // For now we persist the code locally + advance.
            await _save(kKbPairingCode, code);
            if (!mounted) return;
            setState(() => _step = _Step.notifications);
          },
          onSkip: () => setState(() => _step = _Step.notifications),
        );
      case _Step.notifications:
        return NotificationsPage(
          onBack: () => setState(() {
            _step = _role == KBRole.helper ? _Step.connectCode : _Step.role;
          }),
          onAllow: (prefs) async {
            await _save(kKbNotifHelp, prefs.helpRequests ? "Y" : "N");
            await _save(kKbNotifPairing, prefs.pairings ? "Y" : "N");
            await _save(kKbNotifRecap, prefs.weeklyRecap ? "Y" : "N");
            // TODO(Phase IV): Android 13+ permission request via the
            // existing RustDesk permission helper (see MainService.kt).
            await _complete();
          },
          onSkip: _complete,
        );
    }
  }
}
