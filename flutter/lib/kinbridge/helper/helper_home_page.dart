import 'package:flutter/material.dart';
import '../theme/kb_tokens.dart';
import '../widgets/kb_avatar.dart';
import '../data/kb_models.dart';
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

  @override
  void initState() {
    super.initState();
    _devices = KBRepository.instance.listDevices();
    _sessions = KBRepository.instance.listSessions(limit: 3);
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
