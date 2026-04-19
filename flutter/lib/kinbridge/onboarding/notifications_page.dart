import 'package:flutter/material.dart';
import '../theme/kb_tokens.dart';

/// Spec 03 — Notifications.
/// Three in-app preference toggles. The system permission prompt (Android 13+
/// POST_NOTIFICATIONS) is asked on "Allow notifications" via the RustDesk
/// permission flow we already have in MainService.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    required this.onBack,
    required this.onAllow,
    required this.onSkip,
  });

  final VoidCallback onBack;
  final void Function(NotificationPrefs prefs) onAllow;
  final VoidCallback onSkip;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class NotificationPrefs {
  const NotificationPrefs({
    required this.helpRequests,
    required this.pairings,
    required this.weeklyRecap,
  });
  final bool helpRequests;
  final bool pairings;
  final bool weeklyRecap;
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _help = true;
  bool _pair = true;
  bool _recap = false;

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
                constraints:
                    BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
              Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back, color: KB.deepInk),
                  ),
                  Expanded(
                    child: Text("Stay in the loop",
                        textAlign: TextAlign.center, style: KBText.label()),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: KB.s4),
              Center(child: _DotRow(active: 2, total: 3)),
              const SizedBox(height: KB.s6),
              Center(
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        KB.amber.withOpacity(0.25),
                        KB.amber.withOpacity(0.0)
                      ],
                      stops: const [0.55, 1.0],
                    ),
                  ),
                  alignment: Alignment.center,
                  child:
                      const Icon(Icons.notifications_active_outlined, size: 36, color: KB.amber),
                ),
              ),
              const SizedBox(height: KB.s5),
              Text("How should we reach you?",
                  textAlign: TextAlign.center, style: KBText.title()),
              const SizedBox(height: KB.s3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KB.s4),
                child: Text(
                  "Pick the moments that matter. You can change these anytime in Settings.",
                  textAlign: TextAlign.center,
                  style: KBText.body(color: KB.muted),
                ),
              ),
              const SizedBox(height: KB.s6),
              _PrefCard(
                icon: Icons.handshake_outlined,
                title: "When someone needs help",
                subtitle:
                    "Instant alerts when Mom or Dad taps Ask for help.",
                value: _help,
                onChanged: (v) => setState(() => _help = v),
              ),
              const SizedBox(height: KB.s3),
              _PrefCard(
                icon: Icons.key_outlined,
                title: "Pairing requests & approvals",
                subtitle: "So you never miss a new helper joining.",
                value: _pair,
                onChanged: (v) => setState(() => _pair = v),
              ),
              const SizedBox(height: KB.s3),
              _PrefCard(
                icon: Icons.calendar_month_outlined,
                title: "Weekly recap",
                subtitle: "A gentle Sunday summary of the week's sessions.",
                value: _recap,
                onChanged: (v) => setState(() => _recap = v),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(KB.s3),
                decoration: BoxDecoration(
                  color: KB.hairline.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(KB.radiusField),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline, color: KB.muted, size: 16),
                    const SizedBox(width: KB.s2),
                    Expanded(
                      child: Text(
                        "We never send marketing — only what you turn on here.",
                        style: KBText.caption(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: KB.s4),
              _PrimaryButton(
                label: "Allow notifications",
                onTap: () => widget.onAllow(NotificationPrefs(
                  helpRequests: _help,
                  pairings: _pair,
                  weeklyRecap: _recap,
                )),
              ),
              const SizedBox(height: KB.s2),
              TextButton(
                onPressed: widget.onSkip,
                child:
                    Text("Not now", style: KBText.label(color: KB.muted)),
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

class _PrefCard extends StatelessWidget {
  const _PrefCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: KB.s4, vertical: KB.s3),
      decoration: BoxDecoration(
        color: KB.surface,
        border: Border.all(color: KB.hairline, width: 1),
        borderRadius: BorderRadius.circular(KB.radiusCard),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration:
                const BoxDecoration(color: KB.hairline, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(icon, color: KB.amber, size: 20),
          ),
          const SizedBox(width: KB.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: KBText.label()),
                const SizedBox(height: 2),
                Text(subtitle, style: KBText.caption()),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: KB.amber,
          ),
        ],
      ),
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
      mainAxisSize: MainAxisSize.min,
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
              child: Center(
                child: Text(label, style: KBText.label(color: KB.surface)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
