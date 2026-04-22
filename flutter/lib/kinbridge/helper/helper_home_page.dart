import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/kb_tokens.dart';
import '../widgets/kb_avatar.dart';
import '../data/kb_models.dart';
import '../data/kb_realtime.dart';
import '../data/kb_repository.dart';
import '../data/kb_server_fn.dart';
import '../data/kb_supabase.dart';
import '../session/live_session_page.dart';
import '../history/session_detail_page.dart';
import 'quick_connect_page.dart';

/// Helper Home (complement to spec page 7).
///
/// Not in the spec PDF as a dedicated mockup — deduced from the History /
/// Session Detail flow: helper needs a quick "who can I help right now" view.
/// Data comes from [KBRepository.instance].
class HelperHomePage extends StatefulWidget {
  const HelperHomePage({super.key, this.displayName = "Sara"});

  final String displayName;

  @override
  State<HelperHomePage> createState() => _HelperHomePageState();
}

class _HelperHomePageState extends State<HelperHomePage> {
  late Future<List<KBDevice>> _devices;
  late Future<List<KBSession>> _sessions;
  StreamSubscription<KBIncomingSession>? _inboxSub;
  bool _doorbellOpen = false;

  @override
  void initState() {
    super.initState();
    _devices = KBRepository.instance.listDevices();
    _sessions = KBRepository.instance.listSessions(limit: 3);
    // Doorbell: owner taps "Need a hand?" → sessions.INSERT with this
    // user as helper → modal pops. Subscription lives for the page
    // lifetime; no backpressure concerns at typical family volumes.
    _inboxSub = KBRealtime.incomingSessionsStream().listen(_onIncoming);
  }

  @override
  void dispose() {
    _inboxSub?.cancel();
    super.dispose();
  }

  Future<void> _onIncoming(KBIncomingSession ev) async {
    if (!mounted || _doorbellOpen) return;
    _doorbellOpen = true;
    HapticFeedback.heavyImpact();

    // Fetch minimal context so the modal isn't a generic "someone
    // needs help." Falls back to 'your family' / 'device' if the
    // device row isn't reachable (RLS shouldn't hide it — helper
    // just got a session for it — but be defensive).
    String ownerName = 'your family';
    String deviceName = 'device';
    String ownerInitials = '?';
    String? devicePeerId;
    try {
      final device = await KBSupabase.client
          .from('devices')
          .select('name, owner_id, peer_id')
          .eq('id', ev.deviceId)
          .maybeSingle();
      if (device != null) {
        deviceName = (device['name'] as String?) ?? deviceName;
        devicePeerId = device['peer_id'] as String?;
        final ownerId = device['owner_id'] as String?;
        if (ownerId != null) {
          final profile = await KBSupabase.client
              .from('profiles')
              .select('display_name')
              .eq('id', ownerId)
              .maybeSingle();
          final n = (profile?['display_name'] as String?)?.trim();
          if (n != null && n.isNotEmpty) {
            ownerName = n;
            ownerInitials = n.substring(0, 1).toUpperCase();
          }
        }
      }
    } catch (_) {
      /* best-effort context fetch — render with fallbacks */
    }

    if (!mounted) {
      _doorbellOpen = false;
      return;
    }
    await _showDoorbell(
      sessionId: ev.sessionId,
      ownerName: ownerName,
      ownerInitials: ownerInitials,
      deviceName: deviceName,
      devicePeerId: devicePeerId,
    );
    _doorbellOpen = false;
  }

