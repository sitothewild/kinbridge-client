// HTTP client for the kinbridge-api Fastify service (distinct from
// Lovable's TanStack server-fn surface at kinbridge.support/_serverFn).
//
// Base URL:   https://api.kinbridge.dev
// Source:     D:\KinBridge\kinbridge-server\kinbridge-api\src
//
// Authenticated by a **kinbridge_token** JWT minted by
// POST /api/sessions/start → handed to the client via Lovable's
// startSession server-fn response → used here on POST
// /v1/sessions/:id/resolve.
//
// Today only the resolve endpoint is wrapped — that's the one the
// Android helper needs to open a remote-view session. Heartbeat and
// device-peer endpoints can be added here when we wire the per-device
// JWT pipeline.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'kb_server_fn.dart' show KBServerFnError;

/// Response from `POST /v1/sessions/:id/resolve`. See
/// `kinbridge-api/src/routes/v1-sessions.ts`.
class KBResolveResult {
  KBResolveResult({
    required this.sessionId,
    required this.relayHost,
    required this.relayPort,
    required this.rendezvousToken,
    required this.iceServers,
    required this.deviceFingerprint,
  });
  final String sessionId;
  final String relayHost;
  final int relayPort;

  /// Short-lived token the Rust core passes to hbbs as `connToken` in
  /// [KBRemoteConnection.connect]. Bound to the session id so it can't
  /// be reused across sessions.
  final String rendezvousToken;

  /// STUN/TURN ICE servers for NAT traversal. Each entry is a map
  /// with `urls` (comma-separated) and optional `username`/`credential`.
  final List<Map<String, dynamic>> iceServers;

  /// Base64 Ed25519 pubkey the Rust core uses to verify the relay's
  /// identity (prevents MITM even if DNS is compromised).
  final String deviceFingerprint;
}

class KBApi {
  KBApi._();

  /// Production base URL. Matches CF Tunnel hostname in HANDOFF.
  static const String baseUrl = 'https://api.kinbridge.dev';

  static final http.Client _http = http.Client();
  static void shutdown() => _http.close();

  /// Resolve a session's relay connection config. Called by the helper
  /// just before `gFFI.start(peerId, connToken: rendezvousToken, …)`.
  ///
  /// The [kinbridgeToken] is the JWT handed back by Lovable's
  /// `startSession` server-fn — it has session_id in its `sid` claim
  /// and kinbridge-api rejects the call if `sid !== id` (403).
  static Future<KBResolveResult> resolveSession({
    required String sessionId,
    required String kinbridgeToken,
  }) async {
    final uri = Uri.parse('$baseUrl/v1/sessions/$sessionId/resolve');
    final res = await _http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $kinbridgeToken',
        'Content-Type': 'application/json',
      },
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final ice = (body['ice_servers'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      return KBResolveResult(
        sessionId: body['session_id'] as String? ?? sessionId,
        relayHost: body['relay_host'] as String? ?? '',
        relayPort: (body['relay_port'] as num?)?.toInt() ?? 21117,
        rendezvousToken: body['rendezvous_token'] as String? ?? '',
        iceServers: ice,
        deviceFingerprint: body['device_fingerprint'] as String? ?? '',
      );
    }
    String message = 'HTTP ${res.statusCode}';
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['error'] is String) {
        message = decoded['error'] as String;
      }
    } catch (_) {/* body wasn't JSON */}
    final bodyPreview =
        res.body.length > 400 ? '${res.body.substring(0, 400)}…' : res.body;
    debugPrint(
        'kb.api.resolve: $sessionId failed — ${res.statusCode} $message | body=$bodyPreview');
    throw KBServerFnError(res.statusCode, message, raw: res.body);
  }
}
