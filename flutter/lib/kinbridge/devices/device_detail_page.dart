// Device detail — owner-side full-screen page.
//
// Surfaces the four owner-intent actions that previously required
// switching to the Lovable web dashboard:
//   • Invite a helper for this device (→ https://kinbridge.support/invite/…)
//   • Send install link (→ https://kinbridge.support/install/…)
//   • Rename the device
//   • Revoke the device
//
// Last-seen + online dot populate once Lovable's /heartbeat endpoint
// is live and writing devices.last_seen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/kb_models.dart';
import '../data/kb_server_fn.dart';
import '../data/kb_supabase.dart';
import '../theme/kb_tokens.dart';

class DeviceDetailPage extends StatefulWidget {
  const DeviceDetailPage({super.key, required this.device});

  final KBDevice device;

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  late KBDevice _device;
  bool _revoking = false;

  @override
  void initState() {
    super.initState();
    _device = widget.device;
  }

  IconData get _platformIcon {
    switch (_device.platform) {
      case 'android':
        return Icons.phone_android_rounded;
      case 'ios':
        return Icons.phone_iphone_rounded;
      default:
        return Icons.devices_other_rounded;
    }
  }

  String get _lastSeenSubtitle {
    if (_device.online) return "online now";
    final ls = _device.lastSeen;
    if (ls == null) return "not seen yet — waiting for heartbeat";
    final diff = DateTime.now().difference(ls);
    if (diff.inMinutes < 1) return "just now";
    if (diff.inHours < 1) return "${diff.inMinutes} minutes ago";
    if (diff.inDays < 1) return "${diff.inHours} hours ago";
    return "${diff.inDays} days ago";
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _device.name);
    final newName = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KB.surface,
        title: Text("Rename device", style: KBText.title()),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: KBText.body(color: KB.deepInk),
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KB.radiusField),
              borderSide: BorderSide(color: KB.hairline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KB.radiusField),
              borderSide: const BorderSide(color: KB.amber, width: 1.5),
            ),
            hintText: "Mom's phone",
            hintStyle: KBText.body(color: KB.muted),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text("Cancel", style: KBText.label(color: KB.muted)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(controller.text.trim()),
            child: Text("Save", style: KBText.label(color: KB.amber)),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == _device.name) return;
    try {
      // RLS policy "Owners manage their devices" permits the UPDATE
      // scoped to auth.uid() = owner_id.
      await KBSupabase.client
          .from('devices')
          .update({'name': newName}).eq('id', _device.id);
      if (!mounted) return;
      setState(() {
        _device = KBDevice(
          id: _device.id,
          ownerName: _device.ownerName,
          ownerInitials: _device.ownerInitials,
          name: newName,
          platform: _device.platform,
          lastSeen: _device.lastSeen,
          peerId: _device.peerId,
        );
      });
    } catch (err) {
      if (!mounted) return;
      _snack("Couldn't rename — $err");
    }
  }

  Future<void> _inviteHelper() async {
    try {
      final invite = await KBServerFn.createHelperInvite(
        deviceId: _device.id,
      );
      if (!mounted) return;
      _showShareDialog(
        title: "Helper invite ready",
        subtitle:
            "Send this link to the person you want to help with ${_device.name}. They tap, sign in, and accept — then you'll see them in your helper list.",
        url: invite.inviteUrl,
        expiresAt: invite.expiresAt,
      );
    } on KBServerFnError catch (err) {
      if (!mounted) return;
      _snack(err.message.isNotEmpty
          ? err.message
          : "Couldn't create the invite. Try again.");
    } catch (_) {
      if (!mounted) return;
      _snack("Couldn't create the invite. Try again.");
    }
  }

  Future<void> _sendInstallLink() async {
    try {
      final result = await KBServerFn.issueInstallToken(
        proposedName: _device.name,
        proposedPlatform: _device.platform,
      );
      if (!mounted) return;
      _showShareDialog(
        title: "Install link ready",
        subtitle:
            "Send this link to the device you want to set up. When they open it, KinBridge installs and registers itself as \"${_device.name}\" under your account.",
        url: result.installUrl,
        code: result.installCode.isNotEmpty ? result.installCode : null,
        expiresAt: result.expiresAt,
      );
    } on KBServerFnError catch (err) {
      if (!mounted) return;
      _snack(err.message.isNotEmpty
          ? err.message
          : "Couldn't issue install link. Try again.");
    } catch (_) {
      if (!mounted) return;
      _snack("Couldn't issue install link. Try again.");
    }
  }

  Future<void> _revoke() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KB.surface,
        title: Text("Remove ${_device.name}?", style: KBText.title()),
        content: Text(
          "Helpers will lose access immediately. Any open session on this device ends. This can't be undone — you'd need to set it up again from scratch.",
          style: KBText.body(color: KB.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text("Cancel", style: KBText.label(color: KB.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text("Remove", style: KBText.label(color: KB.coral)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _revoking = true);
    try {
      // No revokeDevice server fn exists yet; direct delete via RLS
      // ("Owners manage their devices" policy covers DELETE).
      await KBSupabase.client
          .from('devices')
          .delete()
          .eq('id', _device.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (err) {
      if (mounted) {
        setState(() => _revoking = false);
        _snack("Couldn't remove — $err");
      }
    }
  }

  void _showShareDialog({
    required String title,
    required String subtitle,
    required String url,
    String? code,
    DateTime? expiresAt,
  }) {
    showDialog<void>(
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
              Text("SHARE", style: KBText.overline()),
              const SizedBox(height: KB.s2),
              Text(title, style: KBText.title()),
              const SizedBox(height: KB.s3),
              Text(subtitle, style: KBText.body(color: KB.muted)),
              const SizedBox(height: KB.s5),
              if (code != null) ...[
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
                          code,
                          style: KBText.title().copyWith(
                            fontFamily: 'monospace',
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                      _CopyButton(text: code),
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
                        url,
                        style: KBText.caption(color: KB.deepInk),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _CopyButton(text: url),
                  ],
                ),
              ),
              if (expiresAt != null) ...[
                const SizedBox(height: KB.s3),
                Text(
                  "Expires ${_relativeFuture(expiresAt)}",
                  style: KBText.caption(color: KB.muted),
                ),
              ],
              const SizedBox(height: KB.s5),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text("Done", style: KBText.label(color: KB.amber)),
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

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(msg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KB.parchment,
      appBar: AppBar(
        backgroundColor: KB.parchment,
        elevation: 0,
        foregroundColor: KB.deepInk,
        title: Text(_device.name,
            style: KBText.label(), overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: "Rename",
            onPressed: _editName,
            icon: const Icon(Icons.edit_outlined, color: KB.muted),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(KB.s6, KB.s2, KB.s6, KB.s6),
          children: [
            Container(
              padding: const EdgeInsets.all(KB.s5),
              decoration: BoxDecoration(
                color: KB.surface,
                borderRadius: BorderRadius.circular(KB.radiusCard),
                border: Border.all(color: KB.hairline, width: 1),
              ),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: KB.amber.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(_platformIcon, color: KB.amber, size: 36),
                  ),
                  const SizedBox(height: KB.s4),
                  Text(_device.name,
                      style: KBText.heading(),
                      textAlign: TextAlign.center),
                  const SizedBox(height: KB.s2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _device.online ? KB.sage : KB.muted,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: KB.s2),
                      Text(_lastSeenSubtitle,
                          style: KBText.caption(color: KB.muted)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: KB.s6),
            Text("ACTIONS", style: KBText.overline()),
            const SizedBox(height: KB.s2),
            _ActionTile(
              icon: Icons.person_add_alt_1_rounded,
              tint: KB.amber,
              title: "Invite a helper",
              subtitle:
                  "Send someone a link so they can help with ${_device.name}.",
              onTap: _inviteHelper,
            ),
            const SizedBox(height: KB.s3),
            _ActionTile(
              icon: Icons.ios_share_rounded,
              tint: KB.amber,
              title: "Send install link",
              subtitle:
                  "Set up a new phone or tablet under this device's name.",
              onTap: _sendInstallLink,
            ),
            const SizedBox(height: KB.s3),
            _ActionTile(
              icon: Icons.delete_outline_rounded,
              tint: KB.coral,
              title: _revoking ? "Removing…" : "Remove this device",
              subtitle:
                  "Helpers lose access and any open session ends. Can't be undone.",
              onTap: _revoking ? null : _revoke,
            ),
            const SizedBox(height: KB.s8),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
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
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tint.withOpacity(disabled ? 0.08 : 0.15),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon,
                      color: disabled ? KB.muted : tint, size: 20),
                ),
                const SizedBox(width: KB.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: KBText.label()),
                      const SizedBox(height: 2),
                      Text(subtitle,
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

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});
  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
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
