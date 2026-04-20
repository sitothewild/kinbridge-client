import 'package:flutter/material.dart';
import '../theme/kb_tokens.dart';
import '../widgets/kb_avatar.dart';
import '../data/kb_models.dart';
import '../data/kb_repository.dart';

/// Session Detail (spec page 12).
///
/// Layout:
///   • Hero card: avatar + peer name + direction + date/duration
///   • Tab bar: Timeline · Chat · Notes
///   • Export action pinned to AppBar
///
/// Data comes from [KBRepository.instance]. Today that's the fake repo;
/// Phase V-b swaps to the http repo.
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
    _tab = TabController(length: 3, vsync: this);
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

  void _export() {
    // TODO(phase V-b): when http repo is wired, call
    // GET /api/sessions/:id/export → returns JSON + attach via share_plus.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: KB.deepInk,
        behavior: SnackBarBehavior.floating,
        content: Text(
          "Export ready soon — we'll email you a copy.",
          style: KBText.body(color: KB.parchment),
        ),
      ),
    );
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
        actions: [
          IconButton(
            tooltip: "Export",
            onPressed: _export,
            icon: const Icon(Icons.ios_share_rounded, color: KB.deepInk),
          ),
        ],
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
                Tab(text: "Notes"),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _TimelineTab(future: _events),
                _ChatTab(future: _chat),
                _NotesTab(future: _events),
              ],
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

class _NotesTab extends StatelessWidget {
  const _NotesTab({required this.future});
  final Future<List<KBSessionEvent>> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<KBSessionEvent>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: KB.amber));
        }
        final notes = (snap.data ?? const <KBSessionEvent>[])
            .where((e) => e.type == KBEventKind.note)
            .toList();
        if (notes.isEmpty) {
          return const _EmptyTab(
            icon: Icons.sticky_note_2_outlined,
            title: "No notes",
            subtitle: "Summaries of what was fixed appear here.",
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(KB.s6, KB.s5, KB.s6, KB.s10),
          itemCount: notes.length,
          itemBuilder: (ctx, i) {
            final n = notes[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: KB.s4),
              child: Container(
                padding: const EdgeInsets.all(KB.s5),
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
                        Icon(n.icon, size: 16, color: KB.amber),
                        const SizedBox(width: KB.s2),
                        Expanded(
                          child: Text(n.label, style: KBText.label()),
                        ),
                      ],
                    ),
                    if (n.detail != null) ...[
                      const SizedBox(height: KB.s2),
                      Text(n.detail!, style: KBText.body(color: KB.muted)),
                    ],
                  ],
                ),
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
