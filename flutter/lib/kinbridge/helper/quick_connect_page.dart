import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/kb_server_fn.dart';
import '../session/live_session_page.dart';
import '../theme/kb_tokens.dart';

/// Helper-side: enter a 6-digit code to either (a) pair long-term with a
/// family member's device, or (b) join a one-shot QuickConnect session
/// someone already has running. Both paths hit the same
/// [KBServerFn.redeemConnectionCode]; the response's `mode` field tells
/// us which branch.
///
/// See `android-snippets/QUICKCONNECT.md` and `HELPER_INVITE.md` for the
/// product spec.
class QuickConnectPage extends StatefulWidget {
  const QuickConnectPage({super.key});

  @override
  State<QuickConnectPage> createState() => _QuickConnectPageState();
}

class _QuickConnectPageState extends State<QuickConnectPage> {
  static const _len = 6;
  final List<TextEditingController> _controllers =
      List.generate(_len, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(_len, (_) => FocusNode());
  bool _busy = false;
  String? _error;

  String get _code => _controllers.map((c) => c.text).join();
  bool get _ready => _code.length == _len;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _onChanged(int i, String v) {
    if (v.isEmpty) {
      if (i > 0) _nodes[i - 1].requestFocus();
    } else {
      final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) {
        _controllers[i].text = '';
      } else {
        final d = digits.substring(0, 1);
        _controllers[i].text = d;
        _controllers[i].selection = TextSelection.collapsed(offset: d.length);
        if (i < _len - 1) _nodes[i + 1].requestFocus();
      }
    }
    if (_error != null) setState(() => _error = null);
    setState(() {});
    if (_ready) _submit();
  }

  Future<void> _submit() async {
    if (_busy || !_ready) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    HapticFeedback.selectionClick();

    try {
      final r = await KBServerFn.redeemConnectionCode(code: _code);
      if (!mounted) return;

      if (r.isQuickConnect && r.sessionId != null) {
        // Jump straight into the session. Pop the code page first so
        // Back from the session lands on Helper Home, not on the code
        // screen.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => LiveSessionPage(
              peerName: r.deviceName,
              peerInitials: r.deviceName.isNotEmpty
                  ? r.deviceName.substring(0, 1).toUpperCase()
                  : '?',
              peerDevice: r.deviceName,
              sessionId: r.sessionId,
            ),
          ),
        );
      } else if (r.isPairing) {
        // Long-term pairing — owner still has to approve. Show a brief
        // confirmation and pop back to Helper Home. The pairing will
        // appear in their list once approved.
        await showDialog(
          context: context,
          builder: (ctx) => _PairingSentDialog(deviceName: r.deviceName),
        );
        if (!mounted) return;
        Navigator.of(context).pop();
      } else {
        setState(() => _error = "Unexpected response. Try again.");
      }
    } on KBServerFnError catch (err) {
      setState(() => _error = _friendly(err));
      // Reset inputs so the user can re-type.
      for (final c in _controllers) {
        c.clear();
      }
      _nodes[0].requestFocus();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(KBServerFnError err) {
    final m = err.message;
    if (m.toLowerCase().contains('expired')) {
      return "That code expired. Ask for a fresh one.";
    }
    if (m.toLowerCase().contains('own device')) {
      return "You can't connect to your own device.";
    }
    if (m.toLowerCase().contains('invalid') ||
        m.toLowerCase().contains('not found')) {
      return "Code not recognized. Double-check the digits.";
    }
    return "Couldn't redeem that code. Try again in a moment.";
  }

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
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: KB.deepInk),
                  ),
                  Expanded(
                    child: Text("Enter a code",
                        textAlign: TextAlign.center, style: KBText.label()),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: KB.s5),
              Text("Enter the 6-digit code", style: KBText.title()),
              const SizedBox(height: KB.s3),
              Text(
                "Ask the person who needs help to read you the code from their dashboard. It's only valid for a few minutes.",
                style: KBText.body(color: KB.muted),
              ),
              const SizedBox(height: KB.s8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (int i = 0; i < _len; i++)
                    _CodeBox(
                      controller: _controllers[i],
                      focusNode: _nodes[i],
                      onChanged: (v) => _onChanged(i, v),
                      enabled: !_busy,
                    ),
                ],
              ),
              const SizedBox(height: KB.s5),
              if (_error != null)
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
                        child: Text(_error!,
                            style: KBText.body(color: KB.deepInk)),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              if (_busy)
                Center(
                  child: Column(
                    children: [
                      const CircularProgressIndicator(color: KB.amber),
                      const SizedBox(height: KB.s3),
                      Text("Checking code…",
                          style: KBText.caption(color: KB.muted)),
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

class _CodeBox extends StatelessWidget {
  const _CodeBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.enabled,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        enabled: enabled,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        textInputAction: TextInputAction.next,
        maxLength: 1,
        style: KBText.title().copyWith(fontSize: 28),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: KB.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: KB.s4),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KB.radiusField),
            borderSide: BorderSide(color: KB.hairline, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KB.radiusField),
            borderSide: BorderSide(color: KB.amber, width: 2),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KB.radiusField),
            borderSide: BorderSide(color: KB.hairline, width: 1),
          ),
        ),
      ),
    );
  }
}

class _PairingSentDialog extends StatelessWidget {
  const _PairingSentDialog({required this.deviceName});
  final String deviceName;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: KB.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KB.radiusCard),
      ),
      child: Padding(
        padding: const EdgeInsets.all(KB.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: KB.sage.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.check_rounded,
                      color: KB.sage, size: 22),
                ),
                const SizedBox(width: KB.s3),
                Expanded(
                    child:
                        Text("Request sent", style: KBText.modalTitle())),
              ],
            ),
            const SizedBox(height: KB.s3),
            Text(
              "$deviceName's owner will see your request in a moment. Once they approve you, they'll appear in your family list.",
              style: KBText.body(color: KB.muted),
            ),
            const SizedBox(height: KB.s5),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  backgroundColor: KB.amber,
                  padding: const EdgeInsets.symmetric(
                      horizontal: KB.s5, vertical: KB.s3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(KB.radiusPill),
                  ),
                ),
                child: Text("OK", style: KBText.label(color: KB.surface)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
