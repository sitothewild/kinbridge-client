import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common.dart' show gFFI;
import '../../utils/image.dart' show ImagePainter;
import '../data/kb_models.dart';
import '../data/kb_realtime.dart';
import '../data/kb_repository.dart';
import '../data/kb_server_fn.dart';
import '../theme/kb_tokens.dart';
import '../widgets/kb_avatar.dart';
import 'kb_remote_connection.dart';

/// Live Session overlay (spec page 9).
///
/// Wraps the RustDesk remote-view surface with KinBridge chrome:
///   • "END-TO-END ENCRYPTED" eyebrow
///   • Header: "Helping <peerName> · Live · 00:12" + peer avatar + End button
///   • Mirrored screen area (placeholder container — Phase IV-b hooks up the
///     real remote-view widget from the RustDesk core via session_add +
///     session_start)
///   • Tool chips: Tap · Draw · Type · Voice
///   • Chat panel with message list + composer
///
/// Entry point today is synthetic (helper taps "Help now" on [HelperHomePage]).
/// In Phase V + Week-2 this page is opened by the `kinbridge://session/<id>`
/// deep link after [KinBridgeApi.resolveSession] returns connection details.
class LiveSessionPage extends StatefulWidget {
  const LiveSessionPage({
    super.key,
    required this.peerName,
    required this.peerInitials,
    this.peerDevice,
    this.sessionId,
    this.devicePeerId,
  });

  final String peerName;
  final String peerInitials;
  final String? peerDevice;

  /// Supabase `sessions.id`. When present, the page hydrates from
  /// `chat_messages` + subscribes to realtime INSERTs, and the Send button
  /// writes through [kbSendChat]. When null, the page renders a static
  /// demo conversation (pre-Lovable-integration mode).
  final String? sessionId;

  /// RustDesk `devices.peer_id` of the device being helped. When
  /// present, the page initiates a [KBRemoteConnection] on mount and
  /// the view surface renders live frames. Null means the device
  /// hasn't completed install-token redemption (no agent registered)
  /// and the surface shows the "waiting" placeholder.
  final String? devicePeerId;

  @override
  State<LiveSessionPage> createState() => _LiveSessionPageState();
}

enum _SessionTool { tap, draw, type, voice }

class _LiveSessionPageState extends State<LiveSessionPage> {
  final _start = DateTime.now();
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  _SessionTool _tool = _SessionTool.tap;

  final List<KBChatMessage> _messages = [];
  StreamSubscription<KBChatMessage>? _chatSub;
  bool _sending = false;

