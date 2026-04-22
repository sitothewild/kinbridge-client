// TanStack Start `createServerFn` HTTP client.
//
// Contract: POST https://kinbridge.support/_serverFn/<exportName> with body
// `{"data": <validated input>}` and `Authorization: Bearer <Supabase JWT>`.
// Every function in this project chains `.middleware([requireSupabaseAuth])`
// so the header is mandatory; missing/expired token returns 401.
//
// Source of truth for endpoint shapes:
//   D:\KinBridge\lovable-docs\SERVER_FUNCTIONS.md
//
// Only endpoints called by the APK today are wrapped here. The remaining
// dashboard-only functions (checkKinBridgeHealth, saveDevicePreferences, etc.)
// can be added when the Flutter side needs them.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'kb_models.dart';
import 'kb_supabase.dart';

/// Sentinel error string returned by `updatePairingStatus` when the owner
/// has TOTP enrolled and hasn't yet supplied a code. Catch in the UI to
/// prompt for 2FA and retry with `totpCode`.
const kServerFnTotpRequired = 'TOTP_REQUIRED';

class KBServerFnError implements Exception {
  KBServerFnError(this.status, this.message, {this.raw});
  final int status;
  final String message;
  final String? raw;
  bool get isTotpRequired => message == kServerFnTotpRequired;
  @override
  String toString() => 'KBServerFnError($status): $message';
}

/// Shape returned by [KBServerFn.redeemConnectionCode]. Discriminate on
/// [mode] — "pairing" means "show waiting-for-approval", "quickconnect"
/// means "jump straight into LiveSessionPage(sessionId)".
class KBRedeemCodeResult {
  KBRedeemCodeResult({
    required this.mode,
    required this.sessionId,
    required this.pairingId,
    required this.quickconnectId,
    required this.deviceName,
  });
  final String mode;
  final String? sessionId;
  final String? pairingId;
  final String? quickconnectId;
  final String deviceName;
  bool get isQuickConnect => mode == 'quickconnect';
  bool get isPairing => mode == 'pairing';
}

/// Response from [KBServerFn.issueInstallToken]. `token` goes into
/// `kinbridge://install?token=<token>` for deep-link redemption;
/// `installCode` is a short 6-digit alternative for manual entry.
class KBInstallTokenResult {
  KBInstallTokenResult({
    required this.id,
    required this.token,
    required this.installCode,
    required this.expiresAt,
  });
  final String id;
  final String token;
  final String installCode;
  final DateTime? expiresAt;

  /// Full deep link the owner shares with the not-yet-registered device.
  String get installUrl => 'https://kinbridge.support/install/$token';
}

/// Response from [KBServerFn.createHelperInvite]. `token` goes into
/// the `https://kinbridge.support/invite/<token>` App Link that the
/// helper opens.
class KBHelperInviteResult {
  KBHelperInviteResult({
    required this.id,
    required this.token,
    required this.deviceName,
    required this.expiresAt,
  });
  final String id;
  final String token;
  final String deviceName;
  final DateTime? expiresAt;

  String get inviteUrl => 'https://kinbridge.support/invite/$token';
}

/// Lovable's `devices` row shape returned by [KBServerFn.redeemInstallToken].
class KBDeviceRow {
  KBDeviceRow({
    required this.id,
    required this.name,
    required this.platform,
    required this.ownerId,
  });
  final String id;
  final String name;
  final String platform;
  final String ownerId;
}

/// Lightweight preview of an invite token via `lookupInvite`.
///
/// Two response shapes per Lovable's `android-snippets/HELPER_INVITE.md`:
///   • **valid** — `{ valid:true, inviteId, deviceName, inviterName, note,
///     expiresAt }`
///   • **invalid** — `{ valid:false, reason:"not_found"|"revoked"|
///     "consumed"|"expired" }`
///
/// Android uses this for the preview UI on `InviteAcceptPage`; only
/// consumes the token (via `acceptHelperInvite`) once the user taps
/// Accept. Invalid → render the friendly rejection copy from
/// [friendlyReason] rather than the raw reason.
class KBInviteLookup {
  KBInviteLookup({
    required this.valid,
    required this.reason,
    required this.inviteId,
    required this.deviceName,
    required this.inviterName,
    required this.note,
    required this.expiresAt,
  });
  final bool valid;
  final String? reason;
  final String? inviteId;
  final String? deviceName;
  final String? inviterName;

  /// Optional note the inviter attached ("Hey Sara — I want you to be able
  /// to help with Dad's tablet"). Shown verbatim on the preview page.
  final String? note;

  /// Invite expiration (ISO-8601 on the wire, parsed to local time here).
  /// Preview UI can show "Expires in 3 days" via a relative-date helper.
  final DateTime? expiresAt;

