// Devices tab — list the caller's registered devices and add new ones.
//
// Today this is a v1 surface: list + add. Last-seen / online-dot will
// light up once Lovable's heartbeat endpoint lands. Revoke is deferred
// until a revokeDevice server-fn exists on the backend.
//
// Replaces the _PlaceholderPage that used to live on the Devices tab
// in KBShell. Unblocks the Owner Home "Need a hand?" flow — that
// button requires at least one registered device before it can fire
// a help request.

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/kb_models.dart';
import '../data/kb_repository.dart';
import '../data/kb_server_fn.dart';
import '../data/kb_supabase.dart';
import '../theme/kb_tokens.dart';
import 'device_detail_page.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  late Future<List<KBDevice>> _devicesFuture;

  @override
  void initState() {
    super.initState();
    _devicesFuture = _fetch();
  }

  Future<List<KBDevice>> _fetch() async {
    final uid = KBSupabase.userId;
    if (uid == null) return const <KBDevice>[];
    return KBRepository.instance.listDevices();
  }

  Future<void> _refresh() async {
    final fresh = _fetch();
    setState(() => _devicesFuture = fresh);
    await fresh;
  }

  Future<void> _openAddDialog() async {
    // Suggest a sensible default name so the user isn't staring at an
    // empty text field. device_info_plus returns the phone's marketing
    // model on Android ("Pixel 9") / iOS; fallback is generic.
    final suggestion = await _proposeDeviceName();
    if (!mounted) return;
    final issued = await showDialog<_IssuedToken>(
      context: context,
      builder: (ctx) => _AddDeviceDialog(suggestedName: suggestion),
    );
    if (issued == null || !mounted) return;
    await _showInstallShareDialog(issued);
    // Device row doesn't exist until someone redeems the token on the
    // target device, so no refresh here. The owner can pull to
    // refresh once the install completes.
  }

  Future<void> _showInstallShareDialog(_IssuedToken issued) async {
    await showDialog<void>(
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
              Text("SET UP ${issued.name.toUpperCase()}",
                  style: KBText.overline()),
              const SizedBox(height: KB.s2),
              Text("Install link ready", style: KBText.title()),
              const SizedBox(height: KB.s3),
              Text(
                "Open this link on the device you're setting up, or enter the code during first-launch onboarding. KinBridge registers it under your account.",
                style: KBText.body(color: KB.muted),
              ),
              const SizedBox(height: KB.s5),
              if (issued.installCode.isNotEmpty) ...[
                Text("OR ENTER CODE",
                    style: KBText.overline(color: KB.muted)),
                const SizedBox(height: KB.s2),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: KB.s4, vertical: KB.s3),
                  decoration: BoxDecoration(
                    color: KB.parchment,
                    borderRadius: BorderRadius.circular(KB.radiusField),
                    border: Border.all(color: KB.hairline, width: 1),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          issued.installCode,
                          style: KBText.title().copyWith(
                            fontFamily: 'monospace',
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                      _CopyIcon(text: issued.installCode),
                    ],
                  ),
                ),
                const SizedBox(height: KB.s4),
              ],
              Text("LINK", style: KBText.overline(color: KB.muted)),
              const SizedBox(height: KB.s2),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: KB.s4, vertical: KB.s3),
                decoration: BoxDecoration(
                  color: KB.parchment,
                  borderRadius: BorderRadius.circular(KB.radiusField),
                  border: Border.all(color: KB.hairline, width: 1),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        issued.installUrl,
                        style: KBText.caption(color: KB.deepInk),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _CopyIcon(text: issued.installUrl),
                  ],
                ),
              ),
              if (issued.expiresAt != null) ...[
                const SizedBox(height: KB.s3),
                Text("Expires ${_relativeFuture(issued.expiresAt!)}",
                    style: KBText.caption(color: KB.muted)),
              ],
              const SizedBox(height: KB.s5),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text("Done",
                      style: KBText.label(color: KB.amber)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _relativeFuture(DateTime t) {
    final diff = t.difference(DateTime.now());
    if (diff.isNegative) return "already";
    if (diff.inMinutes < 1) return "in under a minute";
    if (diff.inHours < 1) return "in ${diff.inMinutes} minutes";
    if (diff.inDays < 1) return "in ${diff.inHours} hours";
    return "in ${diff.inDays} days";
  }

  Future<void> _openDetail(KBDevice device) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DeviceDetailPage(device: device),
      ),
    );
    if (changed == true) await _refresh();
  }

  Future<String?> _proposeDeviceName() async {
    try {
      final info = DeviceInfoPlugin();
      final android = await info.androidInfo;
      // Prefer the marketing name (e.g. "Pixel 9") over device codename.
      final model = android.model.trim();
      if (model.isEmpty) return null;
      return "$model";
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: KB.parchment,
      child: SafeArea(
        child: RefreshIndicator(
          color: KB.amber,
          onRefresh: _refresh,
          child: FutureBuilder<List<KBDevice>>(
            future: _devicesFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                    child: CircularProgressIndicator(color: KB.amber));
              }
              if (snap.hasError) {
                return _ErrorState(
                    onRetry: _refresh, error: snap.error.toString());
              }
              final devices = snap.data ?? const <KBDevice>[];
              if (devices.isEmpty) {
                return _EmptyState(onAdd: _openAddDialog);
              }
              return _DevicesList(
                devices: devices,
                onAdd: _openAddDialog,
                onOpen: _openDetail,
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state — first-run CTA, no FAB clutter
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(KB.s6, KB.s5, KB.s6, KB.s6),
      children: [
        Text("DEVICES", style: KBText.overline()),
        const SizedBox(height: KB.s2),
        Text("Your paired phones & tablets", style: KBText.title()),
        const SizedBox(height: KB.s3),
        Text(
          "Add a phone or tablet so helpers can see it and jump in when you ask for help. We'll give you a short install link to open on the device you're setting up.",
          style: KBText.body(color: KB.muted),
        ),
        const SizedBox(height: KB.s6),
        Container(
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
                  const Icon(Icons.phone_android_rounded,
                      color: KB.amber, size: 28),
                  const SizedBox(width: KB.s3),
                  Expanded(
                    child: Text("Add your first device",
                        style: KBText.heading()),
                  ),
                ],
              ),
              const SizedBox(height: KB.s3),
              Text(
                "Give it a friendly name — \"Mom's phone\" or \"Living room tablet\" — and we'll issue an install link to open on it.",
                style: KBText.body(color: KB.muted),
              ),
              const SizedBox(height: KB.s4),
              SizedBox(
                width: double.infinity,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(KB.radiusPill),
                    onTap: onAdd,
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
                            Text("Set up a device",
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
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// List state
// ---------------------------------------------------------------------------

class _DevicesList extends StatelessWidget {
  const _DevicesList({
    required this.devices,
    required this.onAdd,
    required this.onOpen,
  });
  final List<KBDevice> devices;
  final VoidCallback onAdd;
  final void Function(KBDevice) onOpen;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(KB.s6, KB.s5, KB.s6, 100),
          children: [
            Text("DEVICES", style: KBText.overline()),
            const SizedBox(height: KB.s2),
            Text("Your paired phones & tablets", style: KBText.title()),
            const SizedBox(height: KB.s5),
            for (final d in devices) ...[
              _DeviceCard(device: d, onTap: () => onOpen(d)),
              const SizedBox(height: KB.s3),
            ],
          ],
        ),
        Positioned(
          right: KB.s5,
          bottom: KB.s5,
          child: _AddFab(onTap: onAdd),
        ),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.onTap});
  final KBDevice device;
  final VoidCallback onTap;

  IconData _iconFor(String platform) {
    switch (platform) {
      case 'android':
        return Icons.phone_android_rounded;
      case 'ios':
        return Icons.phone_iphone_rounded;
      default:
        return Icons.devices_other_rounded;
    }
  }

  String _subtitleFor() {
    if (device.online) return "online now";
    final ls = device.lastSeen;
    if (ls == null) return "not seen yet";
    final diff = DateTime.now().difference(ls);
    if (diff.inMinutes < 1) return "just now";
    if (diff.inHours < 1) return "${diff.inMinutes} min ago";
    if (diff.inDays < 1) return "${diff.inHours} hr ago";
    return "${diff.inDays} days ago";
  }

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
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: KB.amber.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(_iconFor(device.platform),
                      color: KB.amber, size: 22),
                ),
                const SizedBox(width: KB.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(device.name,
                          style: KBText.label(),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: device.online ? KB.sage : KB.muted,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: KB.s2),
                          Text(_subtitleFor(),
                              style: KBText.caption(color: KB.muted)),
                        ],
                      ),
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

/// Small inline copy-to-clipboard icon used inside share dialogs.
class _CopyIcon extends StatefulWidget {
  const _CopyIcon({required this.text});
  final String text;

  @override
  State<_CopyIcon> createState() => _CopyIconState();
}

class _CopyIconState extends State<_CopyIcon> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _copy,
      tooltip: _copied ? "Copied" : "Copy",
      icon: Icon(
        _copied ? Icons.check_rounded : Icons.content_copy_rounded,
        color: _copied ? KB.sage : KB.amber,
        size: 18,
      ),
    );
  }
}

