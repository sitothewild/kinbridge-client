// Plain-Dart view models for KinBridge data surfaces.
//
// Mapped from Supabase tables owned by Lovable. Source of truth:
//   D:\KinBridge\lovable-docs\SUPABASE_SCHEMA.md
//   └── sessions, session_events, chat_messages, devices, device_pairings,
//       profiles, connection_codes, device_preferences
//
// These are UI-ergonomic shapes, not raw Supabase rows. The repository layer
// does the join + derivation (peerName, peerInitials, direction, online,
// fromSelf). Adding a second mapping layer would be overkill until the UI
// grows past its current surface.

import 'package:flutter/material.dart';

enum KBRoleDirection { owner, helper }

/// Mirror of Postgres enum `public.session_event_type`. Wire values are
/// snake_case; Dart values are camelCase. Use [wireName] / [fromWire] at the
/// Supabase boundary.
///
/// The four `session_*` values and `help_requested` are written by the
/// *server* (server-fn handlers, not user code) — the public `logSessionEvent`
/// endpoint rejects them. Client code only ever emits
/// {tap, scroll, keyboard, screenshot, fileSent, annotation, note}.
enum KBEventKind {
  sessionStarted,
  sessionApproved,
  sessionEnded,
  tap,
  scroll,
  keyboard,
  screenshot,
  fileSent,
  annotation,
  note,
  helpRequested,
}

extension KBEventKindWire on KBEventKind {
  String get wireName {
    switch (this) {
      case KBEventKind.sessionStarted:
        return 'session_started';
      case KBEventKind.sessionApproved:
        return 'session_approved';
      case KBEventKind.sessionEnded:
        return 'session_ended';
      case KBEventKind.tap:
        return 'tap';
      case KBEventKind.scroll:
        return 'scroll';
      case KBEventKind.keyboard:
        return 'keyboard';
      case KBEventKind.screenshot:
        return 'screenshot';
      case KBEventKind.fileSent:
        return 'file_sent';
      case KBEventKind.annotation:
        return 'annotation';
      case KBEventKind.note:
        return 'note';
      case KBEventKind.helpRequested:
        return 'help_requested';
    }
  }

  static KBEventKind? fromWire(String s) {
    for (final k in KBEventKind.values) {
      if (k.wireName == s) return k;
    }
    return null;
  }
}

/// Row from `public.sessions` with the peer identity resolved for rendering.
///
/// Schema reminder: sessions has no `summary` column — that's `notes` (text,
/// nullable). We call it [summary] in the view model because it's the
/// shorter, UI-friendlier name for a one-line history row.
class KBSession {
  KBSession({
    required this.id,
    required this.peerName,
    required this.peerInitials,
    required this.peerDevice,
    required this.startedAt,
    required this.approvedAt,
    required this.endedAt,
    required this.summary,
    required this.direction,
  });

  final String id;
  final String peerName;
  final String peerInitials;
  final String peerDevice;
  final DateTime startedAt;
  final DateTime? approvedAt;
  final DateTime? endedAt;

  /// Mapped from Postgres `sessions.notes`. First line of the field, or a
  /// synthesized fallback ("Helped with something") when notes are empty.
  final String summary;

  /// Whether the current user was the owner (receiving help) or the helper
  /// (giving help). Derived from auth.uid() vs sessions.helper_id /
  /// devices.owner_id — not a column.
  final KBRoleDirection direction;

  Duration? get duration =>
      endedAt == null ? null : endedAt!.difference(startedAt);
  bool get isLive => endedAt == null;
}

/// Row from `public.session_events`. [type] mirrors the Postgres enum;
/// [createdAt] maps from `created_at`. The schema is intentionally narrow —
/// variable-shape data lives in `payload` (jsonb). [label] / [detail] are
/// *derived* for UI display; the repository synthesizes them from
/// [type] + [payload].
class KBSessionEvent {
  KBSessionEvent({
    required this.id,
    required this.sessionId,
    required this.actorId,
    required this.type,
    required this.createdAt,
    required this.label,
    this.detail,
  });

  final String id;
  final String sessionId;
  final String? actorId;
  final KBEventKind type;
  final DateTime createdAt;
  final String label;
  final String? detail;

  IconData get icon {
    switch (type) {
      case KBEventKind.sessionStarted:
        return Icons.play_circle_outline_rounded;
      case KBEventKind.sessionApproved:
        return Icons.check_circle_outline_rounded;
      case KBEventKind.sessionEnded:
        return Icons.stop_circle_outlined;
      case KBEventKind.tap:
        return Icons.touch_app_rounded;
      case KBEventKind.scroll:
        return Icons.swipe_vertical_rounded;
      case KBEventKind.keyboard:
        return Icons.keyboard_rounded;
      case KBEventKind.screenshot:
        return Icons.photo_camera_outlined;
      case KBEventKind.fileSent:
        return Icons.attach_file_rounded;
      case KBEventKind.annotation:
        return Icons.gesture_rounded;
      case KBEventKind.note:
        return Icons.sticky_note_2_outlined;
      case KBEventKind.helpRequested:
        return Icons.pan_tool_outlined;
    }
  }
}

/// Row from `public.chat_messages`. Schema columns: `sender_id`, `body`,
/// `created_at`. We expose [fromSelf] (derived) and keep [text] / [at] as
/// ergonomic view-model names.
class KBChatMessage {
  KBChatMessage({
    required this.id,
    required this.sessionId,
    required this.senderId,
    required this.fromSelf,
    required this.text,
    required this.at,
  });

  final String id;
  final String sessionId;
  final String senderId;

  /// Derived: senderId == auth.uid() on the client. "Self" = current user,
  /// regardless of role.
  final bool fromSelf;

  /// Mapped from Postgres `chat_messages.body`.
  final String text;

  /// Mapped from Postgres `chat_messages.created_at`.
  final DateTime at;
}

/// A helper as seen from the owner's side. Join of `device_pairings`
/// (status='approved') + `profiles` (display_name, avatar_url).
///
/// [online] is *derived* client-side — there's no column. Convention:
/// `now() - last_seen < 60s` on any of their devices/presence channels.
class KBHelper {
  KBHelper({
    required this.id,
    required this.name,
    required this.initials,
    required this.online,
    this.lastSeen,
  });

  final String id;
  final String name;
  final String initials;
  final bool online;
  final DateTime? lastSeen;
}

/// Row from `public.devices` (the schema column is `name`, not `label`).
/// [online] is derived from `last_seen`, not a column.
class KBDevice {
  KBDevice({
    required this.id,
    required this.ownerName,
    required this.ownerInitials,
    required this.name,
    required this.platform,
    required this.lastSeen,
  });

  final String id;
  final String ownerName;
  final String ownerInitials;

  /// Mapped from Postgres `devices.name`.
  final String name;

  /// Mapped from Postgres `devices.platform` enum: android | ios | other.
  final String platform;

  /// Mapped from Postgres `devices.last_seen` (nullable).
  final DateTime? lastSeen;

  /// Derived: fresh heartbeat within the last 60s counts as online.
  bool get online {
    final ls = lastSeen;
    if (ls == null) return false;
    return DateTime.now().difference(ls) < const Duration(seconds: 60);
  }
}
