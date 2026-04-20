import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase/supabase.dart' show AuthState, User;

import '../data/kb_supabase.dart';
import '../onboarding/sign_in_page.dart';
import '../theme/kb_tokens.dart';

/// Account tab content for [KBShell]. Surfaces Supabase sign-in/out
/// controls so a user who skipped the onboarding SignInPage — or whose
/// session lapsed on cold boot — can authenticate without clearing app
/// data. The legacy RustDesk SettingsPage stays reachable as an
/// "Advanced" route for users who need proxy / low-level tweaks.
class KBAccountPage extends StatefulWidget {
  const KBAccountPage({super.key, required this.advancedSettingsPage});

  /// The legacy RustDesk SettingsPage, pushed as a full-screen route
  /// when the user taps Advanced. Not embedded inline — nesting a
  /// scroll view inside a scroll view produces a bad scroll experience
  /// on Android.
  final Widget advancedSettingsPage;

  @override
  State<KBAccountPage> createState() => _KBAccountPageState();
}

class _KBAccountPageState extends State<KBAccountPage> {
  StreamSubscription<AuthState>? _sub;
  User? _user;
  String? _displayName;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  Future<void> _bind() async {
    try {
      await KBSupabase.init();
    } catch (_) {
      // Best-effort: if Supabase init fails, the sign-in route will
      // surface the real error when the user taps it.
    }
    if (!mounted) return;
    setState(() => _user = KBSupabase.client.auth.currentUser);
    _refreshDisplayName();
    _sub = KBSupabase.authStateChanges().listen((s) {
      if (!mounted) return;
      setState(() => _user = s.session?.user);
      _refreshDisplayName();
    });
  }

  Future<void> _refreshDisplayName() async {
    final uid = _user?.id;
    if (uid == null) {
      if (_displayName != null) setState(() => _displayName = null);
      return;
    }
    try {
      final row = await KBSupabase.client
          .from('profiles')
          .select('display_name')
          .eq('id', uid)
          .maybeSingle();
      final name = (row?['display_name'] as String?)?.trim();
      if (!mounted) return;
      setState(() =>
          _displayName = (name == null || name.isEmpty) ? null : name);
    } catch (_) {
      // Best-effort — sign-in state is what matters; name is cosmetic.
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _openSignIn() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => SignInPage(
          onBack: () => Navigator.of(ctx).pop(),
          onSignedIn: (_) => Navigator.of(ctx).pop(),
        ),
      ),
    );
    // Auth-state listener wakes us up when sign-in lands; just in case
    // the listener missed the edge (e.g. already-signed-in restore),
    // resync on return.
    if (!mounted) return;
    setState(() => _user = KBSupabase.client.auth.currentUser);
    _refreshDisplayName();
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KB.surface,
        title: Text("Sign out?", style: KBText.title()),
        content: Text(
          "You'll need to sign in again to see your paired devices, start sessions, or sync history.",
          style: KBText.body(color: KB.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text("Cancel", style: KBText.label(color: KB.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text("Sign out", style: KBText.label(color: KB.coral)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _signingOut = true);
    try {
      await KBSupabase.signOut();
    } catch (_) {
      // Auth-state listener will reconcile; swallow here so the user
      // isn't shown a scary error on a best-effort sign-out.
    }
    if (mounted) setState(() => _signingOut = false);
  }

  void _openAdvanced() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: false,
        builder: (_) => Scaffold(
          backgroundColor: KB.parchment,
          appBar: AppBar(
            backgroundColor: KB.surface,
            elevation: 0,
            foregroundColor: KB.deepInk,
            title: Text("Advanced", style: KBText.label()),
          ),
          body: widget.advancedSettingsPage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: KB.parchment,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(KB.s6, KB.s5, KB.s6, KB.s6),
          children: [
            Text("ACCOUNT", style: KBText.overline()),
            const SizedBox(height: KB.s2),
            _AccountCard(
              user: _user,
              displayName: _displayName,
              signingOut: _signingOut,
              onSignIn: _openSignIn,
              onSignOut: _confirmSignOut,
            ),
            const SizedBox(height: KB.s6),
            Text("SETTINGS", style: KBText.overline()),
            const SizedBox(height: KB.s2),
            _AdvancedRow(onTap: _openAdvanced),
            const SizedBox(height: KB.s6),
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.user,
    required this.displayName,
    required this.signingOut,
    required this.onSignIn,
    required this.onSignOut,
  });

  final User? user;
  final String? displayName;
  final bool signingOut;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final u = user;
    if (u == null) return _signedOut();
    return _signedIn(u);
  }

  Widget _signedOut() {
    return Container(
      padding: const EdgeInsets.all(KB.s5),
      decoration: BoxDecoration(
        color: KB.surface,
        borderRadius: BorderRadius.circular(KB.radiusField),
        border: Border.all(color: KB.hairline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("You're not signed in.", style: KBText.body()),
          const SizedBox(height: KB.s2),
          Text(
            "Sign in with Google or email to see your paired devices, start sessions, and sync history.",
            style: KBText.body(color: KB.muted),
          ),
          const SizedBox(height: KB.s4),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(KB.radiusPill),
                onTap: onSignIn,
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
                        Text("Sign in",
                            style: KBText.label(color: KB.surface)),
                        const SizedBox(width: KB.s2),
                        const Icon(Icons.arrow_forward_rounded,
                            color: KB.surface, size: 18),
                      ],
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

  Widget _signedIn(User u) {
    final primary = displayName ?? u.email ?? "Signed in";
    final secondary =
        (u.email != null && u.email != primary) ? u.email : null;
    return Container(
      padding: const EdgeInsets.all(KB.s5),
      decoration: BoxDecoration(
        color: KB.surface,
        borderRadius: BorderRadius.circular(KB.radiusField),
        border: Border.all(color: KB.hairline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: KB.amber.withOpacity(0.15),
                child: Text(_initialsFor(primary),
                    style: KBText.label(color: KB.amber)),
              ),
              const SizedBox(width: KB.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(primary,
                        style: KBText.body(), overflow: TextOverflow.ellipsis),
                    if (secondary != null) ...[
                      const SizedBox(height: 2),
                      Text(secondary,
                          style: KBText.caption(color: KB.muted),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: KB.s4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: signingOut ? null : onSignOut,
              style: OutlinedButton.styleFrom(
                foregroundColor: KB.coral,
                side: BorderSide(color: KB.coral.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(vertical: KB.s3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(KB.radiusPill),
                ),
              ),
              icon: signingOut
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: KB.coral, strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_rounded, size: 18),
              label: Text(signingOut ? "Signing out…" : "Sign out"),
            ),
          ),
        ],
      ),
    );
  }

  String _initialsFor(String s) {
    final t = s.trim();
    if (t.isEmpty) return "?";
    final parts = t.split(RegExp(r'\s+|@'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return t.substring(0, 1).toUpperCase();
  }
}

class _AdvancedRow extends StatelessWidget {
  const _AdvancedRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KB.surface,
        borderRadius: BorderRadius.circular(KB.radiusField),
        border: Border.all(color: KB.hairline, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(KB.radiusField),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(KB.s4),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, color: KB.muted, size: 22),
                const SizedBox(width: KB.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Advanced", style: KBText.label()),
                      const SizedBox(height: 2),
                      Text("Network, proxy, and low-level options",
                          style: KBText.caption(color: KB.muted)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: KB.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
