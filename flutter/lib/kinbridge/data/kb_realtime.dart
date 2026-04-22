// Realtime subscriptions for session-scoped tables.
//
// Wraps Supabase Realtime's `postgres_changes` so UI code consumes plain
// [Stream]s of DTO rows. Row shape mapping lives here (same helpers as
// [SupabaseKBRepository]) — intentional duplication to keep the realtime
// path independent of the repo's joined-row selects.
//
// Topic authorization is handled by the SECURITY DEFINER
// `can_access_realtime_topic` helper on the Postgres side (see
// SUPABASE_SCHEMA.md §"Realtime topic authorization"). We don't authorize
// here; the server rejects unauthorized subscribe attempts.
//
// Usage:
//
//   final sub = KBRealtime.chatStream(sessionId).listen((msg) { ... });
//   // later
//   await sub.cancel();

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import 'kb_models.dart';
import 'kb_supabase.dart';

class KBRealtime {
  KBRealtime._();

  /// INSERTs on `chat_messages` for one session. Emits the mapped
  /// [KBChatMessage] (with `fromSelf` resolved via [KBSupabase.userId]).
  static Stream<KBChatMessage> chatStream(String sessionId) {
    final ctrl = StreamController<KBChatMessage>();
    final channel = KBSupabase.client.channel('chat:$sessionId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'chat_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'session_id',
          value: sessionId,
        ),
        callback: (payload) {
          try {
            final row = payload.newRecord;
            final msg = _mapChat(row);
            if (!ctrl.isClosed) ctrl.add(msg);
          } catch (err, st) {
            if (kDebugMode) debugPrint('kb.realtime.chat: $err\n$st');
          }
        },
      )
      ..subscribe();

