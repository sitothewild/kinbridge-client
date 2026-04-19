import 'package:flutter/material.dart';
import '../theme/kb_tokens.dart';

/// Spec 01 — Welcome. First-launch hero.
class WelcomePage extends StatelessWidget {
  const WelcomePage({
    super.key,
    required this.onGetStarted,
    required this.onSignIn,
    required this.onSkip,
  });

  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KB.parchment,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding:
                  const EdgeInsets.fromLTRB(KB.s6, KB.s3, KB.s6, KB.s6),
              child: ConstrainedBox(
                // Lets us still distribute with Spacer-ish SizedBoxes while
                // gracefully scrolling on ultra-small screens.
                constraints:
                    BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: onSkip,
                          child: Text("Skip",
                              style: KBText.label(color: KB.muted)),
                        ),
                      ),
                      const SizedBox(height: KB.s3),
                      _HeroMark(),
                      const SizedBox(height: KB.s4),
                      const _DotRow(active: 0, total: 3),
                      const SizedBox(height: KB.s5),
                      Text("Help is just a tap away.",
                          textAlign: TextAlign.center,
                          style: KBText.title()),
                      const SizedBox(height: KB.s3),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: KB.s3),
                        child: Text(
                          "KinBridge Support connects you with the people who already help you with your phone — gently, on your terms.",
                          textAlign: TextAlign.center,
                          style: KBText.body(color: KB.muted),
                        ),
                      ),
                      const SizedBox(height: KB.s5),
                      _FeatureRow(
                          icon: Icons.verified_user_outlined,
                          label: "End-to-end encrypted"),
                      const SizedBox(height: KB.s2),
                      _FeatureRow(
                          icon: Icons.check_circle_outline,
                          label: "Always asks before sharing"),
                      const Spacer(),
                      const SizedBox(height: KB.s5),
                      _PrimaryButton(
                          label: "Get started", onTap: onGetStarted),
                      const SizedBox(height: KB.s2),
                      TextButton(
                        onPressed: onSignIn,
                        child: Text(
                          "I already have an account · Sign in",
                          style: KBText.label(color: KB.amber),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HeroMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 128,
      height: 128,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [KB.amber, KB.amberGlow.withOpacity(0.0)],
          stops: const [0.55, 1.0],
        ),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.favorite, color: KB.surface, size: 44),
    );
  }
}

class _DotRow extends StatelessWidget {
  const _DotRow({required this.active, required this.total});
  final int active;
  final int total;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < total; i++)
          Container(
            width: i == active ? 24 : 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: i == active ? KB.amber : KB.hairline,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: KB.sage, size: 20),
        const SizedBox(width: KB.s2),
        Text(label, style: KBText.body(color: KB.deepInk)),
      ],
    );
  }
}

/// Full-width amber-gradient pill, used throughout onboarding + Owner Home.
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
