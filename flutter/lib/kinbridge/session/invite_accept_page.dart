import 'package:flutter/material.dart';

import '../data/kb_server_fn.dart';
import '../data/kb_supabase.dart';
import '../theme/kb_tokens.dart';
import '../widgets/kb_avatar.dart';

/// Shown when the user taps a verified `https://kinbridge.support/invite/<token>`
/// App Link. Two-stage flow:
///
///   1. [KBServerFn.lookupInvite] — preview without consuming. If the
///      token isn't valid (not_found / revoked / consumed / expired),
///      render a friendly rejection state with the reason copy.
///   2. User taps "Accept" → [KBServerFn.acceptHelperInvite] — consumes
///      the token, creates an **approved** `device_pairings` row.
///
/// See `android-snippets/HELPER_INVITE.md`.
class InviteAcceptPage extends StatefulWidget {
  const InviteAcceptPage({super.key, required this.token});
  final String token;

  @override
  State<InviteAcceptPage> createState() => _InviteAcceptPageState();
}

class _InviteAcceptPageState extends State<InviteAcceptPage> {
  late Future<KBInviteLookup> _lookup;
  bool _accepting = false;
  String? _acceptError;
  String? _successDeviceId;

  @override
  void initState() {
    super.initState();
    _lookup = KBServerFn.lookupInvite(token: widget.token);
  }

  Future<void> _accept() async {
    if (_accepting) return;
    setState(() {
      _accepting = true;
      _acceptError = null;
    });
    try {
      final r = await KBServerFn.acceptHelperInvite(token: widget.token);
      if (!mounted) return;
      setState(() => _successDeviceId = r.deviceId);
    } on KBServerFnError catch (err) {
      if (!mounted) return;
      setState(() {
        _acceptError = err.message.contains('own invite')
            ? "This invite was sent by your own account."
            : "Couldn't accept the invite. Try opening the link again.";
      });
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KB.parchment,
      appBar: AppBar(
        backgroundColor: KB.parchment,
        surfaceTintColor: KB.parchment,
        elevation: 0,
        iconTheme: const IconThemeData(color: KB.deepInk),
        title: Text("Invite", style: KBText.heading()),
      ),
      body: SafeArea(
        child: FutureBuilder<KBInviteLookup>(
          future: _lookup,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: KB.amber),
              );
            }
            final look = snap.data;
            if (look == null) {
              return _ErrorState(
                message: "Couldn't reach KinBridge. Check your connection.",
              );
            }
            if (!look.valid) {
              return _ErrorState(message: look.friendlyReason);
            }
            if (_successDeviceId != null) {
              return _SuccessState(
                deviceName: look.deviceName ?? 'this device',
                inviterName: look.inviterName ?? 'your family',
                onDone: () => Navigator.of(context).pop(),
              );
            }
            return _PreviewState(
              lookup: look,
              busy: _accepting,
              error: _acceptError,
              onAccept: _accept,
              onDecline: () => Navigator.of(context).pop(),
            );
          },
        ),
      ),
    );
  }
}

