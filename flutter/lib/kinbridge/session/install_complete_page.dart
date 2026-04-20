import 'package:flutter/material.dart';

import '../data/kb_server_fn.dart';
import '../theme/kb_tokens.dart';
import '../widgets/kb_avatar.dart';

/// Shown after a successful [KBServerFn.redeemInstallToken]. Confirms
/// the device is now registered with the owner's account and points to
/// what happens next (wait for a helper to pair, or hand out an invite
/// link). See `android-snippets/INSTALL_TOKEN.md`.
class InstallCompletePage extends StatelessWidget {
  const InstallCompletePage({super.key, required this.device});

  final KBDeviceRow device;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KB.parchment,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(KB.s6, KB.s3, KB.s6, KB.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: KB.s4),
              _HeroMark(),
              const SizedBox(height: KB.s6),
              Text("This phone is ready.",
                  textAlign: TextAlign.center, style: KBText.title()),
              const SizedBox(height: KB.s3),
              Text(
                "KinBridge Support has been set up on this device. The person who sent you the install link can now invite helpers who will be able to see the screen when you need help.",
                textAlign: TextAlign.center,
                style: KBText.body(color: KB.muted),
              ),
              const SizedBox(height: KB.s6),
              Container(
                padding: const EdgeInsets.all(KB.s5),
                decoration: BoxDecoration(
                  color: KB.surface,
                  borderRadius: BorderRadius.circular(KB.radiusCard),
                  border: Border.all(color: KB.hairline, width: 1),
                ),
                child: Row(
                  children: [
                    KBAvatar(
                      initials: device.name.isNotEmpty
                          ? device.name.substring(0, 1).toUpperCase()
                          : '?',
                      size: 48,
                      tint: KB.amber,
                    ),
                    const SizedBox(width: KB.s4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("REGISTERED AS", style: KBText.overline()),
                          const SizedBox(height: 2),
                          Text(device.name, style: KBText.heading()),
                          const SizedBox(height: 2),
                          Text(device.platform,
                              style: KBText.caption(color: KB.muted)),
                        ],
                      ),
                    ),
                    const Icon(Icons.check_circle_rounded,
                        color: KB.sage, size: 22),
                  ],
                ),
              ),
              const SizedBox(height: KB.s5),
              _NextStep(
                icon: Icons.mail_outline_rounded,
                title: "Wait for an invite",
                body:
                    "If the person who set this up sends you an invite link from the dashboard, tap it to approve them as a helper.",
              ),
              const SizedBox(height: KB.s3),
              _NextStep(
                icon: Icons.pin_rounded,
                title: "Or use a QuickConnect code",
                body:
                    "Ask the person who set this up to generate a 6-digit code on their dashboard when you need immediate help.",
              ),
              const Spacer(),
              _PrimaryButton(
                label: "Got it",
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [KB.sage, KB.sage.withOpacity(0.0)],
            stops: const [0.55, 1.0],
          ),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.check_rounded, color: KB.surface, size: 40),
      ),
    );
  }
}

class _NextStep extends StatelessWidget {
  const _NextStep({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: KB.amber, size: 20),
        const SizedBox(width: KB.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: KBText.label()),
              const SizedBox(height: 2),
              Text(body, style: KBText.body(color: KB.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});
  final String label;
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
              gradient: KB.amberGradient,
              borderRadius: BorderRadius.circular(KB.radiusPill),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: KB.s4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: KBText.label(color: KB.surface)),
                  const SizedBox(width: KB.s2),
                  const Icon(Icons.arrow_forward_rounded,
                      color: KB.surface, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
