// KinBridge deep-link handler — routes four URL shapes:
//
//   kinbridge://session/<id>?token=<jwt>   — helper joins a live session
//   kinbridge://install?token=<64-hex>     — device claims an install token
//   kinbridge://quickconnect?code=<6>      — helper redeems a 1-shot code
//   https://kinbridge.support/invite/<tk>  — helper accepts a pairing invite
//
// All four are dispatched by [KBDeepLink.tryHandle]. AndroidManifest
// registers intent-filters for the three `kinbridge://` hosts and an App
// Link verified filter for `https://kinbridge.support/invite/*`.
//
// Specs live in the kinbridgesupport repo's android-snippets/ — see
//   INSTALL_TOKEN.md, QUICKCONNECT.md, HELPER_INVITE.md.

import 'package:flutter/material.dart';

import '../../common.dart' show globalKey;
import '../data/kb_models.dart';
import '../data/kb_repository.dart';
import '../data/kb_server_fn.dart';
import '../data/kb_supabase.dart';
import 'install_complete_page.dart';
import 'invite_accept_page.dart';
import 'live_session_page.dart';

// Reuses the existing RustDesk-side [globalKey] navigator so deep-link
// pushes work from any app state (cold boot, background → foreground,
// or already-at-home). No second navigator key needed.

class KBDeepLink {
  KBDeepLink._();

