import 'package:flutter/material.dart';
import '../theme/kb_tokens.dart';
import '../widgets/kb_avatar.dart';

/// Owner Home (spec page 7).
///
/// "Mom's home screen — ask for help in one tap."
///
/// This screen is intentionally low-density. The whole job of the Owner Home
/// is to make the "Ask for help" affordance obvious. Everything else is
/// secondary.
///
/// Data today is placeholder (see [_placeholderHelpers], [_placeholderActivity]).
/// Phase V wires to Supabase via the KinBridge API.
class OwnerHomePage extends StatelessWidget {
  const OwnerHomePage({super.key, this.displayName = "Mom"});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: KB.parchment,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(KB.s6, KB.s4, KB.s6, KB.s10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Greeting(displayName: displayName),
              const SizedBox(height: KB.s6),
              const _NeedAHandCard(),
              const SizedBox(height: KB.s8),
              _SectionEyebrow(label: "RECENT HELPERS"),
              const SizedBox(height: KB.s4),
              const _RecentHelpersRow(),
              const SizedBox(height: KB.s8),
              _SectionEyebrow(label: "ACTIVITY"),
              const SizedBox(height: KB.s3),
              const _ActivityList(),
            ],
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
          // TODO(phase V): POST /api/help-requests via KinBridgeApi.
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
                padding:
                    const EdgeInsets.symmetric(horizontal: KB.s4, vertical: KB.s3),
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

class _SectionEyebrow extends StatelessWidget {
  const _SectionEyebrow({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Text(label, style: KBText.overline());
  }
}

class _Helper {
  const _Helper(this.name, this.initials, {required this.online, this.subtitle});
  final String name;
  final String initials;
  final bool online;
  final String? subtitle;
}

// Placeholder data — replaced in Phase V via Supabase `device_pairings`
// joined with `profiles`.
const List<_Helper> _placeholderHelpers = [
  _Helper("Sara", "S", online: true, subtitle: "online"),
  _Helper("James", "J", online: true, subtitle: "online"),
  _Helper("Priya", "P", online: false, subtitle: "2h ago"),
];

class _RecentHelpersRow extends StatelessWidget {
  const _RecentHelpersRow();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final h in _placeholderHelpers)
            Padding(
              padding: const EdgeInsets.only(right: KB.s5),
              child: _HelperChip(helper: h),
            ),
        ],
      ),
    );
  }
}

class _HelperChip extends StatelessWidget {
  const _HelperChip({required this.helper});
  final _Helper helper;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: Column(
        children: [
          KBAvatar(
            initials: helper.initials,
            size: 64,
            online: helper.online,
            tint: KB.amber,
          ),
          const SizedBox(height: KB.s2),
          Text(helper.name,
              style: KBText.label(), textAlign: TextAlign.center),
          if (helper.subtitle != null)
            Text(helper.subtitle!,
                style: KBText.caption(color: helper.online ? KB.sage : KB.muted),
                textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ActivityEntry {
  const _ActivityEntry(this.icon, this.label, this.when);
  final IconData icon;
  final String label;
  final String when;
}

// Placeholder — Phase V reads from Supabase `session_events`.
const List<_ActivityEntry> _placeholderActivity = [
  _ActivityEntry(
      Icons.check_circle_outline, "Sara helped you set up Wi-Fi", "2h ago"),
  _ActivityEntry(
      Icons.handshake_outlined, "Pairing approved with James", "yesterday"),
  _ActivityEntry(
      Icons.notifications_active_outlined, "Help requested", "3 days ago"),
];

class _ActivityList extends StatelessWidget {
  const _ActivityList();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KB.surface,
        borderRadius: BorderRadius.circular(KB.radiusCard),
        border: Border.all(color: KB.hairline, width: 1),
      ),
      child: Column(
        children: [
          for (int i = 0; i < _placeholderActivity.length; i++) ...[
            _ActivityRow(entry: _placeholderActivity[i]),
            if (i < _placeholderActivity.length - 1)
              Divider(height: 1, color: KB.hairline, indent: KB.s5),
          ],
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});
  final _ActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: KB.s4, vertical: KB.s4),
      child: Row(
        children: [
          Icon(entry.icon, size: 20, color: KB.amber),
          const SizedBox(width: KB.s3),
          Expanded(
              child: Text(entry.label, style: KBText.body(color: KB.deepInk))),
          Text(entry.when, style: KBText.caption()),
        ],
      ),
    );
  }
}