  String get friendlyReason {
    switch (reason) {
      case 'not_found':
        return "That invite link doesn't exist. Double-check it with the person who sent it.";
      case 'revoked':
        return "The person who invited you cancelled this invite.";
      case 'consumed':
        return "This invite has already been used. Ask for a new link if you still need one.";
      case 'expired':
        return "This invite expired. Ask for a new one.";
      default:
        return "This invite isn't valid. Ask the inviter to send a new link.";
    }
  }
}

class KBServerFn {
  KBServerFn._();

  /// Production base URL. Preview / Lovable-published URLs documented in
  /// SERVER_FUNCTIONS.md §"Base URL"; keep them swap-in-able via a const
  /// override if we ever need preview builds.
  static const String baseUrl = 'https://kinbridge.support';

  /// Shared [http.Client]. One instance so connection keep-alive + HTTP/2
  /// stays warm across calls. Call [shutdown] on app teardown if you care
  /// (we don't today).
  static final http.Client _http = http.Client();
  static void shutdown() => _http.close();

  static Future<Map<String, dynamic>> _post(
    String exportName,
    Map<String, dynamic>? data,
  ) async {
    final token = KBSupabase.accessToken;
    if (token == null) {
      throw KBServerFnError(401, 'Not signed in (no Supabase access token)');
    }
    final uri = Uri.parse('$baseUrl/_serverFn/$exportName');
    final body = jsonEncode({'data': data ?? const <String, dynamic>{}});

    final res = await _http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      // Server-fn handlers can return non-object values too (e.g. a string).
      // Wrap so callers have a consistent shape.
      return {'value': decoded};
    }