  /// Return true if [uri] is a KinBridge link and was dispatched here.
  /// Caller (hooked into common.dart's handleUriLink) should short-circuit
  /// when this returns true so the RustDesk handler doesn't also fire.
  static bool tryHandle(Uri uri) {
    // Custom scheme flows.
    if (uri.scheme == 'kinbridge') {
      switch (uri.host) {
        case 'session':
          return _dispatchSession(uri);
        case 'install':
          return _dispatchInstall(uri);
        case 'quickconnect':
        case 'pair':
          return _dispatchQuickConnect(uri);
        case 'auth-callback':
          return _dispatchAuthCallback(uri);
        default:
          debugPrint("kb: unknown kinbridge:// host '${uri.host}' — ignoring");
          return false;
      }
    }
    // Verified App Link: https://kinbridge.support/invite/<token>
    if (uri.scheme == 'https' &&
        uri.host == 'kinbridge.support' &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments.first == 'invite') {
      return _dispatchInvite(uri.pathSegments[1]);
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // session/<id>?token=<jwt>
  // ---------------------------------------------------------------------------
  static bool _dispatchSession(Uri uri) {
    final token = uri.queryParameters['token'];
    String? sessionId;
    if (uri.pathSegments.isNotEmpty && uri.pathSegments.first.isNotEmpty) {
      sessionId = uri.pathSegments.first;
    }
    if (token == null || token.isEmpty) {
      debugPrint('kb: kinbridge://session rejected — missing token');
      return true;
    }
    _openLiveSession(sessionId: sessionId, token: token);
    return true;
  }

  // ---------------------------------------------------------------------------
  // install?token=<64-hex>
  // ---------------------------------------------------------------------------
  static bool _dispatchInstall(Uri uri) {
    final token = uri.queryParameters['token'];
    if (token == null || token.isEmpty) {
      debugPrint('kb: kinbridge://install rejected — missing token');
      return true;
    }
    _pendingInstall = _PendingInstall(token: token);
    _drainInstallIfReady();
    return true;
  }

  // ---------------------------------------------------------------------------
  // quickconnect?code=<6>
  // ---------------------------------------------------------------------------
  static bool _dispatchQuickConnect(Uri uri) {
    final code = uri.queryParameters['code'];
    if (code == null || !RegExp(r'^\d{6}$').hasMatch(code)) {
      debugPrint('kb: kinbridge://quickconnect rejected — bad code');
      return true;
    }
    _pendingQuickConnect = _PendingQuickConnect(code: code);
    _drainQuickConnectIfReady();
    return true;
  }

  // ---------------------------------------------------------------------------
  // auth-callback?code=<authcode>  — Supabase PKCE OAuth return
  // ---------------------------------------------------------------------------
  static bool _dispatchAuthCallback(Uri uri) {
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      debugPrint('kb: kinbridge://auth-callback rejected — missing code');
      return true;
    }
    // Exchange asynchronously; the auth-state listener on [KBSupabase]
    // flips [KBRepository.instance] once the session lands. We don't
    // need to navigate anywhere — the onboarding flow / SignInPage is
    // still on screen, it will react to the auth-state change.
    _exchangeAuthCode(code);
    return true;
  }

  static Future<void> _exchangeAuthCode(String code) async {
    try {
      await KBSupabase.completeOAuthCallback(code);
      final nav = globalKey.currentState;
      final messenger =
          nav == null ? null : ScaffoldMessenger.maybeOf(nav.context);
      messenger?.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text("Signed in."),
      ));
    } catch (err) {
      debugPrint('kb.auth-callback: $err');
      final nav = globalKey.currentState;
      final messenger =
          nav == null ? null : ScaffoldMessenger.maybeOf(nav.context);
      messenger?.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
            "Sign-in didn't complete. Try again or use email & password."),
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // https://kinbridge.support/invite/<token>
  // ---------------------------------------------------------------------------
  static bool _dispatchInvite(String token) {
    if (token.isEmpty) return false;
    _pendingInvite = _PendingInvite(token: token);
    _drainInviteIfReady();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Pending-link replay — cold-boot races
  // ---------------------------------------------------------------------------

  static _PendingLink? _pending;
  static _PendingInstall? _pendingInstall;
  static _PendingQuickConnect? _pendingQuickConnect;
  static _PendingInvite? _pendingInvite;

  /// Called by the KB shell after first build so any link that arrived
  /// before the navigator was ready gets replayed.
  static Future<void> drainPending() async {
    final nav = globalKey.currentState;
    if (nav == null) return;
    final p = _pending;
    if (p != null) {
      _pending = null;
      await _navigateIntoSession(nav,
          sessionId: p.sessionId, token: p.token);
    }
    _drainInstallIfReady();
    _drainQuickConnectIfReady();
    _drainInviteIfReady();
  }

  // ---------------------------------------------------------------------------
  // Session navigation
  // ---------------------------------------------------------------------------

  static Future<void> _openLiveSession({
    String? sessionId,
    required String token,
  }) async {
    final nav = globalKey.currentState;
    if (nav == null) {
      _pending = _PendingLink(sessionId: sessionId, token: token);
      return;
    }
    await _navigateIntoSession(nav, sessionId: sessionId, token: token);
  }

  static Future<void> _navigateIntoSession(
    NavigatorState nav, {
    String? sessionId,
    required String token,
  }) async {
    KBSession? session;
    if (sessionId != null) {
      try {
        session = await KBRepository.instance.getSession(sessionId);
      } catch (err) {
        debugPrint('kb: getSession failed during deep-link: $err');
      }
    }
    final peerName = session?.peerName ?? 'your family';
    final peerInitials = session?.peerInitials ??
        (peerName.isNotEmpty ? peerName.substring(0, 1).toUpperCase() : '?');
    nav.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LiveSessionPage(
          peerName: peerName,
          peerInitials: peerInitials,
          peerDevice: session?.peerDevice,
          sessionId: sessionId,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Install token
  // ---------------------------------------------------------------------------

  static void _drainInstallIfReady() {
    final p = _pendingInstall;
    final nav = globalKey.currentState;
    if (p == null || nav == null) return;
    _pendingInstall = null;
    _redeemInstall(nav, p.token);
  }

  static Future<void> _redeemInstall(
    NavigatorState nav,
    String token,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(nav.context);
    try {
      final device = await KBServerFn.redeemInstallToken(token: token);
      debugPrint('kb.install: device=${device.id} owner=${device.ownerId}');
      if (!nav.mounted) return;
      nav.push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => InstallCompletePage(device: device),
        ),
      );
    } on KBServerFnError catch (err) {
      debugPrint('kb.install: $err');
      if (messenger != null) {
        messenger.showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(_installErrorCopy(err.message)),
        ));
      }
    }
  }

  static String _installErrorCopy(String raw) {
    if (raw.contains('already used')) {
      return "That install link was already used. Ask for a fresh one.";
    }
    if (raw.contains('revoked')) {
      return "That install link was revoked. Ask the sender to send a new one.";
    }
    if (raw.contains('expired')) {
      return "That install link expired. Ask for a new one.";
    }
    return "That install link didn't work. Ask the sender to check it.";
  }

  // ---------------------------------------------------------------------------
  // QuickConnect
  // ---------------------------------------------------------------------------

  static void _drainQuickConnectIfReady() {
    final p = _pendingQuickConnect;
    final nav = globalKey.currentState;
    if (p == null || nav == null) return;
    _pendingQuickConnect = null;
    _redeemQuickConnect(nav, p.code);
  }

  static Future<void> _redeemQuickConnect(
    NavigatorState nav,
    String code,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(nav.context);
    try {
      final result = await KBServerFn.redeemConnectionCode(code: code);
      if (result.isQuickConnect && result.sessionId != null) {
        final deviceName = result.deviceName;
        nav.push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => LiveSessionPage(
              peerName: deviceName,
              peerInitials: deviceName.isNotEmpty
                  ? deviceName.substring(0, 1).toUpperCase()
                  : '?',
              peerDevice: deviceName,
              sessionId: result.sessionId,
            ),
          ),
        );
      } else if (result.isPairing) {
        messenger?.showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
              "Pairing request sent. Waiting for ${result.deviceName}'s owner to approve."),
        ));
      }
    } on KBServerFnError catch (err) {
      debugPrint('kb.quickconnect: $err');
      final msg = err.message.contains('expired')
          ? "That code expired. Ask for a fresh one."
          : err.message.contains('own device')
              ? "You can't connect to your own device."
              : "That code didn't work. Double-check the digits.";
      messenger?.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(msg),
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Helper invite
  // ---------------------------------------------------------------------------

  static void _drainInviteIfReady() {
    final p = _pendingInvite;
    final nav = globalKey.currentState;
    if (p == null || nav == null) return;
    _pendingInvite = null;
    _handleInvite(nav, p.token);
  }

  static Future<void> _handleInvite(
    NavigatorState nav,
    String token,
  ) async {
    // The preview + accept flow lives on InviteAcceptPage — it does its
    // own lookupInvite + acceptHelperInvite and handles all error states.
    // Deep-link dispatcher just routes the token into it.
    if (!nav.mounted) return;
    nav.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => InviteAcceptPage(token: token),
      ),
    );
  }
}

class _PendingLink {
  _PendingLink({required this.sessionId, required this.token});
  final String? sessionId;
  final String token;
}

class _PendingInstall {
  _PendingInstall({required this.token});
  final String token;
}

class _PendingQuickConnect {
  _PendingQuickConnect({required this.code});
  final String code;
}

class _PendingInvite {
  _PendingInvite({required this.token});
  final String token;
}
