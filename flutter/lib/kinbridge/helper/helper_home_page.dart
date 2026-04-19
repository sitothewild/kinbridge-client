import 'package:flutter/material.dart';
import '../theme/kb_tokens.dart';
import '../widgets/kb_avatar.dart';

/// Helper Home (complement to spec page 7).
///
/// Not in the spec PDF as a dedicated mockup — deduced from the History /
/// Session Detail flow: helper needs a quick "who can I help right now" view.
/// Phase V wires to Supabase `devices` table via the KinBridge API.
class HelperHomePage extends StatelessWidget {
  const HelperHomePage({super.key, this.displayName = "Sara"});

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
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("HELPER", style: KBText.overline()),
                        const SizedBox(height: KB.s2),
                        Text("Hi, $displayName 👋", style: KBText.title()),
                      ],
                    ),
                  ),
                  KBAvatar(
                    initials: displayName.substring(0, 1).toUpperCase(),
                    size: 52,
                    tint: KB.amber,
                  ),
                ],
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
                    const _FamilyMemberTile(
                        name: "Mom", device: "Pixel 8", online: true),
                    Divider(color: KB.hairline, height: KB.s5),
                    const _FamilyMemberTile(
                        name: "Dad", device: "Galaxy A54", online: false),
                  ],
                ),
              ),
              const SizedBox(height: KB.s8),
              Text("RECENT SESSIONS", style: KBText.overline()),
              const SizedBox(height: KB.s3),
              Container(
                padding: const EdgeInsets.all(KB.s5),
                decoration: BoxDecoration(
                  color: KB.surface,
                  borderRadius: BorderRadius.circular(KB.radiusCard),
                  border: Border.all(color: KB.hairline, width: 1),
                ),
                child: Column(
                  children: [
                    _RecentSessionRow(
                      initials: "M",
                      person: "Mom — Pixel 8",
                      summary: "Helped with Wi-Fi settings",
                      when: "10:42 AM",
                    ),
                    Divider(color: KB.hairline, height: KB.s5),
                    _RecentSessionRow(
                      initials: "J",
                      person: "James — Galaxy A54",
                      summary: "Showed how to send a photo",
                      when: "8:05 AM",
                    ),
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

class _FamilyMemberTile extends StatelessWidget {
  const _FamilyMemberTile({
    required this.name,
    required this.device,
    required this.online,
  });
  final String name;
  final String device;
  final bool online;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        KBAvatar(
          initials: name.substring(0, 1),
          size: 48,
          online: online,
          tint: KB.amber,
        ),
        const SizedBox(width: KB.s4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: KBText.label()),
              Text(device, style: KBText.caption()),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: KB.s4, vertical: KB.s2),
          decoration: BoxDecoration(
            color: online ? KB.amber : KB.hairline,
            borderRadius: BorderRadius.circular(KB.radiusPill),
          ),
          child: Text(
            online ? "Help now" : "Notify",
            style: KBText.label(color: online ? KB.surface : KB.muted),
          ),
        ),
      ],
    );
  }
}

class _RecentSessionRow extends StatelessWidget {
  const _RecentSessionRow({
    required this.initials,
    required this.person,
    required this.summary,
    required this.when,
  });
  final String initials;
  final String person;
  final String summary;
  final String when;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        KBAvatar(initials: initials, size: 40, tint: KB.amberGlow),
        const SizedBox(width: KB.s4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(person, style: KBText.label()),
              Text(summary, style: KBText.caption()),
            ],
          ),
        ),
        Text(when, style: KBText.caption()),
      ],
    );
  }
}
