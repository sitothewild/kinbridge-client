// KinBridge data repository.
//
// The APK talks to Supabase directly (user-JWT scoped via RLS — see
// SUPABASE_SCHEMA.md for the policies) and to TanStack server functions at
// https://kinbridge.support/_serverFn/<name> for writes that need
// domain-authorization checks beyond RLS (see SERVER_FUNCTIONS.md).
//
// [KBRepository.instance] is the single swap point. Today it's the
// [FakeKBRepository]; once auth + SupabaseKBRepository land (step V-b-3/4),
// flip the assignment at app boot.

import 'kb_models.dart';

abstract class KBRepository {
  static KBRepository instance = FakeKBRepository();

  Future<List<KBSession>> listSessions({int limit = 50});
  Future<KBSession?> getSession(String id);
  Future<List<KBSessionEvent>> listEvents(String sessionId);
  Future<List<KBChatMessage>> listChat(String sessionId);
  Future<List<KBHelper>> listHelpers();
  Future<List<KBDevice>> listDevices();
}

/// In-memory canned data so the UI has something to render before Supabase
/// is wired. Data shapes match what [SupabaseKBRepository] (Phase V-b-3) will
/// return, so no UI code changes on the swap.
class FakeKBRepository implements KBRepository {
  late final List<KBSession> _sessions = _seedSessions();
  late final Map<String, List<KBSessionEvent>> _events = _seedEvents();
  late final Map<String, List<KBChatMessage>> _chat = _seedChat();

  @override
  Future<List<KBSession>> listSessions({int limit = 50}) async {
    return List<KBSession>.from(_sessions.take(limit));
  }

