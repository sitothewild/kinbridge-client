// Real-data [KBRepository] implementation that queries Supabase directly.
//
// Relies on the RLS policies documented in
//   D:\KinBridge\lovable-docs\SUPABASE_SCHEMA.md
// and the PostgREST select syntax supported by `supabase_flutter 2.x`.
//
// All reads are user-JWT scoped — a helper sees only sessions they joined,
// owners only sessions on devices they own. No service-role access.
//
// Swap in at app boot after auth completes:
//
//   await KBSupabase.init();
//   await KBSupabase.signInWithPassword(email: …, password: …);
//   KBRepository.instance = SupabaseKBRepository();
//
// This file is reads-first (step V-b-3). Writes route through the server-fn
// HTTP client in `kb_server_fn.dart` (step V-b-4), not through direct table
// inserts — the server-fn path is where domain auth (TOTP on approve, reuse
// detection on startSession, etc.) is enforced.

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import 'kb_models.dart';
import 'kb_repository.dart';
import 'kb_supabase.dart';

class SupabaseKBRepository implements KBRepository {
  SupabaseKBRepository();

  SupabaseClient get _c => KBSupabase.client;
  String get _uid {
    final id = KBSupabase.userId;
    if (id == null) {
      throw StateError(
          'SupabaseKBRepository used before auth — KBSupabase.userId is null');
    }
    return id;
  }

  // ---------------------------------------------------------------------------
  // Sessions
  // ---------------------------------------------------------------------------

  /// Joins `devices` (for the owner-side data) and `profiles` (for the
  /// helper's display_name). Columns aliased to make the mapping step pure.
  static const _sessionSelect = '''
    id,
    device_id,
    helper_id,
    started_at,
    approved_at,
    ended_at,
    ended_by,
    notes,
    device:devices!inner(
      id,
      name,
      owner_id,
      platform,
      last_seen,
      owner:profiles!owner_id(id, display_name)
    ),
    helper:profiles!helper_id(id, display_name)
  ''';

  @override
  Future<List<KBSession>> listSessions({int limit = 50}) async {
    final rows = await _c
        .from('sessions')
        .select(_sessionSelect)
        .order('started_at', ascending: false)
        .limit(limit) as List<dynamic>;
    return rows
        .map((r) => _mapSession(r as Map<String, dynamic>))
        .whereType<KBSession>()
        .toList();
  }

  @override
  Future<KBSession?> getSession(String id) async {
    final row = await _c
        .from('sessions')
        .select(_sessionSelect)
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return _mapSession(row);
  }

