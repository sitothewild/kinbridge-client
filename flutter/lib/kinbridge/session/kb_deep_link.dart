// kinbridge:// deep-link handler.
//
// Contract (matches the README §7 + kinbridge-api /sessions/start response):
//
//   kinbridge://session/<sessionId>?token=<short-lived-jwt>
//   kinbridge://session?token=<short-lived-jwt>
//
// The JWT embeds sid/owner/helper/device/hs_key claims (see
// kinbridge-api/src/lib/kinbridge-token.ts). The APK validates the token only
// as a sanity check — full verification happens when we talk to the API with
// it. Today, Phase V-b, we just parse + navigate; when the HttpKBRepository
// lands, resolveSession is called first to hydrate the peer.
//
// Week-2 infra: the Android intent-filter in AndroidManifest.xml routes the
// scheme here; desktop uni_links on win/macos do the same.

import 'package:flutter/material.dart';
import '../../common.dart' show globalKey;
import '../data/kb_models.dart';
import '../data/kb_repository.dart';
import 'live_session_page.dart';

// Reuses the existing RustDesk-side [globalKey] navigator so deep-link
// pushes work from any app state (cold boot, background → foreground, or
// already-at-home). No second navigator key needed.

class KBDeepLink {
  KBDeepLink._();

  /// Return true if [uri] is a KinBridge link and was dispatched here.
  /// Caller (hooked into common.dart's handleUriLink) should short-circuit
  /// when this returns true so the RustDesk handler doesn't also fire.
  static bool tryHandle(Uri uri) {
    if (uri.scheme != "kinbridge") return false;
    if (uri.host != "session") {
      debugPrint("kb: unknown kinbridge:// host '${uri.host}' — ignoring");
      return false;
    }

    final token = uri.queryParameters["token"];
    // Path shape: /<sessionId>  OR empty (fallback to token-embedded sid).
    String? sessionId;
    if (uri.pathSegments.isNotEmpty && uri.pathSegments.first.isNotEmpty) {
      sessionId = uri.pathSegments.first;
    }

    if (token == null || token.isEmpty) {
      debugPrint("kb: kinbridge:// rejected — missing token");
      return true; // still "handled" (we don't want rustdesk to re-handle)
    }

    _openLiveSession(sessionId: sessionId, token: token);
    return true;
  }

  static Future<void> _openLiveSession({
    String? sessionId,
    required String token,
  }) async {
    final nav = globalKey.currentState;
    if (nav == null) {
      // Very early cold-boot: store and replay. In practice the KB shell is
      // up by the time uni_links fires its cold-link, but defend in depth.
      _pending = _PendingLink(sessionId: sessionId, token: token);
      return;
    }
    await _navigateIntoSession(nav, sessionId: sessionId, token: token);
  }

  static _PendingLink? _pending;

  /// Called by the KB shell after first build so any link that arrived
  /// before the navigator was ready gets replayed.
  static Future<void> drainPending() async {
    final p = _pending;
    if (p == null) return;
    _pending = null;
    final nav = globalKey.currentState;
    if (nav == null) return;
    await _navigateIntoSession(nav, sessionId: p.sessionId, token: p.token);
  }

  static Future<void> _navigateIntoSession(
    NavigatorState nav, {
    String? sessionId,
    required String token,
  }) async {
    // Phase V-b: replace with
    //   final peer = await (KBRepository.instance as HttpKBRepository)
    //       .resolveSession(sessionId: sessionId, token: token);
    // so we can render the real peer name/device and plumb token/hs_key into
    // the Rust core before navigating.
    KBSession? session;
    if (sessionId != null) {
      try {
        session = await KBRepository.instance.getSession(sessionId);
      } catch (err) {
        debugPrint("kb: getSession failed during deep-link: $err");
      }
    }
    final peerName = session?.peerName ?? "your family";
    final peerInitials = session?.peerInitials ??
        (peerName.isNotEmpty ? peerName.substring(0, 1).toUpperCase() : "?");
    final peerDevice = session?.peerDevice;

    nav.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LiveSessionPage(
          peerName: peerName,
          peerInitials: peerInitials,
          peerDevice: peerDevice,
        ),
      ),
    );
  }
}

class _PendingLink {
  _PendingLink({required this.sessionId, required this.token});
  final String? sessionId;
  final String token;
}
