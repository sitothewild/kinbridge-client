// Tailnet (Headscale) bridge from Flutter.
//
// Today this is a **stub**. The full libtailscale embed is multi-day work:
//   1. Download + cross-compile libtailscale (Go → arm64 / armv7 / x86_64 .so)
//      against Android NDK r25c using `gomobile bind`.
//   2. Drop the resulting AAR into
//      `android/tailscale/` and add it to Gradle.
//   3. Write a thin JNI layer (Kotlin) that exposes start/stop/status to
//      Dart via a `MethodChannel("kinbridge/tailnet")`.
//   4. Replace [NoopTailnetService] with `AndroidTailnetService` that wraps
//      that MethodChannel.
//
// Until then [KBTailnet.instance] is [NoopTailnetService] — the APK still
// works on the LAN because the baked server IP (192.168.68.54) is reachable
// directly. Swapping to a tailscale IP is a pure substitution: the KB
// client never had to know it was routed through a tunnel.
//
// References:
//   • https://pkg.go.dev/tailscale.com/tsnet  (userspace tailnet)
//   • https://pkg.go.dev/golang.org/x/mobile/cmd/gomobile
//   • Headscale preauth key flow already wired in kinbridge-api
//     (`src/lib/headscale.ts`). The key travels via the kinbridge_token's
//     `hs_key` claim; [KBTailnet.start] will accept it.

import 'package:flutter/foundation.dart';

enum TailnetState {
  /// libtailscale not embedded in this build.
  notAvailable,

  /// Embedded but not yet started.
  idle,

  /// `tsnet.Start` in progress.
  starting,

  /// Tunnel is up. Returned [tailnetIp] is usable.
  running,

  /// Not up; [lastError] explains why.
  failed,
}

abstract class KBTailnet {
  /// The singleton used app-wide. Swap to an `AndroidTailnetService` once
  /// the real libtailscale AAR is dropped in — no call sites need to
  /// change.
  static KBTailnet instance = const NoopTailnetService();

  TailnetState get state;

  /// IP inside the tailnet once [state] == [TailnetState.running]. Null
  /// otherwise. Used by the KB core to talk to the relay.
  String? get tailnetIp;

  /// Last error, if [state] == [TailnetState.failed].
  String? get lastError;

  /// Start (or no-op, in the stub). Called from app boot once the user is
  /// signed in and we have a fresh Headscale pre-auth key from the API.
  Future<void> start({required String preAuthKey});

  /// Stop the tunnel. Called on sign-out or "Emergency stop" in settings.
  Future<void> stop();
}

/// Placeholder implementation. Everything is a no-op. Calls to [start]
/// return immediately without side-effects; the APK falls back to
/// direct-LAN connection (which is what it already does today).
class NoopTailnetService implements KBTailnet {
  const NoopTailnetService();

  @override
  TailnetState get state => TailnetState.notAvailable;

  @override
  String? get tailnetIp => null;

  @override
  String? get lastError =>
      "libtailscale not embedded in this build — see "
      "lib/kinbridge/data/tailnet_service.dart for the wiring plan.";

  @override
  Future<void> start({required String preAuthKey}) async {
    if (kDebugMode) {
      debugPrint("kb.tailnet: start() called in stub build, preAuthKey "
          "length=${preAuthKey.length}. Real libtailscale AAR has not yet "
          "been dropped in; falling back to direct LAN.");
    }
  }

  @override
  Future<void> stop() async {
    if (kDebugMode) debugPrint("kb.tailnet: stop() called on stub");
  }
}
