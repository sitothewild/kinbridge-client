import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/kb_tokens.dart';
import '../owner/owner_home_page.dart';
import '../helper/helper_home_page.dart';
import '../history/history_page.dart';
import '../session/kb_deep_link.dart';
import '../data/kb_supabase.dart';
import '../devices/devices_page.dart';
import 'kb_account_page.dart';

/// Runtime role. Phase V: hydrated from Supabase `user_roles`.
/// Phase III: user picks on first launch, persisted in shared prefs.
enum KBRole { owner, helper }

/// Top-level Android shell — replaces RustDesk's mobile HomePage.
///
/// Navigation matches spec page 7: Home · Devices · History · Settings.
/// The body of "Home" is role-dependent: Owner sees the "Ask for help" page,
/// Helper sees the family list.
class KBShell extends StatefulWidget {
  const KBShell({
    super.key,
    required this.role,
    required this.settingsPage,
    this.ownerDisplayName = "Mom",
    this.helperDisplayName = "Sara",
  });

  final KBRole role;
  final Widget settingsPage;
  final String ownerDisplayName;
  final String helperDisplayName;

  @override
  State<KBShell> createState() => _KBShellState();
}

class _KBShellState extends State<KBShell> {
  int _tab = 0;
  String? _realDisplayName;
  StreamSubscription<Object?>? _profileSub;

  @override
  void initState() {
    super.initState();
    // If a kinbridge:// link arrived before the navigator was ready (cold
    // boot race), replay it now that we're mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      KBDeepLink.drainPending();
    });
    _loadProfileName();
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    super.dispose();
  }

  /// Pull display_name from the signed-in user's `profiles` row so the
  /// greeting reads "Hi, Wilson 🦋" instead of the hardcoded "Hi, Mom".
  /// Falls back to the static prop when signed out.
  Future<void> _loadProfileName() async {
    final uid = KBSupabase.userId;
    if (uid == null) return;
    try {
      final row = await KBSupabase.client
          .from('profiles')
          .select('display_name')
          .eq('id', uid)
          .maybeSingle();
      final name = (row?['display_name'] as String?)?.trim();
      if (!mounted || name == null || name.isEmpty) return;
      setState(() => _realDisplayName = name);
    } catch (err) {
      debugPrint('kb.shell: profile fetch failed: $err');
    }
  }

  String get _ownerName => _realDisplayName ?? widget.ownerDisplayName;
  String get _helperName => _realDisplayName ?? widget.helperDisplayName;

  late final List<_KBTab> _tabs = [
    _KBTab(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: "Home",
      build: () => widget.role == KBRole.owner
          ? OwnerHomePage(displayName: _ownerName)
          : HelperHomePage(displayName: _helperName),
    ),
    _KBTab(
      icon: Icons.devices_other_outlined,
      activeIcon: Icons.devices_other_rounded,
      label: "Devices",
      build: () => const DevicesPage(),
    ),
    _KBTab(
      icon: Icons.history_outlined,
      activeIcon: Icons.history_rounded,
      label: "History",
      build: () => const HistoryPage(),
    ),
    _KBTab(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: "Settings",
      build: () =>
          KBAccountPage(advancedSettingsPage: widget.settingsPage),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KB.parchment,
      body: _tabs[_tab].build(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: KB.surface,
          border: Border(top: BorderSide(color: KB.hairline, width: 1)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: KB.s3, vertical: KB.s2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (int i = 0; i < _tabs.length; i++)
                  _NavItem(
                    tab: _tabs[i],
                    selected: i == _tab,
                    onTap: () => setState(() => _tab = i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KBTab {
  _KBTab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.build,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Widget Function() build;
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });
  final _KBTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? KB.amber : KB.muted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KB.radiusField),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: KB.s2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? tab.activeIcon : tab.icon, color: color, size: 24),
              const SizedBox(height: 2),
              Text(
                tab.label,
                style: KBText.caption(color: color).copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({
    required this.title,
    required this.subtitle,
    required this.eyebrow,
  });
  final String title;
  final String subtitle;
  final String eyebrow;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: KB.parchment,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(KB.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eyebrow, style: KBText.overline()),
              const SizedBox(height: KB.s2),
              Text(title, style: KBText.title()),
              const SizedBox(height: KB.s3),
              Text(subtitle, style: KBText.body(color: KB.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
