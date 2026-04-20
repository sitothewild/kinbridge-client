import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/kb_supabase.dart';
import '../shell/kb_shell.dart' show KBRole;
import '../theme/kb_tokens.dart';

/// Email/password sign-in for returning users.
///
/// MVP path to validate the repo end-to-end before PKCE deep-link lands.
/// After PKCE is wired (V-b-step-5), add a "Continue with Google" button
/// above the email field — same page, same [onSignedIn] callback.
///
/// Role is inferred from Supabase `user_roles` after auth completes (see
/// [SUPABASE_SCHEMA.md] `app_role`). Maps:
///   helper       -> KBRole.helper
///   device_owner -> KBRole.owner  (default on signup)
///   admin        -> KBRole.owner
class SignInPage extends StatefulWidget {
  const SignInPage({
    super.key,
    required this.onBack,
    required this.onSignedIn,
  });

  final VoidCallback onBack;
  final void Function(KBRole role) onSignedIn;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_form.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    HapticFeedback.selectionClick();

    try {
      await KBSupabase.init();
      final res = await KBSupabase.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      final uid = res.user?.id;
      if (uid == null) {
        setState(() => _error = "Sign-in succeeded but no user id was returned.");
        return;
      }
      final role = await _inferRole(uid);
      if (!mounted) return;
      widget.onSignedIn(role);
    } catch (err) {
      setState(() => _error = _friendlyError(err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<KBRole> _inferRole(String userId) async {
    try {
      final row = await KBSupabase.client
          .from('user_roles')
          .select('role')
          .eq('user_id', userId)
          .maybeSingle();
      final r = (row?['role'] as String?)?.toLowerCase();
      return r == 'helper' ? KBRole.helper : KBRole.owner;
    } catch (_) {
      // On any RLS / network hiccup, default to owner — less likely to
      // confuse a first-time user than dumping them in helper mode.
      return KBRole.owner;
    }
  }

  String _friendlyError(Object err) {
    final s = err.toString();
    if (s.contains('Invalid login credentials')) {
      return "That email and password don't match.";
    }
    if (s.contains('Email not confirmed')) {
      return "Check your inbox to confirm the email first.";
    }
    if (s.contains('SocketException') || s.contains('Failed host lookup')) {
      return "Couldn't reach KinBridge. Check your connection and try again.";
    }
    return "Something went wrong. Try again in a moment.";
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KB.parchment,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(KB.s6, KB.s3, KB.s6, KB.s6),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: KB.deepInk),
                    tooltip: "Back",
                  ),
                ),
                const SizedBox(height: KB.s3),
                Text("WELCOME BACK", style: KBText.overline()),
                const SizedBox(height: KB.s2),
                Text("Sign in", style: KBText.title()),
                const SizedBox(height: KB.s3),
                Text(
                  "Use the email and password you created on the KinBridge dashboard.",
                  style: KBText.body(color: KB.muted),
                ),
                const SizedBox(height: KB.s6),
                _FieldLabel("EMAIL"),
                const SizedBox(height: KB.s2),
                _KBTextField(
                  controller: _email,
                  hint: "you@example.com",
                  icon: Icons.alternate_email_rounded,
                  keyboard: TextInputType.emailAddress,
                  autofill: const [AutofillHints.email],
                  validator: (v) {
                    final t = v?.trim() ?? "";
                    if (t.isEmpty) return "Please enter your email.";
                    if (!t.contains("@") || !t.contains(".")) {
                      return "That doesn't look like an email.";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: KB.s5),
                _FieldLabel("PASSWORD"),
                const SizedBox(height: KB.s2),
                _KBTextField(
                  controller: _password,
                  hint: "••••••••",
                  icon: Icons.lock_outline_rounded,
                  obscure: !_showPassword,
                  autofill: const [AutofillHints.password],
                  onSubmitted: (_) => _submit(),
                  trailing: IconButton(
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: KB.muted,
                      size: 20,
                    ),
                    tooltip: _showPassword ? "Hide password" : "Show password",
                  ),
                  validator: (v) {
                    if ((v ?? "").isEmpty) return "Please enter your password.";
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: KB.s4),
                  Container(
                    padding: const EdgeInsets.all(KB.s4),
                    decoration: BoxDecoration(
                      color: KB.coral.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(KB.radiusField),
                      border: Border.all(
                          color: KB.coral.withOpacity(0.4), width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: KB.coral, size: 18),
                        const SizedBox(width: KB.s2),
                        Expanded(
                          child: Text(
                            _error!,
                            style: KBText.body(color: KB.deepInk),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: KB.s6),
                _PrimaryButton(
                    label: _busy ? "Signing in…" : "Sign in",
                    onTap: _busy ? null : _submit),
                const SizedBox(height: KB.s2),
                Center(
                  child: TextButton(
                    onPressed: widget.onBack,
                    child: Text("Not registered yet? Go back",
                        style: KBText.label(color: KB.amber)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: KBText.overline());
}

class _KBTextField extends StatelessWidget {
  const _KBTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.keyboard,
    this.autofill,
    this.validator,
    this.onSubmitted,
    this.trailing,
  });
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboard;
  final List<String>? autofill;
  final String? Function(String?)? validator;
  final void Function(String)? onSubmitted;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KB.surface,
        borderRadius: BorderRadius.circular(KB.radiusField),
        border: Border.all(color: KB.hairline, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: KB.s3),
      child: Row(
        children: [
          Icon(icon, color: KB.muted, size: 20),
          const SizedBox(width: KB.s2),
          Expanded(
            child: TextFormField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboard,
              autofillHints: autofill,
              onFieldSubmitted: onSubmitted,
              validator: validator,
              style: KBText.body(color: KB.deepInk),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: KB.s4),
                hintText: hint,
                hintStyle: KBText.body(color: KB.muted),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
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
              gradient: disabled
                  ? null
                  : KB.amberGradient,
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
