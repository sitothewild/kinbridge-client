import 'package:flutter/material.dart';
import '../shell/kb_shell.dart' show KBRole;
import '../theme/kb_tokens.dart';

/// Not in spec as a dedicated mockup, but required to branch owner vs helper
/// first-launch flows. Two-card picker.
class RolePickerPage extends StatelessWidget {
  const RolePickerPage({super.key, required this.onPick, required this.onBack});

  final void Function(KBRole) onPick;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KB.parchment,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(KB.s6, KB.s3, KB.s6, KB.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back, color: KB.deepInk),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: KB.s3),
              Text("How will you use\nKinBridge?", style: KBText.title()),
              const SizedBox(height: KB.s3),
              Text(
                "You can change this later from Settings.",
                style: KBText.body(color: KB.muted),
              ),
              const SizedBox(height: KB.s8),
              _RoleCard(
                role: KBRole.owner,
                emoji: "🌿",
                title: "I need help",
                subtitle:
                    "I want a trusted family member to assist me with my phone.",
                tint: KB.sage,
                onTap: () => onPick(KBRole.owner),
              ),
              const SizedBox(height: KB.s4),
              _RoleCard(
                role: KBRole.helper,
                emoji: "🤝",
                title: "I'm helping someone",
                subtitle:
                    "I want to assist a family member with their phone.",
                tint: KB.amber,
                onTap: () => onPick(KBRole.helper),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.tint,
    required this.onTap,
  });

  final KBRole role;
  final String emoji;
  final String title;
  final String subtitle;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KB.surface,
      borderRadius: BorderRadius.circular(KB.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KB.radiusCard),
        child: Container(
          padding: const EdgeInsets.all(KB.s5),
          decoration: BoxDecoration(
            border: Border.all(color: KB.hairline, width: 1),
            borderRadius: BorderRadius.circular(KB.radiusCard),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration:
                    BoxDecoration(color: tint, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: KB.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: KBText.heading()),
                    const SizedBox(height: KB.s1),
                    Text(subtitle, style: KBText.body(color: KB.muted)),
                  ],
                ),
              ),
              const SizedBox(width: KB.s2),
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: KB.muted, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
