import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/kb_tokens.dart';
import '../widgets/kb_avatar.dart';
import '../data/kb_models.dart';
import '../data/kb_repository.dart';

/// Session Detail (spec page 12).
///
/// Layout:
///   • Hero card: avatar + peer name + direction + date/duration
///   • Tab bar: Timeline · Chat · Taps · Files (matches spec)
///   • Export button pinned to bottom — copies a full text report
///     (metadata + timeline + chat) to the clipboard so the user can
///     paste it anywhere (email, Notes, doctor's message, etc.)
class SessionDetailPage extends StatefulWidget {
  const SessionDetailPage({super.key, required this.session});
  final KBSession session;

  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late Future<List<KBSessionEvent>> _events;
  late Future<List<KBChatMessage>> _chat;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _events = KBRepository.instance.listEvents(widget.session.id);
    _chat = KBRepository.instance.listChat(widget.session.id);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  String _dateLabel(DateTime dt) {
    const months = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ];
    final hour12 = dt.hour == 0
        ? 12
        : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final ampm = dt.hour < 12 ? "AM" : "PM";
    return "${months[dt.month - 1]} ${dt.day} · $hour12:${dt.minute.toString().padLeft(2, '0')} $ampm";
  }

  String _durationLabel(Duration? d) {
    if (d == null) return "in progress";
    if (d.inMinutes < 1) return "${d.inSeconds} seconds";
    return "${d.inMinutes} min ${d.inSeconds % 60}s";
  }

  Future<void> _export() async {
    try {
      final events = await _events;
      final chat = await _chat;
      final report = _buildReport(widget.session, events, chat);
      await Clipboard.setData(ClipboardData(text: report));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: KB.sage,
          behavior: SnackBarBehavior.floating,
          content: Text(
            "Session report copied — paste anywhere.",
            style: KBText.body(color: KB.surface),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            "Couldn't build the report. Try again once the session loads.",
            style: KBText.body(),
          ),
        ),
      );
    }
  }

  String _buildReport(KBSession s, List<KBSessionEvent> events,
      List<KBChatMessage> chat) {
    final buf = StringBuffer();
    buf.writeln('KinBridge — Session Report');
    buf.writeln('=' * 40);
    buf.writeln();
    buf.writeln('Session: ${s.summary}');
    buf.writeln('With:    ${s.peerName} (${s.peerDevice})');
    buf.writeln('Started: ${_dateLabel(s.startedAt)}');
    buf.writeln('Length:  ${_durationLabel(s.duration)}');
    buf.writeln();
    buf.writeln('Timeline');
    buf.writeln('-' * 40);
    if (events.isEmpty) {
      buf.writeln('(no events)');
    } else {
      for (final e in events) {
        final t = _shortTime(e.createdAt);
        final detail = e.detail != null && e.detail!.isNotEmpty
            ? '  — ${e.detail}'
            : '';
        buf.writeln('$t  ${e.label}$detail');
      }
    }
    buf.writeln();
    buf.writeln('Chat');
    buf.writeln('-' * 40);
    if (chat.isEmpty) {
      buf.writeln('(no messages)');
    } else {
      for (final m in chat) {
        final t = _shortTime(m.at);
        final who = m.fromSelf ? 'You' : s.peerName;
        buf.writeln('$t  $who: ${m.text}');
      }
    }
    buf.writeln();
    buf.writeln('— exported ${_dateLabel(DateTime.now())}');
    return buf.toString();
  }

  String _shortTime(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final directionLabel = s.direction == KBRoleDirection.owner
        ? "${s.peerName} helped you"
        : "Helped ${s.peerName}";
    final tintColor =
        s.direction == KBRoleDirection.owner ? KB.amberGlow : KB.sage;

    return Scaffold(
      backgroundColor: KB.parchment,
      appBar: AppBar(
        backgroundColor: KB.parchment,
        surfaceTintColor: KB.parchment,
        elevation: 0,
        iconTheme: const IconThemeData(color: KB.deepInk),
        title: Text("Session", style: KBText.heading()),
        // Export lives as the primary pill pinned to the bottom of the
        // page instead of a compact icon button up top — matches spec
        // p12, and users can't miss it.
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(KB.s6, 0, KB.s6, KB.s4),
            child: Container(
              padding: const EdgeInsets.all(KB.s5),
              decoration: BoxDecoration(
                color: KB.surface,
                borderRadius: BorderRadius.circular(KB.radiusCard),
                border: Border.all(color: KB.hairline, width: 1),
              ),
              child: Row(
                children: [
                  KBAvatar(
                    initials: s.peerInitials,
                    size: 56,
                    tint: tintColor,
                  ),
                  const SizedBox(width: KB.s4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(directionLabel, style: KBText.heading()),
                        const SizedBox(height: KB.s1),
                        Text(s.summary,
                            style: KBText.body(color: KB.muted)),
                        const SizedBox(height: KB.s2),
                        Row(
                          children: [
                            const Icon(Icons.schedule_rounded,
                                size: 14, color: KB.muted),
                            const SizedBox(width: 4),
                            Text(_dateLabel(s.startedAt),
                                style: KBText.caption()),
                            const SizedBox(width: KB.s3),
                            const Icon(Icons.timer_outlined,
                                size: 14, color: KB.muted),
                            const SizedBox(width: 4),
                            Text(_durationLabel(s.duration),
                                style: KBText.caption()),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: KB.s6),
            decoration: BoxDecoration(
              color: KB.surface,
              borderRadius: BorderRadius.circular(KB.radiusPill),
              border: Border.all(color: KB.hairline, width: 1),
            ),
            child: TabBar(
              controller: _tab,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: KB.amber,
                borderRadius: BorderRadius.circular(KB.radiusPill),
              ),
              indicatorPadding: const EdgeInsets.all(3),
              labelColor: KB.surface,
              unselectedLabelColor: KB.muted,
              labelStyle: KBText.label(color: KB.surface),
              unselectedLabelStyle: KBText.label(color: KB.muted),
              tabs: const [
                Tab(text: "Timeline"),
                Tab(text: "Chat"),
                Tab(text: "Taps"),
                Tab(text: "Files"),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _TimelineTab(future: _events),
                _ChatTab(future: _chat),
                _FilteredEventsTab(
                  future: _events,
                  keep: const {
                    KBEventKind.tap,
                    KBEventKind.scroll,
                    KBEventKind.keyboard,
                  },
                  emptyIcon: Icons.touch_app_outlined,
                  emptyTitle: "No taps yet",
                  emptySubtitle:
                      "Guided taps and scrolls you send to this device show up here during a session.",
                ),
                _FilteredEventsTab(
                  future: _events,
                  keep: const {
                    KBEventKind.fileSent,
                    KBEventKind.screenshot,
                  },
                  emptyIcon: Icons.folder_open_rounded,
                  emptyTitle: "No files yet",
                  emptySubtitle:
                      "Screenshots and files you share during a session show up here.",
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(KB.s6, 0, KB.s6, KB.s4),
            child: SizedBox(
              width: double.infinity,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(KB.radiusPill),
                  onTap: _export,
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: KB.amberGradient,
                      borderRadius: BorderRadius.circular(KB.radiusPill),
                    ),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: KB.s4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.ios_share_rounded,
                              color: KB.surface, size: 18),
                          const SizedBox(width: KB.s2),
                          Text("Export session report",
                              style: KBText.label(color: KB.surface)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineTab extends StatelessWidget {
  const _TimelineTab({required this.future});
  final Future<List<KBSessionEvent>> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<KBSessionEvent>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: KB.amber));
        }
        final events = snap.data ?? const <KBSessionEvent>[];
        if (events.isEmpty) {
          return const _EmptyTab(
            icon: Icons.timeline_rounded,
            title: "No events yet",
            subtitle: "Taps, scrolls, and screenshots appear here.",
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(KB.s6, KB.s5, KB.s6, KB.s10),
          itemCount: events.length,
          itemBuilder: (ctx, i) => _TimelineRow(
            event: events[i],
            isFirst: i == 0,
            isLast: i == events.length - 1,
          ),
        );
      },
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.event,
    required this.isFirst,
    required this.isLast,
  });
  final KBSessionEvent event;
  final bool isFirst;
  final bool isLast;

  String _time(DateTime dt) {
    return "${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 2,
                height: KB.s4,
                color: isFirst ? Colors.transparent : KB.hairline,
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: KB.surface,
                  border: Border.all(color: KB.hairline, width: 1),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(event.icon, size: 16, color: KB.amber),
              ),
              Expanded(
                child: Container(
                  width: 2,
                  color: isLast ? Colors.transparent : KB.hairline,
                ),
              ),
            ],
          ),
          const SizedBox(width: KB.s4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: KB.s5, top: KB.s2),
              child: Container(
                padding: const EdgeInsets.all(KB.s4),
                decoration: BoxDecoration(
                  color: KB.surface,
                  borderRadius: BorderRadius.circular(KB.radiusCard),
                  border: Border.all(color: KB.hairline, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(event.label, style: KBText.label()),
                        ),
                        Text(_time(event.createdAt),
                            style: KBText.caption().copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            )),
                      ],
                    ),
                    if (event.detail != null) ...[
                      const SizedBox(height: KB.s1),
                      Text(event.detail!, style: KBText.caption()),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatTab extends StatelessWidget {
  const _ChatTab({required this.future});
  final Future<List<KBChatMessage>> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<KBChatMessage>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: KB.amber));
        }
        final messages = snap.data ?? const <KBChatMessage>[];
        if (messages.isEmpty) {
          return const _EmptyTab(
            icon: Icons.chat_bubble_outline_rounded,
            title: "No chat messages",
            subtitle: "Messages sent during the session appear here.",
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(KB.s6, KB.s5, KB.s6, KB.s10),
          itemCount: messages.length,
          itemBuilder: (ctx, i) => _ChatBubble(message: messages[i]),
        );
      },
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});
  final KBChatMessage message;

  @override
  Widget build(BuildContext context) {
    final self = message.fromSelf;
    return Padding(
      padding: const EdgeInsets.only(bottom: KB.s3),
      child: Row(
        mainAxisAlignment:
            self ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: KB.s4, vertical: KB.s3),
              decoration: BoxDecoration(
                color: self ? KB.amber : KB.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(KB.radiusCard),
                  topRight: const Radius.circular(KB.radiusCard),
                  bottomLeft: Radius.circular(self ? KB.radiusCard : 4),
                  bottomRight: Radius.circular(self ? 4 : KB.radiusCard),
                ),
                border: self
                    ? null
                    : Border.all(color: KB.hairline, width: 1),
              ),
              child: Text(
                message.text,
                style: KBText.body(
                  color: self ? KB.surface : KB.deepInk,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Filtered-event tab (Taps, Files). Same ListView shape as Timeline
/// but scoped to a subset of [KBEventKind] values and with a distinct
/// empty state. Keeps the Timeline tab as the full firehose and lets
/// these surfaces be scan-friendly for their narrower question.
class _FilteredEventsTab extends StatelessWidget {
  const _FilteredEventsTab({
    required this.future,
    required this.keep,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptySubtitle,
  });
  final Future<List<KBSessionEvent>> future;
  final Set<KBEventKind> keep;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptySubtitle;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<KBSessionEvent>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
              child: CircularProgressIndicator(color: KB.amber));
        }
        final rows = (snap.data ?? const <KBSessionEvent>[])
            .where((e) => keep.contains(e.type))
            .toList();
        if (rows.isEmpty) {
          return _EmptyTab(
            icon: emptyIcon,
            title: emptyTitle,
            subtitle: emptySubtitle,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(KB.s6, KB.s5, KB.s6, KB.s10),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: KB.s3),
          itemBuilder: (ctx, i) {
            final e = rows[i];
            final hh = e.createdAt.hour.toString().padLeft(2, '0');
            final mm = e.createdAt.minute.toString().padLeft(2, '0');
            return Container(
              padding: const EdgeInsets.all(KB.s4),
              decoration: BoxDecoration(
                color: KB.surface,
                borderRadius: BorderRadius.circular(KB.radiusField),
                border: Border.all(color: KB.hairline, width: 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: KB.amber.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(e.icon, size: 18, color: KB.amber),
                  ),
                  const SizedBox(width: KB.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.label, style: KBText.label()),
                        if (e.detail != null && e.detail!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(e.detail!,
                              style: KBText.caption(color: KB.muted)),
                        ],
                      ],
                    ),
                  ),
                  Text("$hh:$mm",
                      style: KBText.caption(color: KB.muted)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KB.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: KB.muted.withOpacity(0.6)),
            const SizedBox(height: KB.s3),
            Text(title, style: KBText.heading()),
            const SizedBox(height: KB.s2),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: KBText.body(color: KB.muted)),
          ],
        ),
      ),
    );
  }
}