    ctrl.onCancel = () async {
      await KBSupabase.client.removeChannel(channel);
    };
    return ctrl.stream;
  }

  /// INSERTs on `session_events` for one session.
  static Stream<KBSessionEvent> eventsStream(String sessionId) {
    final ctrl = StreamController<KBSessionEvent>();
    final channel = KBSupabase.client.channel('events:$sessionId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'session_events',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'session_id',
          value: sessionId,
        ),
        callback: (payload) {
          try {
            final row = payload.newRecord;
            final ev = _mapEvent(row);
            if (ev != null && !ctrl.isClosed) ctrl.add(ev);
          } catch (err, st) {
            if (kDebugMode) debugPrint('kb.realtime.events: $err\n$st');
          }
        },
      )
      ..subscribe();

    ctrl.onCancel = () async {
      await KBSupabase.client.removeChannel(channel);
    };
    return ctrl.stream;
  }

  /// UPDATEs on `sessions` for one session — how a helper notices the owner
  /// just approved, or either side notices the session ended.
  static Stream<KBSessionLifecycle> sessionLifecycleStream(
    String sessionId,
  ) {
    final ctrl = StreamController<KBSessionLifecycle>();
    final channel = KBSupabase.client.channel('session:$sessionId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'sessions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: sessionId,
        ),
        callback: (payload) {
          try {
            final row = payload.newRecord;
            final update = KBSessionLifecycle(
              sessionId: row['id'] as String,
              approvedAt: _ts(row['approved_at']),
              endedAt: _ts(row['ended_at']),
              endedBy: row['ended_by'] as String?,
            );
            if (!ctrl.isClosed) ctrl.add(update);
          } catch (err, st) {
            if (kDebugMode) {
              debugPrint('kb.realtime.sessionLifecycle: $err\n$st');
            }
          }
        },
      )
      ..subscribe();

    ctrl.onCancel = () async {
      await KBSupabase.client.removeChannel(channel);
    };
    return ctrl.stream;
  }

  /// INSERTs on `sessions` where `helper_id = current user`. Fires when
  /// an owner taps "Need a hand?" and creates a session with this
  /// helper as the target. The helper-side UI uses this to pop a
  /// doorbell-style notification overlay so the helper can jump in
  /// without having to poll or refresh their home screen.
  ///
  /// Emits a minimal [KBIncomingSession] pulled straight from the
  /// realtime payload (no joins — the consumer fetches device / owner
  /// metadata lazily when the user acts on the notification).
  static Stream<KBIncomingSession> incomingSessionsStream() {
    final uid = KBSupabase.userId;
    if (uid == null) {
      return const Stream<KBIncomingSession>.empty();
    }
    final ctrl = StreamController<KBIncomingSession>();
    final channel = KBSupabase.client.channel('helper-inbox:$uid')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'sessions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'helper_id',
          value: uid,
        ),
        callback: (payload) {
          try {
            final row = payload.newRecord;
            final ev = KBIncomingSession(
              sessionId: row['id'] as String,
              deviceId: row['device_id'] as String,
              helperId: row['helper_id'] as String,
              startedAt: _ts(row['started_at']),
            );
            if (!ctrl.isClosed) ctrl.add(ev);
          } catch (err, st) {
            if (kDebugMode) {
              debugPrint('kb.realtime.helperInbox: $err\n$st');
            }
          }
        },
      )
      ..subscribe();

    ctrl.onCancel = () async {
      await KBSupabase.client.removeChannel(channel);
    };
    return ctrl.stream;
  }

  // ---------------------------------------------------------------------------
  // Row mappers (kept local — parallel to SupabaseKBRepository's; can be
  // extracted if they diverge). Intentionally tolerant: any shape hiccup is
  // logged and the row is dropped, never crashes the stream.
  // ---------------------------------------------------------------------------

  static KBChatMessage _mapChat(Map<String, dynamic> row) {
    final senderId = row['sender_id'] as String;
    return KBChatMessage(
      id: row['id'] as String,
      sessionId: row['session_id'] as String,
      senderId: senderId,
      fromSelf: senderId == KBSupabase.userId,
      text: row['body'] as String,
      at: _ts(row['created_at'])!,
    );
  }

  static KBSessionEvent? _mapEvent(Map<String, dynamic> row) {
    final type = KBEventKindWire.fromWire(row['type'] as String);
    if (type == null) return null;
    final payload = (row['payload'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    return KBSessionEvent(
      id: row['id'] as String,
      sessionId: row['session_id'] as String,
      actorId: row['actor_id'] as String?,
      type: type,
      createdAt: _ts(row['created_at'])!,
      label: _synthLabel(type, payload),
      detail: _synthDetail(type, payload),
    );
  }

  static String _synthLabel(KBEventKind type, Map<String, dynamic> payload) {
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

  static String? _synthDetail(KBEventKind type, Map<String, dynamic> payload) {
    final d = payload['detail'] ?? payload['message'] ?? payload['reason'];
    if (d is String && d.trim().isNotEmpty) return d;
    if (type == KBEventKind.tap &&
        payload['x'] is num &&
        payload['y'] is num) {
      return 'x=${payload['x']}, y=${payload['y']}';
    }
    return null;
  }

  static DateTime? _ts(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}

/// A brand-new `sessions` INSERT where the current user is the
/// helper. Minimal shape — just enough to decide whether to render the
/// doorbell and which device to fetch context for.
class KBIncomingSession {
  KBIncomingSession({
    required this.sessionId,
    required this.deviceId,
    required this.helperId,
    required this.startedAt,
  });
  final String sessionId;
  final String deviceId;
  final String helperId;
  final DateTime? startedAt;
}

/// Snapshot of the lifecycle columns on `sessions` when they change. The
/// session itself has its own row in Supabase; this is the subset the UI
/// cares about (did it get approved? did it end?).
class KBSessionLifecycle {
  KBSessionLifecycle({
    required this.sessionId,
    required this.approvedAt,
    required this.endedAt,
    required this.endedBy,
  });
  final String sessionId;
  final DateTime? approvedAt;
  final DateTime? endedAt;
  final String? endedBy;

  bool get isApproved => approvedAt != null;
  bool get isEnded => endedAt != null;
}

/// Convenience: send a chat message from the APK. Inserts directly into
/// `chat_messages` — RLS policy "Participants can send chat messages"
/// enforces sender_id = auth.uid() + session participation.
///
/// This lives alongside the realtime subscriptions rather than on
/// [KBServerFn] because there's no server-fn wrapping it — chat writes go
/// straight to the table. Mirrors the pattern the dashboard uses.
Future<void> kbSendChat({
  required String sessionId,
  required String body,
}) async {
  final uid = KBSupabase.userId;
  if (uid == null) throw StateError('kbSendChat: not signed in');
  final trimmed = body.trim();
  if (trimmed.isEmpty) return;
  await KBSupabase.client.from('chat_messages').insert({
    'session_id': sessionId,
    'sender_id': uid,
    'body': trimmed,
  });
}