class _AddFab extends StatelessWidget {
  const _AddFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(KB.radiusPill),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: KB.amberGradient,
            borderRadius: BorderRadius.circular(KB.radiusPill),
            boxShadow: [
              BoxShadow(
                color: KB.amber.withOpacity(0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Padding(
            padding:
                EdgeInsets.symmetric(horizontal: KB.s5, vertical: KB.s4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: KB.surface, size: 20),
                SizedBox(width: KB.s2),
                Text("Set up a device",
                    style: TextStyle(
                        color: KB.surface,
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add dialog — name + platform picker, calls KBServerFn.issueInstallToken
// and returns the issued token so the caller can present an install-link
// share dialog. Does NOT insert a devices row directly — per Lovable the
// correct flow is install-token → registerDevice (unauthenticated, run on
// the device being set up, carries peer_id). The createDevice endpoint
// exists but is legacy/owner-only and currently returns 500 from any
// caller — we no longer reach for it.
// ---------------------------------------------------------------------------

/// Return type of [_AddDeviceDialog] when the owner successfully
/// issues an install token. The [DevicesPage] shows a follow-up
/// share dialog using these values.
class _IssuedToken {
  _IssuedToken({
    required this.name,
    required this.platform,
    required this.installUrl,
    required this.installCode,
    required this.expiresAt,
  });
  final String name;
  final String platform;
  final String installUrl;
  final String installCode;
  final DateTime? expiresAt;
}

class _AddDeviceDialog extends StatefulWidget {
  const _AddDeviceDialog({this.suggestedName});
  final String? suggestedName;

  @override
  State<_AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<_AddDeviceDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.suggestedName ?? '');
  String _platform = 'android';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = "Give the device a name.");
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // "Add device" → issue an install token and show the URL + 6-digit
    // code for the owner to open on the device they're setting up.
    // This matches the Lovable model: createDevice is an authenticated
    // owner-only legacy path with no intended callers; the correct
    // route is issueInstallToken → registerDevice (unauthenticated,
    // run on the device being installed, carries peer_id).
    //
    // For "set up THIS phone as my device" on a single emulator, the
    // owner can copy the install code and enter it locally via the
    // Connect Code screen — same flow a fresh install would take.
    try {
      final result = await KBServerFn.issueInstallToken(
        proposedName: name,
        proposedPlatform: _platform,
      );
      if (!mounted) return;
      Navigator.of(context).pop(_IssuedToken(
        name: name,
        platform: _platform,
        installUrl: result.installUrl,
        installCode: result.installCode,
        expiresAt: result.expiresAt,
      ));
    } on KBServerFnError catch (err) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = err.message.isEmpty
            ? "Couldn't create the install link. Try again."
            : err.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't create the install link. Try again.";
      });
    }
  }

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
            Text("NEW DEVICE", style: KBText.overline()),
            const SizedBox(height: KB.s2),
            Text("Set up a phone or tablet", style: KBText.title()),
            const SizedBox(height: KB.s3),
            Text(
              "Pick a name helpers will recognize, and we'll generate an install link to open on the device you're setting up.",
              style: KBText.body(color: KB.muted),
            ),
            const SizedBox(height: KB.s5),
            Container(
              decoration: BoxDecoration(
                color: KB.parchment,
                borderRadius: BorderRadius.circular(KB.radiusField),
                border: Border.all(color: KB.hairline, width: 1),
              ),
              padding: const EdgeInsets.symmetric(horizontal: KB.s3),
              child: TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                style: KBText.body(color: KB.deepInk),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: KB.s4),
                  hintText: "Mom's phone",
                  hintStyle: KBText.body(color: KB.muted),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(height: KB.s4),
            Text("PLATFORM", style: KBText.overline()),
            const SizedBox(height: KB.s2),
            Row(
              children: [
                _PlatformChip(
                  label: "Android",
                  selected: _platform == 'android',
                  onTap: () => setState(() => _platform = 'android'),
                ),
                const SizedBox(width: KB.s2),
                _PlatformChip(
                  label: "iOS",
                  selected: _platform == 'ios',
                  onTap: () => setState(() => _platform = 'ios'),
                ),
                const SizedBox(width: KB.s2),
                _PlatformChip(
                  label: "Other",
                  selected: _platform == 'other',
                  onTap: () => setState(() => _platform = 'other'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: KB.s4),
              Container(
                padding: const EdgeInsets.all(KB.s3),
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
                      child: Text(_error!,
                          style: KBText.body(color: KB.deepInk)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: KB.s5),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed:
                      _busy ? null : () => Navigator.of(context).pop(false),
                  child: Text("Cancel", style: KBText.label(color: KB.muted)),
                ),
                const SizedBox(width: KB.s2),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(KB.radiusPill),
                    onTap: _busy ? null : _submit,
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: _busy ? null : KB.amberGradient,
                        color: _busy ? KB.hairline : null,
                        borderRadius: BorderRadius.circular(KB.radiusPill),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: KB.s5, vertical: KB.s3),
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: KB.muted, strokeWidth: 2))
                            : Text("Generate install link",
                                style: KBText.label(color: KB.surface)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformChip extends StatelessWidget {
  const _PlatformChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(KB.radiusPill),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: KB.s3),
            decoration: BoxDecoration(
              color: selected ? KB.amber.withOpacity(0.15) : KB.parchment,
              borderRadius: BorderRadius.circular(KB.radiusPill),
              border: Border.all(
                color: selected ? KB.amber : KB.hairline,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: KBText.label(
                    color: selected ? KB.amber : KB.muted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error state
// ---------------------------------------------------------------------------

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry, required this.error});
  final VoidCallback onRetry;
  final String error;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(KB.s6, KB.s5, KB.s6, KB.s6),
      children: [
        Text("DEVICES", style: KBText.overline()),
        const SizedBox(height: KB.s2),
        Text("Couldn't load your devices", style: KBText.title()),
        const SizedBox(height: KB.s3),
        Text(
          "Pull down to retry, or check your connection.",
          style: KBText.body(color: KB.muted),
        ),
        const SizedBox(height: KB.s4),
        Container(
          padding: const EdgeInsets.all(KB.s3),
          decoration: BoxDecoration(
            color: KB.coral.withOpacity(0.1),
            borderRadius: BorderRadius.circular(KB.radiusField),
            border: Border.all(color: KB.coral.withOpacity(0.3), width: 1),
          ),
          child: Text(error,
              style: KBText.caption(color: KB.deepInk)),
        ),
        const SizedBox(height: KB.s5),
        SizedBox(
          width: double.infinity,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(KB.radiusPill),
              onTap: onRetry,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: KB.amberGradient,
                  borderRadius: BorderRadius.circular(KB.radiusPill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: KB.s4),
                  child: Center(
                    child: Text("Try again",
                        style: KBText.label(color: KB.surface)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