  Future<void> _showDoorbell({
    required String sessionId,
    required String ownerName,
    required String ownerInitials,
    required String deviceName,
    String? devicePeerId,
  }) async {
    final action = await showModalBottomSheet<_DoorbellAction>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DoorbellSheet(
        ownerName: ownerName,
        ownerInitials: ownerInitials,
        deviceName: deviceName,
      ),
    );
    if (!mounted || action == null || action == _DoorbellAction.later) return;
    if (action == _DoorbellAction.help) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => LiveSessionPage(
            peerName: ownerName,
            peerInitials: ownerInitials,
            peerDevice: deviceName,
            sessionId: sessionId,
            devicePeerId: devicePeerId,
          ),
        ),
      );
      if (mounted) await _refresh();
    } else if (action == _DoorbellAction.message) {
      // Surface a lightweight "on my way" chat reply without opening
      // the full session UI. Idempotent: insert_chat_message RLS
      // accepts a participant sending to their own session.
      try {
        await KBSupabase.client.from('chat_messages').insert({
          'session_id': sessionId,
          'sender_id': KBSupabase.userId,
          'body': "On my way — hang tight.",
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: KB.sage,
              content: Text("Replied — $ownerName will see it.",
                  style: KBText.body(color: KB.surface)),
            ),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text("Couldn't send — try again from the session."),
            ),
          );
        }
      }
    }
  }

  Future<void> _refresh() async {
    final d = KBRepository.instance.listDevices();
    final s = KBRepository.instance.listSessions(limit: 3);
    setState(() {
      _devices = d;
      _sessions = s;
    });
    await Future.wait([d, s]);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: KB.parchment,
      child: SafeArea(
        child: RefreshIndicator(
          color: KB.amber,
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(KB.s6, KB.s4, KB.s6, KB.s10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("HELPER", style: KBText.overline()),
                          const SizedBox(height: KB.s2),
                          Text("Hi, ${widget.displayName} 👋",
                              style: KBText.title()),
                        ],
                      ),
                    ),
                    KBAvatar(
                      initials:
                          widget.displayName.substring(0, 1).toUpperCase(),
                      size: 52,
                      tint: KB.amber,
                    ),
                  ],
                ),
                const SizedBox(height: KB.s6),
                _QuickConnectCard(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const QuickConnectPage(),
                    ),
                  ),
                ),
                const SizedBox(height: KB.s6),
                Container(
                  padding: const EdgeInsets.all(KB.s5),
                  decoration: BoxDecoration(
                    color: KB.surface,
                    borderRadius: BorderRadius.circular(KB.radiusCard),
                    border: Border.all(color: KB.hairline, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Your family", style: KBText.heading()),
                      const SizedBox(height: KB.s2),
                      Text(
                        "Tap someone to start a session. They'll see an approval prompt.",
                        style: KBText.body(color: KB.muted),
                      ),
                      const SizedBox(height: KB.s5),
                      _FamilyList(future: _devices),
                    ],
                  ),
                ),
                const SizedBox(height: KB.s8),
                Text("RECENT SESSIONS", style: KBText.overline()),
                const SizedBox(height: KB.s3),
                _RecentSessions(future: _sessions),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickConnectCard extends StatelessWidget {
  const _QuickConnectCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(KB.radiusCard),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(KB.s5),
          decoration: BoxDecoration(
            color: KB.surface,
            borderRadius: BorderRadius.circular(KB.radiusCard),
            border: Border.all(color: KB.hairline, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: KB.amber.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.pin_rounded,
                    color: KB.amber, size: 22),
              ),
              const SizedBox(width: KB.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Have a code?", style: KBText.heading()),
                    const SizedBox(height: 2),
                    Text(
                      "Enter a 6-digit code to help right now.",
                      style: KBText.body(color: KB.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: KB.muted, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _FamilyList extends StatelessWidget {
  const _FamilyList({required this.future});
  final Future<List<KBDevice>> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<KBDevice>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 72,
            child: Center(child: CircularProgressIndicator(color: KB.amber)),
          );
        }
        final devices = snap.data ?? const <KBDevice>[];
        if (devices.isEmpty) {
          return Text(
            "No paired family members yet. Share a 6-digit code from Devices.",
            style: KBText.body(color: KB.muted),
          );
        }
        return Column(
          children: [
            for (int i = 0; i < devices.length; i++) ...[
              _FamilyMemberTile(device: devices[i]),
              if (i < devices.length - 1)
                Divider(color: KB.hairline, height: KB.s5),
            ],
          ],
        );
      },
    );
  }
}