class _PreviewState extends StatelessWidget {
  const _PreviewState({
    required this.lookup,
    required this.busy,
    required this.error,
    required this.onAccept,
    required this.onDecline,
  });
  final KBInviteLookup lookup;
  final bool busy;
  final String? error;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final inviter = lookup.inviterName ?? 'Someone';
    final device = lookup.deviceName ?? 'their device';
    return Padding(
      padding: const EdgeInsets.fromLTRB(KB.s6, KB.s4, KB.s6, KB.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: KB.s4),
          Center(
            child: KBAvatar(
              initials: inviter.isNotEmpty
                  ? inviter.substring(0, 1).toUpperCase()
                  : '?',
              size: 80,
              tint: KB.amber,
            ),
          ),
          const SizedBox(height: KB.s5),
          Text("$inviter invited you",
              textAlign: TextAlign.center, style: KBText.title()),
          const SizedBox(height: KB.s3),
          Text(
            "Accept to become an approved helper for $device. You'll be able to start support sessions without asking for a new code each time.",
            textAlign: TextAlign.center,
            style: KBText.body(color: KB.muted),
          ),
          if (lookup.note != null && lookup.note!.trim().isNotEmpty) ...[
            const SizedBox(height: KB.s4),
            Container(
              padding: const EdgeInsets.all(KB.s4),
              decoration: BoxDecoration(
                color: KB.amber.withOpacity(0.10),
                borderRadius: BorderRadius.circular(KB.radiusField),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.format_quote_rounded,
                      color: KB.amber, size: 18),
                  const SizedBox(width: KB.s2),
                  Expanded(
                    child: Text(
                      lookup.note!,
                      style: KBText.body(color: KB.deepInk),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (lookup.expiresAt != null) ...[
            const SizedBox(height: KB.s3),
            Center(
              child: Text(
                "Expires ${_relativeFuture(lookup.expiresAt!)}",
                style: KBText.caption(),
              ),
            ),
          ],
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
                _Bullet(
                    icon: Icons.visibility_outlined,
                    text:
                        "See $inviter's screen when a session is active."),
                const SizedBox(height: KB.s3),
                _Bullet(
                    icon: Icons.touch_app_rounded,
                    text:
                        "Tap and type for them — only during consented sessions."),
                const SizedBox(height: KB.s3),
                _Bullet(
                    icon: Icons.block_rounded,
                    text:
                        "$inviter can revoke your access at any time from Devices."),
              ],
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: KB.s4),
            Container(
              padding: const EdgeInsets.all(KB.s4),
              decoration: BoxDecoration(
                color: KB.coral.withOpacity(0.15),
                borderRadius: BorderRadius.circular(KB.radiusField),
                border:
                    Border.all(color: KB.coral.withOpacity(0.4), width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: KB.coral, size: 18),
                  const SizedBox(width: KB.s2),
                  Expanded(
                    child: Text(error!,
                        style: KBText.body(color: KB.deepInk)),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          _PrimaryButton(
            label: busy ? "Accepting…" : "Accept invite",
            onTap: busy ? null : onAccept,
          ),
          const SizedBox(height: KB.s2),
          Center(
            child: TextButton(
              onPressed: busy ? null : onDecline,
              child:
                  Text("Not now", style: KBText.label(color: KB.muted)),
            ),
          ),
        ],
      ),
    );
  }
}

String _relativeFuture(DateTime when) {
  final now = DateTime.now();
  if (when.isBefore(now)) return 'soon';
  final diff = when.difference(now);
  if (diff.inDays >= 2) return 'in ${diff.inDays} days';
  if (diff.inDays == 1) return 'tomorrow';
  if (diff.inHours >= 2) return 'in ${diff.inHours} hours';
  if (diff.inHours == 1) return 'in 1 hour';
  if (diff.inMinutes >= 2) return 'in ${diff.inMinutes} minutes';
  return 'in a moment';
}

class _SuccessState extends StatelessWidget {
  const _SuccessState({
    required this.deviceName,
    required this.inviterName,
    required this.onDone,
  });
  final String inviterName;
  final String deviceName;
  final VoidCallback onDone;

  String _selfInitial() {
    final me = KBSupabase.client.auth.currentUser;
    final name = (me?.userMetadata?['display_name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name.substring(0, 1).toUpperCase();
    final email = me?.email;
    if (email != null && email.isNotEmpty) return email.substring(0, 1).toUpperCase();
    return 'S';
  }

  String _inviterInitial() {
    return inviterName.isNotEmpty
        ? inviterName.substring(0, 1).toUpperCase()
        : 'M';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(KB.s6, KB.s5, KB.s6, KB.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: KB.s4),
          // Celebration mark: sage radial behind a checkmark
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [KB.sage, KB.sage.withOpacity(0.0)],
                  stops: const [0.55, 1.0],
                ),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.check_rounded,
                  color: KB.surface, size: 36),
            ),
          ),
          const SizedBox(height: KB.s5),
          Text("Pairing complete",
              textAlign: TextAlign.center, style: KBText.overline()),
          const SizedBox(height: KB.s2),
          Text("You're connected with $inviterName",
              textAlign: TextAlign.center, style: KBText.title()),
          const SizedBox(height: KB.s3),
          Text(
            "$inviterName approved you just now. You can offer help any time $inviterName asks for it on $deviceName.",
            textAlign: TextAlign.center,
            style: KBText.body(color: KB.muted),
          ),
          const SizedBox(height: KB.s6),
          _AvatarBridge(
            selfInitial: _selfInitial(),
            selfLabel: "You",
            selfRole: "Helper",
            peerInitial: _inviterInitial(),
            peerLabel: inviterName,
            peerRole: "Pixel 8",
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
                Text("HERE'S WHAT YOU CAN DO", style: KBText.overline()),
                const SizedBox(height: KB.s3),
                _Bullet(
                    icon: Icons.visibility_outlined,
                    text: "View $inviterName's screen when they say yes."),
                const SizedBox(height: KB.s3),
                _Bullet(
                    icon: Icons.touch_app_outlined,
                    text: "Send messages and gentle taps."),
                const SizedBox(height: KB.s3),
                _Bullet(
                    icon: Icons.bolt_outlined,
                    text: "Help during their active session."),
              ],
            ),
          ),
          const SizedBox(height: KB.s3),
          Text(
            "We'll notify you the moment $inviterName asks for help.",
            textAlign: TextAlign.center,
            style: KBText.caption(color: KB.muted),
          ),
          const SizedBox(height: KB.s5),
          _PrimaryButton(label: "Done — back to dashboard", onTap: onDone),
        ],
      ),
    );
  }
}