  final _composer = TextEditingController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(_start));
    });
    _hydrateChat();
    _openRemoteConnection();
  }

  Future<void> _openRemoteConnection() async {
    final pid = widget.devicePeerId;
    if (pid == null || pid.isEmpty) return;
    // Fire-and-forget: KBRemoteConnection flips its ValueNotifier as
    // state changes, and _RemoteViewSurface subscribes to it. Any
    // connect error surfaces through state=failed + errorMessage.
    await KBRemoteConnection.instance.connect(peerId: pid);
  }

  Future<void> _hydrateChat() async {
    final sid = widget.sessionId;
    if (sid == null) {
      // Demo mode — seed a short static conversation so the panel looks
      // populated during pre-integration walkthroughs.
      final now = DateTime.now();
      setState(() {
        _messages.addAll([
          KBChatMessage(
            id: 'demo-1',
            sessionId: 'demo',
            senderId: 'demo-peer',
            fromSelf: false,
            text: "I can't find the Wi-Fi settings.",
            at: now.subtract(const Duration(seconds: 22)),
          ),
          KBChatMessage(
            id: 'demo-2',
            sessionId: 'demo',
            senderId: 'demo-self',
            fromSelf: true,
            text: "No worries Mom — I'll show you. Hold on one sec.",
            at: now.subtract(const Duration(seconds: 8)),
          ),
        ]);
      });
      return;
    }

    try {
      final initial = await KBRepository.instance.listChat(sid);
      if (!mounted) return;
      setState(() => _messages
        ..clear()
        ..addAll(initial));
    } catch (err) {
      debugPrint('LiveSessionPage: initial chat fetch failed: $err');
    }

    _chatSub = KBRealtime.chatStream(sid).listen((msg) {
      if (!mounted) return;
      // Guard against the INSERT echo duplicating a message we already
      // rendered (repositories can race with realtime on fast round-trips).
      if (_messages.any((m) => m.id == msg.id)) return;
      setState(() => _messages.add(msg));
    });
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _ticker?.cancel();
    _composer.dispose();
    // Tear down the Rust-core session so a second LiveSessionPage push
    // doesn't collide with a half-open peer handle. Safe to call when
    // idle per KBRemoteConnection's contract.
    KBRemoteConnection.instance.disconnect();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  Future<void> _confirmEnd() async {
    final shouldEnd = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
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
              Text("End session?", style: KBText.modalTitle()),
              const SizedBox(height: KB.s2),
              Text(
                "${widget.peerName} will see that you've disconnected.",
                style: KBText.body(color: KB.muted),
              ),
              const SizedBox(height: KB.s5),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text("Keep helping",
                        style: KBText.label(color: KB.muted)),
                  ),
                  const SizedBox(width: KB.s2),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: TextButton.styleFrom(
                      backgroundColor: KB.coral,
                      padding: const EdgeInsets.symmetric(
                          horizontal: KB.s5, vertical: KB.s3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(KB.radiusPill),
                      ),
                    ),
                    child: Text("End session",
                        style: KBText.label(color: KB.surface)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (shouldEnd == true && mounted) {
      final sid = widget.sessionId;
      if (sid != null) {
        // Fire-and-forget — we still pop even if the network call fails,
        // the session is effectively ended on our side regardless.
        unawaited(KBServerFn.endSession(sessionId: sid)
            .catchError((err) => debugPrint('endSession failed: $err')));
      }
      Navigator.of(context).pop();
    }
  }

  Future<void> _sendMessage() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    final sid = widget.sessionId;

    if (sid == null) {
      // Demo mode — local-only append, no network.
      setState(() {
        _messages.add(KBChatMessage(
          id: 'demo-${DateTime.now().microsecondsSinceEpoch}',
          sessionId: 'demo',
          senderId: 'demo-self',
          fromSelf: true,
          text: text,
          at: DateTime.now(),
        ));
        _composer.clear();
      });
      return;
    }

    setState(() => _sending = true);
    final original = text;
    _composer.clear();
    try {
      await kbSendChat(sessionId: sid, body: original);
      // The realtime channel will emit the INSERT and our listener appends
      // it — no optimistic local add here, to avoid duplicate bubbles.
    } catch (err) {
      debugPrint('kbSendChat failed: $err');
      if (mounted) {
        _composer.text = original; // restore so the user can retry
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: KB.deepInk,
            behavior: SnackBarBehavior.floating,
            content: Text(
              "Message didn't send. Try again.",
              style: KBText.body(color: KB.parchment),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _confirmEnd();
      },
      child: Scaffold(
        backgroundColor: KB.deepInk,
        body: SafeArea(
          child: Column(
            children: [
              _EncryptedEyebrow(),
              _SessionHeader(
                peerName: widget.peerName,
                peerInitials: widget.peerInitials,
                elapsed: _formatElapsed(_elapsed),
                onEnd: _confirmEnd,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: KB.s4),
                  child: _RemoteViewSurface(
                    peerDevice: widget.peerDevice,
                    tool: _tool,
                  ),
                ),
              ),
              _ToolStrip(
                selected: _tool,
                onSelect: (t) => setState(() => _tool = t),
              ),
              _ChatPanel(
                messages: _messages,
                composer: _composer,
                onSend: _sendMessage,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EncryptedEyebrow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: KB.s3, bottom: KB.s2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_rounded, size: 12, color: KB.sage),
          const SizedBox(width: KB.s1),
          Text(
            "END-TO-END ENCRYPTED",
            style: KBText.overline(color: KB.sage),
          ),
        ],
      ),
    );
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.peerName,
    required this.peerInitials,
    required this.elapsed,
    required this.onEnd,
  });
  final String peerName;
  final String peerInitials;
  final String elapsed;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(KB.s4, KB.s2, KB.s4, KB.s3),
      child: Row(
        children: [
          KBAvatar(initials: peerInitials, size: 40, tint: KB.amber),
          const SizedBox(width: KB.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Helping $peerName",
                    style: KBText.heading(color: KB.surface)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: KB.coral,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: KB.s1),
                    Text("LIVE",
                        style: KBText.overline(color: KB.coral)
                            .copyWith(letterSpacing: 1.5)),
                    const SizedBox(width: KB.s2),
                    Text("·",
                        style: KBText.caption(
                            color: KB.parchment.withOpacity(0.6))),
                    const SizedBox(width: KB.s2),
                    Text(elapsed,
                        style: KBText.caption(
                                color: KB.parchment.withOpacity(0.85))
                            .copyWith(fontFeatures: const [
                          FontFeature.tabularFigures(),
                        ])),
                  ],
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(KB.radiusPill),
              onTap: onEnd,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: KB.s4, vertical: KB.s2),
                decoration: BoxDecoration(
                  color: KB.coral,
                  borderRadius: BorderRadius.circular(KB.radiusPill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.call_end_rounded,
                        size: 16, color: KB.surface),
                    const SizedBox(width: KB.s1),
                    Text("End", style: KBText.label(color: KB.surface)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live remote-frame surface.
///
/// State machine per [KBRemoteConnection]:
///   idle        → "waiting" placeholder (device agent not registered
///                 or no peerId given on page open)
///   connecting  → spinner + "Connecting to <peerDevice>…"
///   connected   → live frame from `gFFI.imageModel.image`, painted via
///                 RustDesk's `ImagePainter` inside a letterboxed
///                 container. AnimatedBuilder listens to the
///                 `ChangeNotifier` so every decoded frame triggers a
///                 repaint.
///   failed      → inline error + retry chip
///
/// v1 is view-only. Input forwarding (tap-through, scroll, keyboard)
/// is deliberately deferred — the bulk of the product value is
/// seeing the screen.
class _RemoteViewSurface extends StatelessWidget {
  const _RemoteViewSurface({required this.peerDevice, required this.tool});
  final String? peerDevice;
  final _SessionTool tool;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: KB.s3),
      decoration: BoxDecoration(
        color: const Color(0xFF1B130C),
        borderRadius: BorderRadius.circular(KB.radiusCard),
        border: Border.all(color: KB.muted.withOpacity(0.25), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(KB.radiusCard),
        child: Stack(
          children: [
            ValueListenableBuilder<KBRemoteState>(
              valueListenable: KBRemoteConnection.instance.state,
              builder: (context, st, _) {
                switch (st) {
                  case KBRemoteState.connected:
                    return _LiveFrame(peerDevice: peerDevice);
                  case KBRemoteState.connecting:
                    return _ConnectingOverlay(peerDevice: peerDevice);
                  case KBRemoteState.failed:
                    return _FailedOverlay(
                      peerDevice: peerDevice,
                      message: KBRemoteConnection.instance.errorMessage,
                    );
                  case KBRemoteState.idle:
                    return _IdleOverlay(peerDevice: peerDevice);
                }
              },
            ),
            Positioned(
              top: KB.s3,
              left: KB.s3,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: KB.s3, vertical: KB.s1),
                decoration: BoxDecoration(
                  color: KB.deepInk.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(KB.radiusPill),
                ),
                child: Text(
                  _toolLabel(tool),
                  style: KBText.caption(color: KB.parchment),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _toolLabel(_SessionTool t) {
    switch (t) {
      case _SessionTool.tap:
        return "Tap-through enabled";
      case _SessionTool.draw:
        return "Drawing on screen";
      case _SessionTool.type:
        return "Keyboard ready";
      case _SessionTool.voice:
        return "Voice connected";
    }
  }
}

// ---------------------------------------------------------------------------
// _RemoteViewSurface state overlays
// ---------------------------------------------------------------------------

/// The actual live remote frame. Subscribes to `gFFI.imageModel` via
/// [AnimatedBuilder] so every decoded frame (the ChangeNotifier fires
/// on each update) triggers a repaint through RustDesk's existing
/// [ImagePainter]. Letterboxed inside the container with aspect
/// preserved via FittedBox.
class _LiveFrame extends StatelessWidget {
  const _LiveFrame({required this.peerDevice});
  final String? peerDevice;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: gFFI.imageModel,
      builder: (context, _) {
        final img = gFFI.imageModel.image;
        if (img == null) {
          return _ConnectingOverlay(peerDevice: peerDevice);
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            // Paint the decoded peer frame at its native pixel size
            // inside a FittedBox so it letterboxes into the container
            // without upscaling past 1:1.
            return FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: img.width.toDouble(),
                height: img.height.toDouble(),
                child: CustomPaint(
                  painter: ImagePainter(
                    image: img,
                    x: 0,
                    y: 0,
                    scale: 1.0,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ConnectingOverlay extends StatelessWidget {
  const _ConnectingOverlay({required this.peerDevice});
  final String? peerDevice;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
                color: KB.amber, strokeWidth: 2.5),
          ),
          const SizedBox(height: KB.s4),
          Text(
            peerDevice != null
                ? "Connecting to $peerDevice…"
                : "Connecting to the remote screen…",
            style: KBText.body(color: KB.parchment.withOpacity(0.7)),
          ),
          const SizedBox(height: KB.s2),
          Text(
            "End-to-end encrypted. Only you and ${peerDevice ?? 'the owner'} can see this.",
            style: KBText.caption(color: KB.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _IdleOverlay extends StatelessWidget {
  const _IdleOverlay({required this.peerDevice});
  final String? peerDevice;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KB.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.phonelink_off_rounded,
                size: 48, color: KB.parchment.withOpacity(0.25)),
            const SizedBox(height: KB.s3),
            Text(
              peerDevice ?? "Remote screen not available yet",
              style: KBText.body(color: KB.parchment.withOpacity(0.55)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KB.s2),
            Text(
              "Waiting for the agent on the other side to come online.",
              style: KBText.caption(color: KB.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _FailedOverlay extends StatelessWidget {
  const _FailedOverlay({required this.peerDevice, this.message});
  final String? peerDevice;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KB.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 48, color: KB.coral.withOpacity(0.7)),
            const SizedBox(height: KB.s3),
            Text(
              "Couldn't connect to $peerDevice",
              style: KBText.body(color: KB.parchment),
              textAlign: TextAlign.center,
            ),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: KB.s2),
              Text(
                message!,
                style: KBText.caption(color: KB.muted),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToolStrip extends StatelessWidget {
  const _ToolStrip({required this.selected, required this.onSelect});
  final _SessionTool selected;
  final ValueChanged<_SessionTool> onSelect;

  @override
  Widget build(BuildContext context) {
    const tools = <_ToolChipSpec>[
      _ToolChipSpec(_SessionTool.tap, Icons.touch_app_rounded, "Tap"),
      _ToolChipSpec(_SessionTool.draw, Icons.gesture_rounded, "Draw"),
      _ToolChipSpec(_SessionTool.type, Icons.keyboard_rounded, "Type"),
      _ToolChipSpec(_SessionTool.voice, Icons.mic_rounded, "Voice"),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(KB.s4, KB.s2, KB.s4, KB.s3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final t in tools)
            _ToolChip(
              spec: t,
              active: t.tool == selected,
              onTap: () => onSelect(t.tool),
            ),
        ],
      ),
    );
  }
}

class _ToolChipSpec {
  const _ToolChipSpec(this.tool, this.icon, this.label);
  final _SessionTool tool;
  final IconData icon;
  final String label;
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.spec,
    required this.active,
    required this.onTap,
  });
  final _ToolChipSpec spec;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = active ? KB.amber : KB.surface.withOpacity(0.08);
    final fg = active ? KB.surface : KB.parchment.withOpacity(0.85);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KB.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: KB.s4, vertical: KB.s2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(KB.radiusPill),
            border: Border.all(
              color: active ? KB.amber : KB.muted.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(spec.icon, size: 16, color: fg),
              const SizedBox(width: KB.s1),
              Text(spec.label, style: KBText.label(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({
    required this.messages,
    required this.composer,
    required this.onSend,
  });
  final List<KBChatMessage> messages;
  final TextEditingController composer;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KB.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(KB.radiusCard),
        ),
      ),
      padding: EdgeInsets.only(
        left: KB.s4,
        right: KB.s4,
        top: KB.s4,
        bottom: MediaQuery.of(context).viewInsets.bottom + KB.s3,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 140),
            child: ListView(
              shrinkWrap: true,
              reverse: false,
              padding: EdgeInsets.zero,
              children: [
                for (final m in messages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: KB.s2),
                    child: _ChatBubble(message: m),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: KB.parchment,
                    borderRadius: BorderRadius.circular(KB.radiusPill),
                    border: Border.all(color: KB.hairline, width: 1),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: KB.s4, vertical: KB.s1),
                  child: TextField(
                    controller: composer,
                    style: KBText.body(color: KB.deepInk),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: "Write a message…",
                      hintStyle: KBText.body(color: KB.muted),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: KB.s2),
              Material(
                color: KB.amber,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onSend,
                  child: const Padding(
                    padding: EdgeInsets.all(KB.s3),
                    child: Icon(Icons.send_rounded,
                        size: 18, color: KB.surface),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});
  final KBChatMessage message;

  @override
  Widget build(BuildContext context) {
    final self = message.fromSelf;
    return Row(
      mainAxisAlignment:
          self ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: KB.s4, vertical: KB.s2),
            decoration: BoxDecoration(
              color: self ? KB.amber : KB.parchment,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(KB.radiusCard),
                topRight: const Radius.circular(KB.radiusCard),
                bottomLeft: Radius.circular(self ? KB.radiusCard : 4),
                bottomRight: Radius.circular(self ? 4 : KB.radiusCard),
              ),
            ),
            child: Text(
              message.text,
              style: KBText.body(
                color: self ? KB.surface : KB.deepInk,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
