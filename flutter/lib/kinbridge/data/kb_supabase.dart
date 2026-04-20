// Supabase client + auth shell for KinBridge.
//
// One Supabase project (shared by dev/preview/prod per Lovable Cloud). The
// anon key is publishable — safe to ship in the APK. See
//   D:\KinBridge\lovable-docs\SERVER_FUNCTIONS.md (§"Base URL")
//   D:\KinBridge\lovable-docs\SUPABASE_SCHEMA.md (§"Auth model summary")
//
// Call [KBSupabase.init] exactly once at app boot (see main.dart) before any
// Dart-side Supabase call. Flutter hot-reload keeps the singleton across
// reloads, so init is idempotent.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import 'kb_repository.dart';
import 'kb_supabase_repository.dart';

class KBSupabase {
  KBSupabase._();

  /// Shared Supabase project used by dashboard + APK. Anon key is the
  /// publishable key and is intentionally in the client. RLS policies (see
  /// SUPABASE_SCHEMA.md) are what enforce tenant isolation, not the key.
  static const _url = 'https://fqqswguifsyjxrvglnmk.supabase.co';
  static const _anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZxcXN3Z3VpZnN5anhydmdsbm1rIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY1MjM0NDYsImV4cCI6MjA5MjA5OTQ0Nn0.srYei0JuqAOWBOSS9-XGqlVjPeCGOC2itfz2Flk39k8';

  static SupabaseClient? _client;

  /// Bootstraps the Supabase singleton. Safe to call repeatedly (idempotent).
  /// PKCE is configured so the `kinbridge://auth-callback` deep-link path
  /// (handled in common.dart via uni_links) works with
  /// `client.auth.getSessionFromUrl(uri)`.
  ///
  /// On completion this also installs an auth-state listener that rebinds
  /// [KBRepository.instance] — signed-in → [SupabaseKBRepository],
  /// signed-out → [FakeKBRepository]. So callers never have to flip the
  /// repo themselves; auth is the source of truth.
  static Future<void> init() async {
    if (_client != null) return;
    _client = SupabaseClient(
      _url,
      _anonKey,
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.pkce),
    );
    _bindRepositoryToAuth();
    // Session restoration lands with the PKCE deep-link in step 5 (pure-Dart
    // SDK persistence is caller-managed). Cold-boot today starts signed-out.
  }

  static StreamSubscription<AuthState>? _authSub;

  static void _bindRepositoryToAuth() {
    final c = _client;
    if (c == null) return;
    _applyAuth(c.auth.currentUser);
    _authSub?.cancel();
    _authSub = c.auth.onAuthStateChange.listen((state) {
      _applyAuth(state.session?.user);
    });
  }

  static void _applyAuth(User? user) {
    final wasAuthed = KBRepository.instance is SupabaseKBRepository;
    if (user != null && !wasAuthed) {
      KBRepository.instance = SupabaseKBRepository();
      if (kDebugMode) {
        debugPrint('kb.auth: repository -> SupabaseKBRepository (uid=${user.id})');
      }
    } else if (user == null && wasAuthed) {
      KBRepository.instance = FakeKBRepository();
      if (kDebugMode) {
        debugPrint('kb.auth: repository -> FakeKBRepository (signed out)');
      }
    }
  }

  static SupabaseClient get client {
    final c = _client;
    if (c == null) {
      throw StateError(
          'KBSupabase.init() must be awaited before using the client');
    }
    return c;
  }

  /// Current signed-in user id (`auth.uid()` in Postgres). Null when the
  /// session isn't hydrated yet.
  static String? get userId => _client?.auth.currentUser?.id;

  /// Short-lived access token for `Authorization: Bearer <…>` on server-fn
  /// POSTs. May return null if the session has lapsed; the Supabase SDK
  /// refreshes on its own most of the time.
  static String? get accessToken => _client?.auth.currentSession?.accessToken;

  /// Convenience for email/password sign-in (step V-b-2 — the simplest path
  /// to test the repo end-to-end before PKCE deep-link is wired).
  static Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) =>
      client.auth.signInWithPassword(email: email, password: password);

  static Future<void> signOut() => client.auth.signOut();

  /// Auth state stream — subscribe at app boot to refresh caches + repo
  /// state when the user signs in/out.
  static Stream<AuthState> authStateChanges() =>
      client.auth.onAuthStateChange;
}
