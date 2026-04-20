import 'package:flutter/material.dart';
import '../theme/kb_tokens.dart';
import '../widgets/kb_avatar.dart';
import '../data/kb_models.dart';
import '../data/kb_repository.dart';
import '../history/session_detail_page.dart';

/// Owner Home (spec page 7).
///
/// "Mom's home screen — ask for help in one tap."
///
/// The whole job of this screen is making "Ask for help" obvious. Everything
/// else is secondary. Data comes from [KBRepository.instance] (fake today,
/// real once Phase V-b lands).
class OwnerHomePage extends StatefulWidget {
  const OwnerHomePage({super.key, this.displayName = "Mom"});

  final String displayName;

  @override
  State<OwnerHomePage> createState() => _OwnerHomePageState();
}

class _OwnerHomePageState extends State<OwnerHomePage> {
  late Future<List<KBHelper>> _helpers;
  late Future<List<KBSession>> _sessions;

  @override
  void initState() {
    super.initState();
    _helpers = KBRepository.instance.listHelpers();
    _sessions = KBRepository.instance.listSessions(limit: 4);
  }

  Future<void> _refresh() async {
    final h = KBRepository.instance.listHelpers();
    final s = KBRepository.instance.listSessions(limit: 4);
    setState(() {
      _helpers = h;
      _sessions = s;
    });
    await Future.wait([h, s]);
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
                _Greeting(displayName: widget.displayName),
                const SizedBox(height: KB.s6),
                const _NeedAHandCard(),
                const SizedBox(height: KB.s8),
                Text("RECENT HELPERS", style: KBText.overline()),
                const SizedBox(height: KB.s4),
                _RecentHelpersRow(future: _helpers),
                const SizedBox(height: KB.s8),
                Text("ACTIVITY", style: KBText.overline()),
                const SizedBox(height: KB.s3),
                _ActivityList(future: _sessions),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.displayName});
  final String displayName;

  String _partOfDay() {
    final h = DateTime.now().hour;
    if (h < 12) return "GOOD MORNING";
    if (h < 18) return "GOOD AFTERNOON";
    return "GOOD EVENING";
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_partOfDay(), style: KBText.overline()),
              const SizedBox(height: KB.s2),
              Text("Hi, $displayName 🦋", style: KBText.title()),
            ],
          ),
        ),
        KBAvatar(
          initials: displayName.isNotEmpty
              ? displayName.substring(0, 1).toUpperCase()
              : "?",
          size: 52,
          tint: KB.sage,
        ),
      ],
    );
  }
}

class _NeedAHandCard extends StatelessWidget {
  const _NeedAHandCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(KB.radiusCard),
        onTap: () {
          // TODO(phase V-b): POST /api/help-requests via HttpKBRepository.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: KB.deepInk,
              content: Text(
                "Help request sent to your helpers.",
                style: KBText.body(color: KB.parchment),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(KB.s5),
          decoration: BoxDecoration(
            gradient: KB.amberGradient,
            borderRadius: BorderRadius.circular(KB.radiusCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: KB.surface.withOpacity(0.25),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Text("👋", style: TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: KB.s4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Need a hand?",
                            style: KBText.heading(color: KB.surface)),
                        const SizedBox(height: KB.s1),
                        Text(
                          "Tap to ask Sara for help — she'll see it instantly.",
                          style: KBText.body(
                              color: KB.surface.withOpacity(0.9)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: KB.s4),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: KB.s4, vertical: KB.s3),
                decoration: BoxDecoration(
                  color: KB.surface,
                  borderRadius: BorderRadius.circular(KB.radiusPill),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Ask for help",
                        style: KBText.label(color: KB.deepInk)),
                    const Icon(Icons.arrow_forward_rounded,
                        color: KB.deepInk, size: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentHelpersRow extends StatelessWidget {
  const _RecentHelpersRow({required this.future});
  final Future<List<KBHelper>> future;

  String _subtitle(KBHelper h) {
    if (h.online) return "online";
    final last = h.lastSeen;
    if (last == null) return "offline";
    final diff = DateTime.now().difference(last);
    if (diff.inMinutes < 1) return "just now";
    if (diff.inHours < 1) return "${diff.inMinutes}m ago";
    if (diff.inDays < 1) return "${diff.inHours}h ago";
    return "${diff.inDays}d ago";
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<KBHelper>>(
      future: future,
      builder: (context, snap) {
        final helpers = snap.data ?? const <KBHelper>[];
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 104,
            child: Center(
              child: CircularProgressIndicator(color: KB.amber),
            ),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final h in helpers)
                Padding(
                  padding: const EdgeInsets.only(right: KB.s5),
                  child: SizedBox(
                    width: 96,
                    child: Column(
                      children: [
                        KBAvatar(
                          initials: h.initials,
                          size: 64,
                          online: h.online,
                          tint: KB.amber,
                        ),
                        const SizedBox(height: KB.s2),
                        Text(h.name,
                            style: KBText.label(),
                            textAlign: TextAlign.center),
                        Text(
                          _subtitle(h),
                          style: KBText.caption(
                              color: h.online ? KB.sage : KB.muted),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({required this.future});
  final Future<List<KBSession>> future;

  String _when(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return "just now";
    if (diff.inHours < 1) return "${diff.inMinutes}m ago";
    if (diff.inDays < 1) return "${diff.inHours}h ago";
    if (diff.inDays == 1) return "yesterday";
    if (diff.inDays < 7) return "${diff.inDays}d ago";
    return "${(diff.inDays / 7).floor()}w ago";
  }

  String _label(KBSession s) {
    if (s.direction == KBRoleDirection.owner) {
      return "${s.peerName} ${s.summary.toLowerCase().startsWith('helped')
          ? s.summary.toLowerCase()
          : 'helped you: ${s.summary.toLowerCase()}'}";
    }
    return s.summary;
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
              "Nothing here yet — when someone helps you, it shows up here.",
              style: KBText.body(color: KB.muted),
            ),
          );
        }
        return Container(
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: KB.s4, vertical: KB.s4),
                      child: Row(
                        children: [
                          Icon(
                            sessions[i].direction == KBRoleDirection.owner
                                ? Icons.handshake_outlined
                                : Icons.volunteer_activism_outlined,
                            size: 20,
                            color: KB.amber,
                          ),
                          const SizedBox(width: KB.s3),
                          Expanded(
                            child: Text(
                              _label(sessions[i]),
                              style: KBText.body(color: KB.deepInk),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                  Divider(height: 1, color: KB.hairline, indent: KB.s5),
              ],
            ],
          ),
        );
      },
    );
  }
}
