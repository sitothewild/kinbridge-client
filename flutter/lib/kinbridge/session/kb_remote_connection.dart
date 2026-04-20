// KinBridge wrapper around RustDesk's session-lifecycle plumbing.
//
// Why this exists
// ---------------
// RustDesk exposes a single global `gFFI` that owns exactly one remote
// session at a time. Its `gFFI.start(peerId, ...)` fires a connection off
// and the various models (`ffiModel`, `imageModel`, `inputModel`,
// `chatModel`) become live and drive `RemotePage` UI.
//
// For KinBridge we want to own the session chrome ourselves
// (`LiveSessionPage` with the E2EE eyebrow, chat panel, tool chips) and
// render the remote frames inside it. Using RustDesk's `RemotePage`
// directly would take over the whole screen and throw out that chrome.
//
// This wrapper provides a narrow, typed API over `gFFI.start` /
// `closeConnection` plus a [ValueNotifier] that drives
// [_RemoteViewSurface] in `LiveSessionPage`. It does **not** render the
// actual screen frames — that's Phase IV-b part 2 (a `Texture` widget
// bound to `gFFI.imageModel.textureId`, plus pointer-event wiring into
// `gFFI.inputModel` for tap-through).
//
// How it's called
// ---------------
//   • Helper taps "Help now" on their device in the KinBridge app.
//   • Flutter calls `KBServerFn.startSession(deviceId:)` → Supabase
//     `sessions.id`.
//   • Flutter calls `POST /v1/sessions/:id/resolve` on kinbridge-api →
//     `{relay_host, relay_port, rendezvous_token, ice_servers,
//       device_fingerprint}`.
//   • Flutter calls [KBRemoteConnection.connect] with the peer's
//     RustDesk ID (held on `devices.rustdesk_peer_id` — see
//     prerequisites below) and the `rendezvous_token` as the
//     `connToken`.
//   • The RustDesk core registers with hbbs, opens a peer session,
//     starts receiving frames. Our [state] flips
//     `connecting` → `connected` on first frame.
//
// Prerequisites before this actually connects to a peer
// -----------------------------------------------------
// 1. **`devices.rustdesk_peer_id`** — needs to exist in Supabase.
//    The KinBridge Android agent registers with hbbs at startup and
//    learns its own peer ID; it should POST that to kinbridge-api's
//    `/api/devices/:id/heartbeat` with a `peer_id` field, which
//    persists it to `devices.rustdesk_peer_id`. Lovable-side
//    schema addition + heartbeat route finish — neither exists yet.
// 2. **Agent-side registration** — the owner's device has to be
//    running the KinBridge agent and registered with hbbs
//    (`register_pk` in the Rust core). That happens automatically at
//    app launch today, but only against the LAN relay. Once
//    libtailscale is embedded, it'll happen over the tailnet.
// 3. **`gFFI.imageModel.addCallbackOnFirstImage`** — we hook it in
//    [connect] to flip `connecting → connected`. Works today — the
//    hook fires on first decoded frame regardless of codec.

import 'package:flutter/foundation.dart';

import '../../common.dart' show closeConnection, gFFI;

enum KBRemoteState {
  /// No connection attempt in flight, nothing to tear down.
  idle,

  /// `gFFI.start` has been called. Waiting for hbbs rendezvous,
  /// codec negotiation, and the first decoded frame.
  connecting,

  /// First frame has been decoded. The Texture is ready to render.
  connected,

  /// Connection attempt failed (auth, network, or peer offline).
  /// [KBRemoteConnection.errorMessage] has the last human-readable
  /// error. Caller should show it to the user and allow retry.
  failed,
}

class KBRemoteConnection {
  KBRemoteConnection._();
  static final KBRemoteConnection instance = KBRemoteConnection._();

  /// Drives the [_RemoteViewSurface] in `LiveSessionPage`. Listen in
  /// `initState`, rebuild on change, cancel listener in `dispose`.
  final ValueNotifier<KBRemoteState> state =
      ValueNotifier(KBRemoteState.idle);

  /// Peer's RustDesk ID for the active connection (or last-attempted).
  /// Null when [state] == idle.
  String? peerId;

  /// Human-readable error when [state] == failed. Safe to show in a
  /// Snackbar. Cleared on the next successful [connect].
  String? errorMessage;

  /// Kick off a connection to [peerId] using the short-lived token
  /// returned by `/v1/sessions/:id/resolve` (`rendezvous_token`).
  ///
  /// If a session is already in flight we tear it down first — the
  /// Rust core only supports one session at a time.
  Future<void> connect({
    required String peerId,
    String? password,
    String? connToken,
    bool forceRelay = true,
  }) async {
    if (state.value != KBRemoteState.idle) {
      if (kDebugMode) {
        debugPrint(
            'kb.remote: connect() while state=${state.value.name}; tearing down first');
      }
      await disconnect();
    }

    this.peerId = peerId;
    errorMessage = null;
    state.value = KBRemoteState.connecting;

    try {
      gFFI.start(
        peerId,
        password: password,
        isSharedPassword: password != null,
        connToken: connToken,
        forceRelay: forceRelay,
      );
      // Flip to `connected` once the first decoded frame arrives.
      // Works across codec types (VP8/VP9/AV1/H264/H265) because the
      // callback is at the post-decode stage.
      gFFI.imageModel.addCallbackOnFirstImage((String _) {
        if (state.value == KBRemoteState.connecting) {
          state.value = KBRemoteState.connected;
        }
      });
    } catch (err, st) {
      errorMessage = err.toString();
      state.value = KBRemoteState.failed;
      if (kDebugMode) {
        debugPrint('kb.remote: connect failed: $err\n$st');
      }
    }
  }

  /// Tear down the active session. Safe to call when idle.
  Future<void> disconnect() async {
    final id = peerId;
    peerId = null;
    if (id != null) {
      // RustDesk-side close. Synchronous in practice (the Rust core
      // handles cleanup asynchronously, but the Dart side returns
      // immediately).
      closeConnection(id: id);
    }
    state.value = KBRemoteState.idle;
  }

  /// Record a failure surfaced by the caller (e.g., `/v1/sessions/:id/resolve`
  /// returning 403, or the upstream relay timing out). Flips to `failed`
  /// without touching `gFFI`.
  void recordFailure(String reason) {
    errorMessage = reason;
    state.value = KBRemoteState.failed;
  }
}