    String message = 'HTTP ${res.statusCode}';
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['error'] is String) {
        message = decoded['error'] as String;
      } else if (decoded is Map && decoded['message'] is String) {
        message = decoded['message'] as String;
      }
    } catch (_) {
      /* body wasn't JSON */
    }
    // Log failures in every build, not just debug. Release APKs in the
    // field are exactly when we most need the post-mortem — and the
    // log body never contains auth material (we redact before send
    // and the server never echoes our token).
    final bodyPreview = res.body.length > 400
        ? '${res.body.substring(0, 400)}…'
        : res.body;
    debugPrint(
        'kb.serverFn: $exportName failed — ${res.statusCode} $message | body=$bodyPreview');
    throw KBServerFnError(res.statusCode, message, raw: res.body);
  }

  /// GET /_serverFn/getMfaStatus — the one GET endpoint in the project.
  static Future<Map<String, dynamic>> _get(String exportName) async {
    final token = KBSupabase.accessToken;
    if (token == null) {
      throw KBServerFnError(401, 'Not signed in');
    }
    final uri = Uri.parse('$baseUrl/_serverFn/$exportName');
    final res = await _http.get(uri, headers: {
      'Authorization': 'Bearer $token',
    });
    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'value': decoded};
    }
    String message = 'HTTP ${res.statusCode}';
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['error'] is String) {
        message = decoded['error'] as String;
      }
    } catch (_) {}
    throw KBServerFnError(res.statusCode, message, raw: res.body);
  }

  // ---------------------------------------------------------------------------
  // Pairing flow
  // ---------------------------------------------------------------------------

  /// Owner-side: mint a 6-digit code for a device. TTL 120s, zero-padded,
  /// invalidates prior unconsumed codes.
  static Future<({String code, DateTime expiresAt, int ttlSeconds})>
      generateConnectionCode({required String deviceId}) async {
    final r = await _post('generateConnectionCode', {'deviceId': deviceId});
    return (
      code: r['code'] as String,
      expiresAt: DateTime.parse(r['expiresAt'] as String).toLocal(),
      ttlSeconds: (r['ttlSeconds'] as num).toInt(),
    );
  }

  /// Helper-side: redeem a 6-digit code. Server looks at the underlying
  /// [connection_codes.mode] and returns one of two shapes:
  ///
  /// - **pairing** — creates a `pending` device_pairing, owner still has
  ///   to approve (possibly with TOTP). UI: "Request sent, waiting for
  ///   owner to approve."
  /// - **quickconnect** — a one-shot support session that skips pairing
  ///   entirely. Owner pre-consented by issuing the code, so a pre-
  ///   approved [sessions] row + [quickconnect_sessions] audit row are
  ///   created. UI: jump straight into LiveSessionPage(sessionId).
  ///
  /// See `android-snippets/QUICKCONNECT.md` for the full spec.
  static Future<KBRedeemCodeResult> redeemConnectionCode({
    required String code,
  }) async {
    final r = await _post('redeemConnectionCode', {'code': code});
    return KBRedeemCodeResult(
      mode: r['mode'] as String? ?? 'pairing',
      sessionId: r['sessionId'] as String?,
      pairingId: r['pairingId'] as String?,
      quickconnectId: r['quickconnectId'] as String?,
      deviceName: (r['deviceName'] as String?) ?? 'device',
    );
  }

  /// Owner-side (opt-in): end an active QuickConnect session.
  /// See `android-snippets/QUICKCONNECT.md`. Either participant may call.
  static Future<void> endQuickConnectSession({
    required String quickconnectId,
  }) async {
    await _post(
      'endQuickConnectSession',
      {'quickconnectId': quickconnectId},
    );
  }

  /// Redeem an install token (kinbridge://install?token=…). Called on
  /// first launch when no local `device_id` is stored. Creates the
  /// `devices` row bound to the token's original owner (not the caller's
  /// auth.uid — that's stored in `consumed_by` for audit).
  ///
  /// See `android-snippets/INSTALL_TOKEN.md`.
  static Future<KBDeviceRow> redeemInstallToken({
    required String token,
  }) async {
    final r = await _post('redeemInstallToken', {'token': token});
    // Lovable's server-fn response wraps the device in a `result` envelope.
    final inner =
        (r['result'] as Map<String, dynamic>?) ?? r;
    final d = (inner['device'] as Map).cast<String, dynamic>();
    return KBDeviceRow(
      id: d['id'] as String,
      name: d['name'] as String? ?? 'device',
      platform: d['platform'] as String? ?? 'android',
      ownerId: d['owner_id'] as String? ?? '',
    );
  }

  /// Helper-side: preview an invite without consuming it. Renders the
  /// `/invite/<token>` preview page before the user taps Accept.
  static Future<KBInviteLookup> lookupInvite({required String token}) async {
    final r = await _post('lookupInvite', {'token': token});
    final expiresRaw = r['expiresAt'];
    return KBInviteLookup(
      valid: (r['valid'] as bool?) ?? false,
      reason: r['reason'] as String?,
      inviteId: r['inviteId'] as String?,
      deviceName: r['deviceName'] as String?,
      inviterName: r['inviterName'] as String?,
      note: r['note'] as String?,
      expiresAt: expiresRaw is String
          ? DateTime.tryParse(expiresRaw)?.toLocal()
          : null,
    );
  }

  /// Helper-side: consume an invite. Creates an **approved**
  /// device_pairing row (owner pre-consented by issuing the invite — no
  /// second round-trip). See `android-snippets/HELPER_INVITE.md`.
  static Future<({String pairingId, String deviceId})> acceptHelperInvite({
    required String token,
  }) async {
    final r = await _post('acceptHelperInvite', {'token': token});
    return (
      pairingId: r['pairingId'] as String,
      deviceId: r['deviceId'] as String,
    );
  }

  /// Owner-side: approve or revoke a pending pairing. If owner has TOTP
  /// enrolled, [totpCode] is required when approving; catch
  /// [KBServerFnError.isTotpRequired] and retry with a code.
  static Future<void> updatePairingStatus({
    required String pairingId,
    required String status, // 'approved' | 'revoked'
    String? totpCode,
  }) async {
    await _post('updatePairingStatus', {
      'pairingId': pairingId,
      'status': status,
      if (totpCode != null) 'totpCode': totpCode,
    });
  }

  /// Owner-side: register a device on their account. Returns the full row.
  static Future<Map<String, dynamic>> createDevice({
    required String name,
    String platform = 'android',
  }) async {
    final r = await _post('createDevice', {
      'name': name,
      'platform': platform,
    });
    return (r['device'] as Map).cast<String, dynamic>();
  }

  /// Owner-side: issue an install-token pair for a not-yet-registered device
  /// (e.g. mom wants to send the KinBridge install link to daughter's
  /// tablet). Returns both the long-form `token` (used in the
  /// `kinbridge://install?token=…` deep link) and a short 6-digit
  /// `installCode` for manual entry. Per Lovable's
  /// `devices.functions.ts → issueInstallToken`.
  static Future<KBInstallTokenResult> issueInstallToken({
    required String proposedName,
    String proposedPlatform = 'android',
  }) async {
    final r = await _post('issueInstallToken', {
      'proposedName': proposedName,
      'proposedPlatform': proposedPlatform,
    });
    return KBInstallTokenResult(
      id: r['id'] as String,
      token: r['token'] as String,
      installCode: r['installCode'] as String? ?? '',
      expiresAt: r['expiresAt'] is String
          ? DateTime.tryParse(r['expiresAt'] as String)?.toLocal()
          : null,
    );
  }

  /// Owner-side: generate a helper invite for one of their devices.
  /// Response: `{id, token, expiresAt, deviceName}` per
  /// `invites.functions.ts → createHelperInvite`. The `token` is embedded
  /// into `https://kinbridge.support/invite/<token>` which the helper
  /// opens to accept.
  static Future<KBHelperInviteResult> createHelperInvite({
    required String deviceId,
    String? note,
  }) async {
    final r = await _post('createHelperInvite', {
      'deviceId': deviceId,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    return KBHelperInviteResult(
      id: r['id'] as String,
      token: r['token'] as String,
      deviceName: r['deviceName'] as String? ?? 'device',
      expiresAt: r['expiresAt'] is String
          ? DateTime.tryParse(r['expiresAt'] as String)?.toLocal()
          : null,
    );
  }

  /// Owner-side: revoke a pending helper invite.
  static Future<void> revokeHelperInvite({required String inviteId}) async {
    await _post('revokeHelperInvite', {'inviteId': inviteId});
  }

  /// Owner-side: revoke an outstanding install token (before it's redeemed).
  static Future<void> revokeInstallToken({required String tokenId}) async {
    await _post('revokeInstallToken', {'tokenId': tokenId});
  }

  // ---------------------------------------------------------------------------
  // Session lifecycle
  // ---------------------------------------------------------------------------

  /// Helper-side: open a session with an approved device. Reuses an open
  /// session if one exists (idempotent).
  static Future<String> startSession({required String deviceId}) async {
    final r = await _post('startSession', {'deviceId': deviceId});
    return r['sessionId'] as String;
  }

  /// Owner-side: consent to an active session (idempotent).
  static Future<void> approveSession({required String sessionId}) async {
    await _post('approveSession', {'sessionId': sessionId});
  }

  /// Either side: end the session. Idempotent.
  static Future<void> endSession({required String sessionId}) async {
    await _post('endSession', {'sessionId': sessionId});
  }

  /// Append an event to the session timeline. Server rejects the four
  /// server-only types (sessionStarted/Approved/Ended, helpRequested) —
  /// the enum wire-value is checked against a narrower zod schema.
  static Future<void> logSessionEvent({
    required String sessionId,
    required KBEventKind type,
    Map<String, dynamic>? payload,
  }) async {
    await _post('logSessionEvent', {
      'sessionId': sessionId,
      'type': type.wireName,
      if (payload != null) 'payload': payload,
    });
  }

  /// Owner-side: raise a help request inside a session. If the device's
  /// `auto_accept_help` preference is set, the session is auto-approved as
  /// a side effect (returned in [autoAccepted]).
  static Future<({bool autoAccepted})> requestHelp({
    required String sessionId,
    String? message,
  }) async {
    final r = await _post('requestHelp', {
      'sessionId': sessionId,
      if (message != null) 'message': message,
    });
    return (autoAccepted: (r['autoAccepted'] as bool?) ?? false);
  }

  /// Owner-side: attach notes to a session. Max 5000 chars server-side.
  static Future<void> saveSessionNotes({
    required String sessionId,
    required String notes,
  }) async {
    await _post('saveSessionNotes', {
      'sessionId': sessionId,
      'notes': notes,
    });
  }

  /// Owner-side: upsert per-device prefs (notifications, auto-accept).
  static Future<void> saveDevicePreferences({
    required String deviceId,
    required bool notificationsEnabled,
    required bool autoAcceptHelp,
  }) async {
    await _post('saveDevicePreferences', {
      'deviceId': deviceId,
      'notificationsEnabled': notificationsEnabled,
      'autoAcceptHelp': autoAcceptHelp,
    });
  }

  // ---------------------------------------------------------------------------
  // KinBridge agent bridge (dashboard → agent deep-link minting)
  // ---------------------------------------------------------------------------

  /// Ask the dashboard to mint a `kinbridge://` deep-link by calling our
  /// agent. Always returns 200 — failures come back as `connectUrl == null`
  /// with a human-readable `error`.
  static Future<({String? connectUrl, String? error})>
      startKinBridgeSession({required String sessionId}) async {
    final r = await _post('startKinBridgeSession', {'sessionId': sessionId});
    return (
      connectUrl: r['connectUrl'] as String?,
      error: r['error'] as String?,
    );
  }

  // ---------------------------------------------------------------------------
  // MFA / TOTP
  // ---------------------------------------------------------------------------

  static Future<({bool enabled, String? factorId})> getMfaStatus() async {
    final r = await _get('getMfaStatus');
    return (
      enabled: (r['enabled'] as bool?) ?? false,
      factorId: r['factorId'] as String?,
    );
  }

  /// Verify a TOTP code on demand — used to gate sensitive actions
  /// client-side. Throws `Error("Invalid 2FA code")` on mismatch.
  static Future<void> verifyTotp({required String code}) async {
    await _post('verifyTotp', {'code': code});
  }
}