/// Avatar ↔ sage-gradient line ↔ Avatar. Visual beat for spec p10.
class _AvatarBridge extends StatelessWidget {
  const _AvatarBridge({
    required this.selfInitial,
    required this.selfLabel,
    required this.selfRole,
    required this.peerInitial,
    required this.peerLabel,
    required this.peerRole,
  });
  final String selfInitial;
  final String selfLabel;
  final String selfRole;
  final String peerInitial;
  final String peerLabel;
  final String peerRole;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Node(
            initial: selfInitial,
            label: selfLabel,
            role: selfRole,
            tint: KB.sage),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: KB.s3),
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [KB.sage, KB.amber],
                ),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
        _Node(
            initial: peerInitial,
            label: peerLabel,
            role: peerRole,
            tint: KB.amber),
      ],
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({
    required this.initial,
    required this.label,
    required this.role,
    required this.tint,
  });
  final String initial;
  final String label;
  final String role;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: tint.withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(color: tint, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(initial, style: KBText.heading(color: tint)),
        ),
        const SizedBox(height: KB.s2),
        Text(label,
            style: KBText.label(), overflow: TextOverflow.ellipsis),
        Text(role,
            style: KBText.caption(color: KB.muted),
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(KB.s6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 48, color: KB.coral.withOpacity(0.7)),
          const SizedBox(height: KB.s4),
          Text("That invite didn't work",
              textAlign: TextAlign.center, style: KBText.heading()),
          const SizedBox(height: KB.s3),
          Text(message,
              textAlign: TextAlign.center,
              style: KBText.body(color: KB.muted)),
          const SizedBox(height: KB.s6),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              backgroundColor: KB.amber,
              padding: const EdgeInsets.symmetric(
                  horizontal: KB.s6, vertical: KB.s3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(KB.radiusPill),
              ),
            ),
            child: Text("Close", style: KBText.label(color: KB.surface)),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: KB.amber, size: 18),
        const SizedBox(width: KB.s3),
        Expanded(
          child: Text(text, style: KBText.body(color: KB.deepInk)),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(KB.radiusPill),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: disabled ? null : KB.amberGradient,
              color: disabled ? KB.hairline : null,
              borderRadius: BorderRadius.circular(KB.radiusPill),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: KB.s4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label,
                      style: KBText.label(
                          color: disabled ? KB.muted : KB.surface)),
                  if (!disabled) ...[
                    const SizedBox(width: KB.s2),
                    const Icon(Icons.arrow_forward_rounded,
                        color: KB.surface, size: 18),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