  KBSession? _mapSession(Map<String, dynamic> row) {
    try {
      final helperId = row['helper_id'] as String?;
      final device = row['device'] as Map<String, dynamic>?;
      if (device == null) return null;

      final deviceOwnerId = device['owner_id'] as String?;
      final isHelper = helperId == _uid;
      final isOwner = deviceOwnerId == _uid;

      // Shouldn't happen — RLS filters rows the user isn't party to.
      if (!isHelper && !isOwner) return null;

      final direction =
          isHelper ? KBRoleDirection.helper : KBRoleDirection.owner;

      // Peer = the other participant.
      final Map<String, dynamic>? peerProfile = isHelper
          ? (device['owner'] as Map<String, dynamic>?)
          : (row['helper'] as Map<String, dynamic>?);
      final peerName =
          (peerProfile?['display_name'] as String?)?.trim().isNotEmpty == true
              ? peerProfile!['display_name'] as String
              : 'your family';
      final peerInitials =
          peerName.isNotEmpty ? peerName.substring(0, 1).toUpperCase() : '?';
      final peerDevice = (device['name'] as String?) ?? 'device';

      final notes = (row['notes'] as String?)?.trim() ?? '';
      final summary = notes.isEmpty
          ? (direction == KBRoleDirection.owner
              ? '$peerName helped you'
              : 'Helped $peerName')
          : notes.split('\n').first;

      return KBSession(
        id: row['id'] as String,
        peerName: peerName,
        peerInitials: peerInitials,
        peerDevice: peerDevice,
        startedAt: _ts(row['started_at'])!,
        approvedAt: _ts(row['approved_at']),
        endedAt: _ts(row['ended_at']),
        summary: summary,
        direction: direction,
      );
    } catch (err, st) {
      debugPrint('kb.supabase: failed to map session row: $err\n$st');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Session events
  // ---------------------------------------------------------------------------

  @override
  Future<List<KBSessionEvent>> listEvents(String sessionId) async {
    final rows = await _c
        .from('session_events')
        .select('id, session_id, actor_id, type, payload, created_at')
        .eq('session_id', sessionId)
        .order('created_at', ascending: true) as List<dynamic>;
    return rows
        .map((r) => _mapEvent(r as Map<String, dynamic>))
        .whereType<KBSessionEvent>()
        .toList();
  }

  KBSessionEvent? _mapEvent(Map<String, dynamic> row) {
    final type = KBEventKindWire.fromWire(row['type'] as String);
    if (type == null) return null;
    final payload =
        (row['payload'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final label = _synthLabel(type, payload);
    final detail = _synthDetail(type, payload);
    return KBSessionEvent(
      id: row['id'] as String,
      sessionId: row['session_id'] as String,
      actorId: row['actor_id'] as String?,
      type: type,
      createdAt: _ts(row['created_at'])!,
      label: label,
      detail: detail,
    );
  }

  /// Synthesize a UI label from (type, payload). Kept narrow and
  /// human-readable — payload keys vary, so we fall back to the type name.
  String _synthLabel(KBEventKind type, Map<String, dynamic> payload) {
    switch (type) {
      case KBEventKind.sessionStarted:
        return 'Session started';
      case KBEventKind.sessionApproved:
        return 'Approved';
      case KBEventKind.sessionEnded:
        return 'Session ended';
      case KBEventKind.tap:
        return payload['target'] is String
            ? 'Tapped ${payload['target']}'
            : 'Tap';
      case KBEventKind.scroll:
        return payload['target'] is String
            ? 'Scrolled ${payload['target']}'
            : 'Scroll';
      case KBEventKind.keyboard:
        return 'Typed';
      case KBEventKind.screenshot:
        return 'Screenshot saved';
      case KBEventKind.fileSent:
        return payload['name'] is String
            ? 'Sent ${payload['name']}'
            : 'File sent';
      case KBEventKind.annotation:
        return 'Annotation';
      case KBEventKind.note:
        return payload['title'] is String
            ? payload['title'] as String
            : 'Note';
      case KBEventKind.helpRequested:
        return 'Help requested';
    }
  }

  String? _synthDetail(KBEventKind type, Map<String, dynamic> payload) {
    // Most events put a human-readable detail in payload.detail or payload.message.
    final d = payload['detail'] ?? payload['message'] ?? payload['reason'];
    if (d is String && d.trim().isNotEmpty) return d;
    if (type == KBEventKind.tap &&
        payload['x'] is num &&
        payload['y'] is num) {
      return 'x=${payload['x']}, y=${payload['y']}';
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Chat
  // ---------------------------------------------------------------------------

  @override
  Future<List<KBChatMessage>> listChat(String sessionId) async {
    final rows = await _c
        .from('chat_messages')
        .select('id, session_id, sender_id, body, created_at')
        .eq('session_id', sessionId)
        .order('created_at', ascending: true) as List<dynamic>;
    return rows
        .map((r) => _mapChat(r as Map<String, dynamic>))
        .whereType<KBChatMessage>()
        .toList();
  }

  KBChatMessage _mapChat(Map<String, dynamic> row) {
    final senderId = row['sender_id'] as String;
    return KBChatMessage(
      id: row['id'] as String,
      sessionId: row['session_id'] as String,
      senderId: senderId,
      fromSelf: senderId == _uid,
      text: row['body'] as String,
      at: _ts(row['created_at'])!,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers (from owner's perspective)
  //
  // "Which helpers are approved to help me?" = device_pairings where the
  // device belongs to me + status = approved, joined with profiles.
  // ---------------------------------------------------------------------------

  @override
  Future<List<KBHelper>> listHelpers() async {
    final rows = await _c.from('device_pairings').select('''
      id,
      helper_id,
      status,
      updated_at,
      device:devices!inner(id, owner_id),
      profile:profiles!helper_id(id, display_name, avatar_url)
    ''').eq('status', 'approved') as List<dynamic>;

    final seen = <String>{};
    final out = <KBHelper>[];
    for (final r in rows) {
      final row = r as Map<String, dynamic>;
      final device = row['device'] as Map<String, dynamic>?;
      // Scope to my devices only — owner view.
      if (device == null || device['owner_id'] != _uid) continue;
      final profile = row['profile'] as Map<String, dynamic>?;
      final helperId = row['helper_id'] as String?;
      if (helperId == null || !seen.add(helperId)) continue;
      final name =
          (profile?['display_name'] as String?)?.trim().isNotEmpty == true
              ? profile!['display_name'] as String
              : 'Helper';
      final initials =
          name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';
      // Online / last_seen isn't on pairings; needs a presence channel or a
      // devices join. Leave null — UI renders "offline" until realtime lands.
      out.add(KBHelper(
        id: helperId,
        name: name,
        initials: initials,
        online: false,
        lastSeen: _ts(row['updated_at']),
      ));
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Devices
  //
  // RLS already filters: owners see their own, paired helpers see devices
  // they can help with. We join profiles to render the owner name for the
  // helper-side "Your family" list.
  // ---------------------------------------------------------------------------

  @override
  Future<List<KBDevice>> listDevices() async {
    final rows = await _c.from('devices').select('''
      id,
      owner_id,
      name,
      platform,
      last_seen,
      owner:profiles!owner_id(id, display_name)
    ''') as List<dynamic>;
    return rows.map((r) {
      final row = r as Map<String, dynamic>;
      final owner = row['owner'] as Map<String, dynamic>?;
      final ownerName =
          (owner?['display_name'] as String?)?.trim().isNotEmpty == true
              ? owner!['display_name'] as String
              : 'Family member';
      final ownerInitials =
          ownerName.isNotEmpty ? ownerName.substring(0, 1).toUpperCase() : '?';
      return KBDevice(
        id: row['id'] as String,
        ownerName: ownerName,
        ownerInitials: ownerInitials,
        name: (row['name'] as String?) ?? 'Device',
        platform: (row['platform'] as String?) ?? 'other',
        lastSeen: _ts(row['last_seen']),
      );
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  /// Supabase returns ISO-8601 strings for `timestamptz`. `.toLocal()` so
  /// the session history respects the phone's time zone.
  static DateTime? _ts(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}