  @override
  Future<KBSession?> getSession(String id) async {
    for (final s in _sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Future<List<KBSessionEvent>> listEvents(String sessionId) async {
    return List<KBSessionEvent>.from(_events[sessionId] ?? const []);
  }

  @override
  Future<List<KBChatMessage>> listChat(String sessionId) async {
    return List<KBChatMessage>.from(_chat[sessionId] ?? const []);
  }

  @override
  Future<List<KBHelper>> listHelpers() async {
    final now = DateTime.now();
    return [
      KBHelper(
        id: "helper-sara",
        name: "Sara",
        initials: "S",
        online: true,
        lastSeen: now,
      ),
      KBHelper(
        id: "helper-james",
        name: "James",
        initials: "J",
        online: true,
        lastSeen: now,
      ),
      KBHelper(
        id: "helper-priya",
        name: "Priya",
        initials: "P",
        online: false,
        lastSeen: now.subtract(const Duration(hours: 2)),
      ),
    ];
  }

  @override
  Future<List<KBDevice>> listDevices() async {
    final now = DateTime.now();
    return [
      KBDevice(
        id: "device-mom",
        ownerName: "Mom",
        ownerInitials: "M",
        name: "Pixel 8",
        platform: "android",
        lastSeen: now,
      ),
      KBDevice(
        id: "device-dad",
        ownerName: "Dad",
        ownerInitials: "D",
        name: "Galaxy A54",
        platform: "android",
        lastSeen: now.subtract(const Duration(hours: 3)),
      ),
      KBDevice(
        id: "device-james",
        ownerName: "James",
        ownerInitials: "J",
        name: "Pixel 7",
        platform: "android",
        lastSeen: now,
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Seed data
  // ---------------------------------------------------------------------------

  static List<KBSession> _seedSessions() {
    final now = DateTime.now();
    KBSession mk({
      required String id,
      required String peer,
      required String peerInit,
      required String device,
      required Duration ago,
      required Duration length,
      required String summary,
      required KBRoleDirection direction,
    }) {
      final started = now.subtract(ago);
      return KBSession(
        id: id,
        peerName: peer,
        peerInitials: peerInit,
        peerDevice: device,
        startedAt: started,
        approvedAt: started.add(const Duration(seconds: 6)),
        endedAt: started.add(length),
        summary: summary,
        direction: direction,
      );
    }

    return [
      mk(
        id: "sess-1",
        peer: "Sara",
        peerInit: "S",
        device: "iPhone 15",
        ago: const Duration(hours: 2, minutes: 6),
        length: const Duration(minutes: 6),
        summary: "Helped with Wi-Fi settings",
        direction: KBRoleDirection.owner,
      ),
      mk(
        id: "sess-2",
        peer: "James",
        peerInit: "J",
        device: "Galaxy A54",
        ago: const Duration(days: 1, hours: 3),
        length: const Duration(minutes: 9),
        summary: "Showed how to send a photo",
        direction: KBRoleDirection.helper,
      ),
      mk(
        id: "sess-3",
        peer: "Sara",
        peerInit: "S",
        device: "iPhone 15",
        ago: const Duration(days: 3, hours: 1),
        length: const Duration(minutes: 18),
        summary: "Updated the email app",
        direction: KBRoleDirection.owner,
      ),
      mk(
        id: "sess-4",
        peer: "Priya",
        peerInit: "P",
        device: "Pixel 7",
        ago: const Duration(days: 7, hours: 4),
        length: const Duration(minutes: 12),
        summary: "Set up two-factor sign-in",
        direction: KBRoleDirection.owner,
      ),
    ];
  }

  static Map<String, List<KBSessionEvent>> _seedEvents() {
    final start = DateTime.now().subtract(const Duration(hours: 2, minutes: 6));
    KBSessionEvent ev({
      required String id,
      required String sid,
      required KBEventKind type,
      required Duration offset,
      required String label,
      String? detail,
      String? actorId,
    }) =>
        KBSessionEvent(
          id: id,
          sessionId: sid,
          actorId: actorId,
          type: type,
          createdAt: start.add(offset),
          label: label,
          detail: detail,
        );

    return {
      "sess-1": [
        ev(
            id: "ev-1",
            sid: "sess-1",
            type: KBEventKind.sessionStarted,
            offset: Duration.zero,
            label: "Session started",
            detail: "Sara connected from iPhone 15"),
        ev(
            id: "ev-2",
            sid: "sess-1",
            type: KBEventKind.sessionApproved,
            offset: const Duration(seconds: 6),
            label: "Approved",
            detail: "Mom tapped Allow"),
        ev(
            id: "ev-3",
            sid: "sess-1",
            type: KBEventKind.tap,
            offset: const Duration(minutes: 1, seconds: 4),
            label: "Tapped Settings",
            detail: "x=312, y=488"),
        ev(
            id: "ev-4",
            sid: "sess-1",
            type: KBEventKind.scroll,
            offset: const Duration(minutes: 1, seconds: 18),
            label: "Scrolled to Wi-Fi"),
        ev(
            id: "ev-5",
            sid: "sess-1",
            type: KBEventKind.tap,
            offset: const Duration(minutes: 1, seconds: 29),
            label: "Turned Wi-Fi on"),
        ev(
            id: "ev-6",
            sid: "sess-1",
            type: KBEventKind.screenshot,
            offset: const Duration(minutes: 2, seconds: 11),
            label: "Screenshot saved",
            detail: "Wi-Fi network list"),
        ev(
            id: "ev-7",
            sid: "sess-1",
            type: KBEventKind.note,
            offset: const Duration(minutes: 3, seconds: 2),
            label: "Connected to HomeNet-5G",
            detail: "Signal strong · password saved"),
        ev(
            id: "ev-8",
            sid: "sess-1",
            type: KBEventKind.sessionEnded,
            offset: const Duration(minutes: 6),
            label: "Session ended",
            detail: "Ended by Sara"),
      ],
      "sess-2": [
        ev(
            id: "ev-10",
            sid: "sess-2",
            type: KBEventKind.sessionStarted,
            offset: Duration.zero,
            label: "Session started",
            detail: "Helped James"),
        ev(
            id: "ev-11",
            sid: "sess-2",
            type: KBEventKind.note,
            offset: const Duration(minutes: 4),
            label: "Explained Photos share sheet"),
        ev(
            id: "ev-12",
            sid: "sess-2",
            type: KBEventKind.sessionEnded,
            offset: const Duration(minutes: 9),
            label: "Session ended"),
      ],
      "sess-3": [
        ev(
            id: "ev-13",
            sid: "sess-3",
            type: KBEventKind.sessionStarted,
            offset: Duration.zero,
            label: "Session started"),
        ev(
            id: "ev-14",
            sid: "sess-3",
            type: KBEventKind.note,
            offset: const Duration(minutes: 6),
            label: "Updated Mail to 7.2"),
        ev(
            id: "ev-15",
            sid: "sess-3",
            type: KBEventKind.sessionEnded,
            offset: const Duration(minutes: 18),
            label: "Session ended"),
      ],
      "sess-4": [
        ev(
            id: "ev-16",
            sid: "sess-4",
            type: KBEventKind.sessionStarted,
            offset: Duration.zero,
            label: "Session started"),
        ev(
            id: "ev-17",
            sid: "sess-4",
            type: KBEventKind.note,
            offset: const Duration(minutes: 3),
            label: "Enrolled in 2FA via authenticator app"),
        ev(
            id: "ev-18",
            sid: "sess-4",
            type: KBEventKind.sessionEnded,
            offset: const Duration(minutes: 12),
            label: "Session ended"),
      ],
    };
  }

  static Map<String, List<KBChatMessage>> _seedChat() {
    final now = DateTime.now();
    KBChatMessage msg({
      required String id,
      required String sid,
      required bool fromSelf,
      required String senderId,
      required String text,
      required Duration ago,
    }) =>
        KBChatMessage(
          id: id,
          sessionId: sid,
          senderId: senderId,
          fromSelf: fromSelf,
          text: text,
          at: now.subtract(ago),
        );

    return {
      "sess-1": [
        msg(
            id: "c1",
            sid: "sess-1",
            fromSelf: true,
            senderId: "uid-self",
            text: "I can't find the Wi-Fi settings.",
            ago: const Duration(hours: 2, minutes: 5)),
        msg(
            id: "c2",
            sid: "sess-1",
            fromSelf: false,
            senderId: "uid-sara",
            text: "No worries Mom — I'll show you. Hold on one sec.",
            ago: const Duration(hours: 2, minutes: 4, seconds: 40)),
        msg(
            id: "c3",
            sid: "sess-1",
            fromSelf: false,
            senderId: "uid-sara",
            text: "All set — you're on HomeNet-5G.",
            ago: const Duration(hours: 2, minutes: 1)),
        msg(
            id: "c4",
            sid: "sess-1",
            fromSelf: true,
            senderId: "uid-self",
            text: "Thank you sweetie ❤️",
            ago: const Duration(hours: 2)),
      ],
    };
  }
}