class _FamilyMemberTile extends StatefulWidget {
  const _FamilyMemberTile({required this.device});
  final KBDevice device;

  @override
  State<_FamilyMemberTile> createState() => _FamilyMemberTileState();
}

class _FamilyMemberTileState extends State<_FamilyMemberTile> {
  bool _starting = false;

  Future<void> _onAction() async {
    final device = widget.device;
    if (!device.online) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: KB.deepInk,
          behavior: SnackBarBehavior.floating,
          content: Text(
            "We'll notify ${device.ownerName} you're ready to help.",
            style: KBText.body(color: KB.parchment),
          ),
        ),
      );
      return;
    }

    // Not signed in → demo-mode session (no real backend call).
    if (KBSupabase.userId == null) {
      _openLiveSession(sessionId: null);
      return;
    }

    // Signed in → real session via TanStack startSession server-fn.
    // Requires an approved device_pairing. RLS enforces that server-side;
    // if the caller isn't approved, we surface the error string.
    setState(() => _starting = true);
    try {
      final sid = await KBServerFn.startSession(deviceId: device.id);
      if (!mounted) return;
      _openLiveSession(sessionId: sid);
    } on KBServerFnError catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: KB.deepInk,
          behavior: SnackBarBehavior.floating,
          content: Text(
            err.message.contains('not approved')
                ? "${device.ownerName} hasn't approved you as a helper yet."
                : "Couldn't start the session. Try again.",
            style: KBText.body(color: KB.parchment),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _openLiveSession({required String? sessionId}) {
    final device = widget.device;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LiveSessionPage(
          peerName: device.ownerName,
          peerInitials: device.ownerInitials,
          peerDevice: device.name,
          sessionId: sessionId,
          devicePeerId: device.peerId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final String pillLabel = _starting
        ? "Starting…"
        : (device.online ? "Help now" : "Notify");
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _starting ? null : _onAction,
        borderRadius: BorderRadius.circular(KB.radiusField),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: KB.s2),
          child: Row(
            children: [
              KBAvatar(
                initials: device.ownerInitials,
                size: 48,
                online: device.online,
                tint: KB.amber,
              ),
              const SizedBox(width: KB.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.ownerName, style: KBText.label()),
                    Text(device.name, style: KBText.caption()),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: KB.s4, vertical: KB.s2),
                decoration: BoxDecoration(
                  color: device.online ? KB.amber : KB.hairline,
                  borderRadius: BorderRadius.circular(KB.radiusPill),
                ),
                child: Text(
                  pillLabel,
                  style: KBText.label(
                      color: device.online ? KB.surface : KB.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentSessions extends StatelessWidget {
  const _RecentSessions({required this.future});
  final Future<List<KBSession>> future;

  String _when(DateTime t) {
    final hour12 = t.hour == 0
        ? 12
        : (t.hour > 12 ? t.hour - 12 : t.hour);
    final ampm = t.hour < 12 ? "AM" : "PM";
    return "$hour12:${t.minute.toString().padLeft(2, '0')} $ampm";
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<KBSession>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(
            height: 96,
            decoration: BoxDecoration(
              color: KB.surface,
              borderRadius: BorderRadius.circular(KB.radiusCard),
              border: Border.all(color: KB.hairline, width: 1),
            ),
            alignment: Alignment.center,
            child: const CircularProgressIndicator(color: KB.amber),
          );
        }
        final sessions = snap.data ?? const <KBSession>[];
        if (sessions.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(KB.s5),
            decoration: BoxDecoration(
              color: KB.surface,
              borderRadius: BorderRadius.circular(KB.radiusCard),
              border: Border.all(color: KB.hairline, width: 1),
            ),
            child: Text(
              "No sessions yet. Your family will appear here once you start helping.",
              style: KBText.body(color: KB.muted),
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.all(KB.s5),
          decoration: BoxDecoration(
            color: KB.surface,
            borderRadius: BorderRadius.circular(KB.radiusCard),
            border: Border.all(color: KB.hairline, width: 1),
          ),
          child: Column(
            children: [
              for (int i = 0; i < sessions.length; i++) ...[
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              SessionDetailPage(session: sessions[i]),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: KB.s2),
                      child: Row(
                        children: [
                          KBAvatar(
                            initials: sessions[i].peerInitials,
                            size: 40,
                            tint: sessions[i].direction ==
                                    KBRoleDirection.owner
                                ? KB.amberGlow
                                : KB.sage,
                          ),
                          const SizedBox(width: KB.s4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "${sessions[i].peerName} — ${sessions[i].peerDevice}",
                                  style: KBText.label(),
                                ),
                                Text(sessions[i].summary,
                                    style: KBText.caption()),
                              ],
                            ),
                          ),
                          Text(_when(sessions[i].startedAt),
                              style: KBText.caption()),
                        ],
                      ),
                    ),
                  ),
                ),
                if (i < sessions.length - 1)
                  Divider(color: KB.hairline, height: KB.s5),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Doorbell sheet — spec page 8 rendered as a bottom-sheet modal.
//
// Full-screen dim + amber-glow avatar + owner name + "needs help" + three
// actions (Help now / Send a message / Later). The lock-screen push from
// spec page 8 is the system notification that wakes the device; this sheet
// is what the user sees once they open the app. Same signals, same three
// actions.
// ---------------------------------------------------------------------------

enum _DoorbellAction { help, message, later }

class _DoorbellSheet extends StatelessWidget {
  const _DoorbellSheet({
    required this.ownerName,
    required this.ownerInitials,
    required this.deviceName,
  });
  final String ownerName;
  final String ownerInitials;
  final String deviceName;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: KB.surface,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(KB.radiusCard)),
        ),
        padding: const EdgeInsets.fromLTRB(KB.s6, KB.s4, KB.s6, KB.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: KB.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: KB.s5),
            Row(
              children: [
                _GlowingAvatar(initials: ownerInitials),
                const SizedBox(width: KB.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("DOORBELL · NOW",
                          style: KBText.overline(color: KB.amber)),
                      const SizedBox(height: KB.s2),
                      Text("$ownerName needs help", style: KBText.title()),
                      const SizedBox(height: KB.s1),
                      Text(
                          "She tapped Ask for help just now on $deviceName.",
                          style: KBText.body(color: KB.muted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: KB.s5),
            _DoorbellButton(
              icon: Icons.play_arrow_rounded,
              label: "Help now",
              primary: true,
              onTap: () => Navigator.of(context).pop(_DoorbellAction.help),
            ),
            const SizedBox(height: KB.s3),
            _DoorbellButton(
              icon: Icons.chat_bubble_outline_rounded,
              label: "Send a message",
              primary: false,
              onTap: () =>
                  Navigator.of(context).pop(_DoorbellAction.message),
            ),
            const SizedBox(height: KB.s3),
            Center(
              child: TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(_DoorbellAction.later),
                child: Text("Later", style: KBText.label(color: KB.muted)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowingAvatar extends StatelessWidget {
  const _GlowingAvatar({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        gradient: KB.amberGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: KB.amber.withOpacity(0.45),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(initials, style: KBText.heading(color: KB.surface)),
    );
  }
}

class _DoorbellButton extends StatelessWidget {
  const _DoorbellButton({
    required this.icon,
    required this.label,
    required this.primary,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(KB.radiusPill),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: primary ? KB.amberGradient : null,
              color: primary ? null : KB.surface,
              borderRadius: BorderRadius.circular(KB.radiusPill),
              border:
                  primary ? null : Border.all(color: KB.hairline, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: KB.s4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon,
                      color: primary ? KB.surface : KB.deepInk, size: 20),
                  const SizedBox(width: KB.s2),
                  Text(label,
                      style: KBText.label(
                          color: primary ? KB.surface : KB.deepInk)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
