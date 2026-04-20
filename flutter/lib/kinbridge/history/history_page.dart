import 'package:flutter/material.dart';
import '../theme/kb_tokens.dart';
import '../widgets/kb_avatar.dart';
import '../data/kb_models.dart';
import '../data/kb_repository.dart';
import 'session_detail_page.dart';

/// History (spec page 11).
///
/// Shows past sessions grouped by date ("Today", "Yesterday", "This week",
/// "Earlier"). Tapping a row opens [SessionDetailPage].
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late Future<List<KBSession>> _future;

  @override
  void initState() {
    super.initState();
    _future = KBRepository.instance.listSessions();
  }

  Future<void> _refresh() async {
    final next = KBRepository.instance.listSessions();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: KB.parchment,
      child: SafeArea(
        child: RefreshIndicator(
          color: KB.amber,
          onRefresh: _refresh,
          child: FutureBuilder<List<KBSession>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const _LoadingHistory();
              }
              final sessions = snap.data ?? const <KBSession>[];
              if (sessions.isEmpty) {
                return const _EmptyHistory();
              }
              final groups = _groupByDay(sessions);
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                    KB.s6, KB.s4, KB.s6, KB.s10),
                children: [
                  Text("HISTORY", style: KBText.overline()),
                  const SizedBox(height: KB.s2),
                  Text("Every session, kept", style: KBText.title()),
                  const SizedBox(height: KB.s3),
                  Text(
                    "Tap a session to see the chat, taps, and notes from that "
                    "conversation. Nothing leaves your family.",
                    style: KBText.body(color: KB.muted),
                  ),
                  const SizedBox(height: KB.s6),
                  for (final g in groups) ...[
                    Text(g.label, style: KBText.overline()),
                    const SizedBox(height: KB.s3),
                    Container(
                      decoration: BoxDecoration(
                        color: KB.surface,
                        borderRadius: BorderRadius.circular(KB.radiusCard),
                        border: Border.all(color: KB.hairline, width: 1),
                      ),
                      child: Column(
                        children: [
                          for (int i = 0; i < g.sessions.length; i++) ...[
                            _SessionRow(
                              session: g.sessions[i],
                              onTap: () => _openDetail(g.sessions[i]),
                            ),
                            if (i < g.sessions.length - 1)
                              Divider(
                                color: KB.hairline,
                                height: 1,
                                indent: KB.s5,
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: KB.s6),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _openDetail(KBSession s) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionDetailPage(session: s),
      ),
    );
  }
}

class _DayGroup {
  _DayGroup(this.label, this.sessions);
  final String label;
  final List<KBSession> sessions;
}

List<_DayGroup> _groupByDay(List<KBSession> sessions) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final weekAgo = today.subtract(const Duration(days: 7));

  final sorted = [...sessions]
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  final todayList = <KBSession>[];
  final yestList = <KBSession>[];
  final weekList = <KBSession>[];
  final earlierList = <KBSession>[];

  for (final s in sorted) {
    final d = DateTime(s.startedAt.year, s.startedAt.month, s.startedAt.day);
    if (d == today) {
      todayList.add(s);
    } else if (d == yesterday) {
      yestList.add(s);
    } else if (d.isAfter(weekAgo)) {
      weekList.add(s);
    } else {
      earlierList.add(s);
    }
  }

  return [
    if (todayList.isNotEmpty) _DayGroup("TODAY", todayList),
    if (yestList.isNotEmpty) _DayGroup("YESTERDAY", yestList),
    if (weekList.isNotEmpty) _DayGroup("THIS WEEK", weekList),
    if (earlierList.isNotEmpty) _DayGroup("EARLIER", earlierList),
  ];
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.onTap});
  final KBSession session;
  final VoidCallback onTap;

  String _timeLabel() {
    final t = session.startedAt;
    final hour = t.hour == 0
        ? 12
        : (t.hour > 12 ? t.hour - 12 : t.hour);
    final ampm = t.hour < 12 ? "AM" : "PM";
    final minute = t.minute.toString().padLeft(2, "0");
    return "$hour:$minute $ampm";
  }

  String _directionLabel() {
    return session.direction == KBRoleDirection.owner
        ? "${session.peerName} helped you"
        : "Helped ${session.peerName}";
  }

  String _durationLabel() {
    final d = session.duration;
    if (d == null) return "live";
    if (d.inMinutes < 1) return "${d.inSeconds}s";
    return "${d.inMinutes} min";
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KB.radiusCard),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: KB.s4, vertical: KB.s4),
          child: Row(
            children: [
              KBAvatar(
                initials: session.peerInitials,
                size: 44,
                tint: session.direction == KBRoleDirection.owner
                    ? KB.amberGlow
                    : KB.sage,
              ),
              const SizedBox(width: KB.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_directionLabel(), style: KBText.label()),
                    const SizedBox(height: 2),
                    Text(session.summary,
                        style: KBText.caption(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: KB.s3),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_timeLabel(), style: KBText.caption()),
                  const SizedBox(height: 2),
                  Text(_durationLabel(),
                      style: KBText.caption(color: KB.amber).copyWith(
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),
              const SizedBox(width: KB.s2),
              const Icon(Icons.chevron_right_rounded,
                  color: KB.muted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingHistory extends StatelessWidget {
  const _LoadingHistory();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(KB.s8),
        child: CircularProgressIndicator(color: KB.amber),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(KB.s8),
      children: [
        const SizedBox(height: KB.s10),
        Icon(Icons.history_rounded, size: 48, color: KB.muted.withOpacity(0.6)),
        const SizedBox(height: KB.s4),
        Text("No sessions yet",
            textAlign: TextAlign.center, style: KBText.heading()),
        const SizedBox(height: KB.s2),
        Text(
          "When you help or get help from someone, the session will appear here.",
          textAlign: TextAlign.center,
          style: KBText.body(color: KB.muted),
        ),
      ],
    );
  }
}
