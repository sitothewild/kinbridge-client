import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/kb_tokens.dart';

/// Spec 02 — Connect Code.
/// 6-character alphanumeric code redemption. Spec shows a mix of letters +
/// digits (e.g. "KB7P__"). We accept A–Z and 0–9, auto-uppercase, auto-advance.
class ConnectCodePage extends StatefulWidget {
  const ConnectCodePage({
    super.key,
    required this.onBack,
    required this.onSubmit,
    required this.onSkip,
  });

  final VoidCallback onBack;
  final void Function(String code) onSubmit;
  final VoidCallback onSkip;

  @override
  State<ConnectCodePage> createState() => _ConnectCodePageState();
}

class _ConnectCodePageState extends State<ConnectCodePage> {
  static const int _len = 6;
  final List<TextEditingController> _controllers =
      List.generate(_len, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(_len, (_) => FocusNode());

  String get _code => _controllers.map((c) => c.text).join();
  bool get _ready => _code.length == _len;

  @override
  void initState() {
    super.initState();
    // Autofocus the first box so the system keyboard appears immediately.
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
      final up = v.toUpperCase();
      if (up != v) {
        _controllers[i].text = up;
        _controllers[i].selection =
            TextSelection.collapsed(offset: up.length);
      }
      if (i < _len - 1) _nodes[i + 1].requestFocus();
    }
    setState(() {});
  }

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
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back, color: KB.deepInk),
                  ),
                  Expanded(
                    child: Text("Connect to a helper",
                        textAlign: TextAlign.center, style: KBText.label()),
                  ),
                  TextButton(
                    onPressed: widget.onSkip,
                    child:
                        Text("Skip", style: KBText.label(color: KB.muted)),
                  ),
                ],
              ),
              const SizedBox(height: KB.s4),
              Center(
                child: _DotRow(active: 1, total: 3),
              ),
              const SizedBox(height: KB.s6),
              Text("Enter your invite code", style: KBText.title()),
              const SizedBox(height: KB.s3),
              Text(
                "Ask your helper to share the 6-character code from their KinBridge app.",
                style: KBText.body(color: KB.muted),
              ),
              const SizedBox(height: KB.s6),
              Text("INVITE CODE", style: KBText.overline()),
              const SizedBox(height: KB.s3),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (int i = 0; i < _len; i++)
                    _CodeBox(
                      controller: _controllers[i],
                      focusNode: _nodes[i],
                      onChanged: (v) => _onChanged(i, v),
                    ),
                ],
              ),
              const SizedBox(height: KB.s5),
              if (_ready)
                Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: KB.sage, size: 18),
                    const SizedBox(width: KB.s2),
                    Text("Looks good — keep going.",
                        style: KBText.caption(color: KB.sage)),
                  ],
                )
              else
                Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: KB.muted, size: 18),
                    const SizedBox(width: KB.s2),
                    Expanded(
                      child: Text(
                          "Codes expire after 10 minutes for your safety.",
                          style: KBText.caption()),
                    ),
                  ],
                ),
              const Spacer(),
              _PrimaryButton(
                label: "Continue",
                enabled: _ready,
                onTap: _ready ? () => widget.onSubmit(_code) : null,
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
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 56,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        textAlign: TextAlign.center,
        maxLength: 1,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.next,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
        ],
        style:
            KBText.heading().copyWith(fontSize: 24, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          counterText: "",
          filled: true,
          fillColor: KB.surface,
          contentPadding: EdgeInsets.zero,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KB.radiusField),
            borderSide: const BorderSide(color: KB.hairline, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(KB.radiusField),
            borderSide: const BorderSide(color: KB.amber, width: 2),
          ),
        ),
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
  const _PrimaryButton({
    required this.label,
    required this.onTap,
    required this.enabled,
  });
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
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
              gradient: enabled ? KB.amberGradient : null,
              color: enabled ? null : KB.hairline,
              borderRadius: BorderRadius.circular(KB.radiusPill),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: KB.s4),
              child: Center(
                child: Text(label,
                    style: KBText.label(
                        color: enabled ? KB.surface : KB.muted)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
