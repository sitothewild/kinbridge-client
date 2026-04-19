import 'package:flutter/material.dart';
import '../theme/kb_tokens.dart';

/// Circular initials avatar used throughout KinBridge screens (Recent Helpers
/// row, Activity feed, Session list). Supports an optional online dot in the
/// bottom-right corner (sage for online, muted for offline).
class KBAvatar extends StatelessWidget {
  const KBAvatar({
    super.key,
    required this.initials,
    this.size = 48,
    this.online,
    this.tint,
  });

  /// One-to-two character initials. Longer strings are truncated by the
  /// paint system — prefer first-name initial + family-surname initial.
  final String initials;
  final double size;

  /// null = hide status dot. true/false = show sage/muted dot.
  final bool? online;

  /// Background tint for the circle. Defaults to amber for helpers,
  /// sage for self, coral for urgent — caller decides.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final bg = tint ?? KB.amber;
    final dotSize = (size * 0.28).clamp(10.0, 18.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: KBText.label(color: KB.surface).copyWith(
                fontSize: size * 0.38,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (online != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: online! ? KB.sage : KB.muted,
                  shape: BoxShape.circle,
                  border: Border.all(color: KB.parchment, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
